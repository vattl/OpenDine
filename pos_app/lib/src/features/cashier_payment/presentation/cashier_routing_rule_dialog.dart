import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_components.dart';
import '../data/cashier_payment_repository.dart';
import '../domain/cashier_payment_config.dart';

/// 门店商户分流路由规则新增 / 编辑弹窗
class CashierRoutingRuleDialog extends StatefulWidget {
  const CashierRoutingRuleDialog({
    super.key,
    required this.repository,
    required this.channel,
    this.initialRule,
    this.availableMerchants = const [],
  });

  final CashierPaymentRepository repository;
  final PaymentChannel channel;
  final PaymentRoutingRule? initialRule;
  final List<PaymentMerchant> availableMerchants;

  @override
  State<CashierRoutingRuleDialog> createState() =>
      _CashierRoutingRuleDialogState();
}

class _CashierRoutingRuleDialogState extends State<CashierRoutingRuleDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _ruleNameController;
  late final TextEditingController _priorityController;
  late final TextEditingController _remarkController;
  late final TextEditingController _minPaidController;
  late final TextEditingController _maxPaidController;
  late final TextEditingController _keywordsController;
  late final TextEditingController _startTimeController;
  late final TextEditingController _endTimeController;

  late String _targetMerchantKey;
  late String _matchMode; // ALL or ANY
  late bool _enabled;
  late Set<String> _selectedDiningTypes;
  late String _goodsMatchMode; // CONTAINS_ANY, CONTAINS_ALL, ONLY

  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final rule = widget.initialRule;
    final cond = rule?.conditions;

    _ruleNameController = TextEditingController(text: rule?.ruleName ?? '');
    _priorityController = TextEditingController(
      text: (rule?.priority ?? 100).toString(),
    );
    _remarkController = TextEditingController(text: rule?.remark ?? '');
    _minPaidController = TextEditingController(
      text: cond?.minPaidYuan != null ? cond!.minPaidYuan!.toStringAsFixed(2) : '',
    );
    _maxPaidController = TextEditingController(
      text: cond?.maxPaidYuan != null ? cond!.maxPaidYuan!.toStringAsFixed(2) : '',
    );
    _keywordsController = TextEditingController(
      text: cond?.goodsMatch?.goodsNameKeywords.join(', ') ?? '',
    );
    _startTimeController = TextEditingController(
      text: cond?.timeRange?.startTime ?? '',
    );
    _endTimeController = TextEditingController(
      text: cond?.timeRange?.endTime ?? '',
    );

    // 默认商户键处理
    final availableKeys = widget.availableMerchants.map((m) => m.merchantKey).toList();
    if (rule != null && rule.targetMerchantKey.isNotEmpty) {
      _targetMerchantKey = rule.targetMerchantKey;
    } else if (availableKeys.contains('small_amount')) {
      _targetMerchantKey = 'small_amount';
    } else if (availableKeys.isNotEmpty) {
      _targetMerchantKey = availableKeys.first;
    } else {
      _targetMerchantKey = 'default';
    }

    _matchMode = rule?.matchMode ?? 'ALL';
    _enabled = rule?.enabled ?? true;
    _selectedDiningTypes = (cond?.diningTypes ?? []).toSet();
    _goodsMatchMode = cond?.goodsMatch?.mode ?? 'CONTAINS_ANY';
  }

  @override
  void dispose() {
    _ruleNameController.dispose();
    _priorityController.dispose();
    _remarkController.dispose();
    _minPaidController.dispose();
    _maxPaidController.dispose();
    _keywordsController.dispose();
    _startTimeController.dispose();
    _endTimeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;

    final ruleName = _ruleNameController.text.trim();
    if (ruleName.isEmpty) {
      setState(() => _error = '规则名称不能为空');
      return;
    }

    final priority = int.tryParse(_priorityController.text.trim()) ?? 100;
    final minPaid = double.tryParse(_minPaidController.text.trim());
    final maxPaid = double.tryParse(_maxPaidController.text.trim());
    if (minPaid != null && maxPaid != null && minPaid > maxPaid) {
      setState(() => _error = '最小实付金额不能大于最大金额');
      return;
    }

    // 解析商品关键字
    final keywords = _keywordsController.text
        .split(RegExp(r'[,，\s]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    GoodsMatchCondition? goodsMatch;
    if (keywords.isNotEmpty) {
      goodsMatch = GoodsMatchCondition(
        goodsNameKeywords: keywords,
        mode: _goodsMatchMode,
      );
    }

    TimeRangeCondition? timeRange;
    final st = _startTimeController.text.trim();
    final et = _endTimeController.text.trim();
    if (st.isNotEmpty || et.isNotEmpty) {
      timeRange = TimeRangeCondition(
        startTime: st,
        endTime: et,
      );
    }

    final conditions = PaymentRoutingConditions(
      diningTypes: _selectedDiningTypes.toList(),
      minPaidYuan: minPaid,
      maxPaidYuan: maxPaid,
      goodsMatch: goodsMatch,
      timeRange: timeRange,
    );

    final payload = <String, Object?>{
      'channel': widget.channel.code,
      'ruleName': ruleName,
      'priority': priority,
      'enabled': _enabled,
      'targetMerchantKey': _targetMerchantKey,
      'matchMode': _matchMode,
      'conditions': conditions.toJson(),
      'remark': _remarkController.text.trim(),
    };

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.repository.saveRoutingRule(
        id: widget.initialRule?.id,
        data: payload,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialRule != null;
    return CashierDialogFrame(
      title: isEdit ? '编辑商户分流路由规则' : '新增商户分流路由规则',
      subtitle: '${widget.channel.label} · 多条件组合判定与优先级分流',
      width: 760,
      height: 720,
      busy: _busy,
      onClose: () => Navigator.of(context).pop(false),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          minimumWidth: 100,
          height: 48,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
        CashierActionButton(
          key: const Key('cashier-routing-rule-save-btn'),
          label: '保存生效',
          minimumWidth: 140,
          height: 48,
          busy: _busy,
          onPressed: _submit,
        ),
      ],
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),

              // 基础信息区
              _buildSectionTitle('基础参数'),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      key: const Key('cashier-routing-rule-name-input'),
                      controller: _ruleNameController,
                      decoration: const InputDecoration(
                        labelText: '规则名称 *',
                        hintText: '如: 三文鱼生鲜专线、外卖自提小额分流',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? '请输入规则名称' : null,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const Key('cashier-routing-rule-priority-input'),
                      controller: _priorityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '优先级数值 *',
                        hintText: '越大越优先 (如 150)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 目标商户号选择
              DropdownButtonFormField<String>(
                key: const Key('cashier-routing-rule-merchant-dropdown'),
                initialValue: _targetMerchantKey,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '目标商户号 *',
                  helperText: '命中的订单将以此商户配置发起收款（若凭据未就绪将自动降级至主商户保护）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  if (widget.availableMerchants.isEmpty)
                    const DropdownMenuItem(
                      value: 'default',
                      child: Text('默认主商户 (default)'),
                    )
                  else
                    for (final m in widget.availableMerchants)
                      DropdownMenuItem(
                        value: m.merchantKey,
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: m.payReady
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFFF59E0B),
                              ),
                            ),
                            Text(
                              '${m.merchantKey} (${m.mchId.isNotEmpty ? m.mchId : "未配mchId"}) · ${m.payReady ? "凭据就绪" : "凭据未就绪"}',
                              style: TextStyle(
                                fontWeight: m.merchantKey == 'default'
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _targetMerchantKey = val);
                },
              ),
              const SizedBox(height: 14),

              // 条件判定关系
              Row(
                children: [
                  const Text(
                    '多条件逻辑关系：',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('满足所有条件 (AND)'),
                    selected: _matchMode == 'ALL',
                    onSelected: (sel) {
                      if (sel) setState(() => _matchMode = 'ALL');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('满足任一条件 (OR)'),
                    selected: _matchMode == 'ANY',
                    onSelected: (sel) {
                      if (sel) setState(() => _matchMode = 'ANY');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 14),

              SwitchListTile(
                title: const Text('立即启用此规则'),
                subtitle: const Text('停用后此规则不参与结账分流，保留配置供后续随时恢复'),
                value: _enabled,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _enabled = v),
              ),

              const Divider(height: 32),

              // 多维度条件设定
              _buildSectionTitle('多维度生效条件（选填，未设置则代表不限制该维度）'),
              const SizedBox(height: 12),

              // 1. 就餐方式
              const Text(
                '1. 就餐方式 (Dining Types)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                children: ['堂食', '打包', '外卖自提'].map((type) {
                  final checked = _selectedDiningTypes.contains(type);
                  return FilterChip(
                    label: Text(type),
                    selected: checked,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDiningTypes.add(type);
                        } else {
                          _selectedDiningTypes.remove(type);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // 2. 实付金额区间
              const Text(
                '2. 订单实付金额区间 (元)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minPaidController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '最低金额 (¥)',
                        hintText: '如 50.00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('~', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _maxPaidController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: '最高金额 (¥)',
                        hintText: '如 200.00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. 菜品商品关键字匹配
              const Text(
                '3. 菜品商品匹配规则',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      initialValue: _goodsMatchMode,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '匹配模式',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'CONTAINS_ANY',
                          child: Text('包含任一 (ANY)', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'CONTAINS_ALL',
                          child: Text('包含全部 (ALL)', overflow: TextOverflow.ellipsis),
                        ),
                        DropdownMenuItem(
                          value: 'ONLY',
                          child: Text('整单仅限此菜品', overflow: TextOverflow.ellipsis),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _goodsMatchMode = val);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _keywordsController,
                      decoration: const InputDecoration(
                        labelText: '菜品名称关键字',
                        hintText: '多个词请用逗号或空格分隔，如: 三文鱼, 刺身',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 4. 生效时段
              const Text(
                '4. 生效时段 (24小时制 HH:mm)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _startTimeController,
                      decoration: const InputDecoration(
                        labelText: '开始时间',
                        hintText: '10:00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Text('~', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: TextFormField(
                      controller: _endTimeController,
                      decoration: const InputDecoration(
                        labelText: '结束时间',
                        hintText: '22:00',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 备注
              TextFormField(
                controller: _remarkController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '规则备注说明 (选填)',
                  hintText: '简要记录此条分流规则的业务背景与用途',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0F172A),
      ),
    );
  }
}
