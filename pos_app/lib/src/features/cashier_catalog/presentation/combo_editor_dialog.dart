import 'dart:math';
import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/cashier_catalog_repository.dart';
import '../domain/cashier_dish.dart';
import '../domain/combo_definition_models.dart';
import 'combo_dish_selector_dialog.dart';

class ComboEditorDialog extends StatefulWidget {
  const ComboEditorDialog({
    super.key,
    required this.headerDish,
    required this.repository,
    required this.categories,
    required this.allDishes,
  });

  final CashierDish headerDish;
  final CashierCatalogRepository repository;
  final List<CashierDishCategory> categories;
  final List<CashierDish> allDishes;

  static Future<bool?> show({
    required BuildContext context,
    required CashierDish headerDish,
    required CashierCatalogRepository repository,
    required List<CashierDishCategory> categories,
    required List<CashierDish> allDishes,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ComboEditorDialog(
        headerDish: headerDish,
        repository: repository,
        categories: categories,
        allDishes: allDishes,
      ),
    );
  }

  @override
  State<ComboEditorDialog> createState() => _ComboEditorDialogState();
}

class _ComboEditorDialogState extends State<ComboEditorDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _comboType = 'groups';
  String _editorSection = 'content';
  int _status = 1;
  List<ComboFixedItemModel> _fixedItems = [];
  List<ComboGroupModel> _groups = [];
  int? _limitPerOrder;
  int? _limitPerUser;
  String _limitCycle = 'daily';
  String? _startTime;
  String? _endTime;
  String? _timeRangeStart;
  String? _timeRangeEnd;
  Set<int> _availableDays = {};
  String _applyDiningType = 'all';
  bool _allowCoupon = true;
  int? _dailyStock;

  Map<int, CashierDish> get _dishMap => {
    for (final d in widget.allDishes) d.id: d,
  };

  @override
  void initState() {
    super.initState();
    _loadComboDetail();
  }

  Future<void> _loadComboDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.repository.getComboDetail(
        widget.headerDish.id,
      );
      final def = response.definition;
      if (def != null) {
        _comboType = def.comboType;
        _status = def.status;
        _fixedItems = def.fixedItems.map(_attachFixedDishInfo).toList();
        _groups = def.groups.map(_attachGroupDishInfo).toList();
        _limitPerOrder = def.limitPerOrder;
        _limitPerUser = def.limitPerUser;
        _limitCycle = def.limitCycle;
        _startTime = def.startTime;
        _endTime = def.endTime;
        _timeRangeStart = def.timeRangeStart;
        _timeRangeEnd = def.timeRangeEnd;
        _availableDays = (def.availableDays ?? '')
            .split(',')
            .map((value) => int.tryParse(value.trim()))
            .whereType<int>()
            .toSet();
        _applyDiningType = def.applyDiningType;
        _allowCoupon = def.allowCoupon;
        _dailyStock = def.dailyStock;
      } else {
        _comboType = 'groups';
        _status = 1;
        _fixedItems = [];
        _groups = [];
      }
    } catch (e) {
      _error = '加载套餐配置失败：$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  ComboFixedItemModel _attachFixedDishInfo(ComboFixedItemModel item) {
    final dish = _dishMap[item.componentDishId];
    if (dish != null) {
      return item.attachDishInfo(dish);
    }
    return item;
  }

  ComboGroupModel _attachGroupDishInfo(ComboGroupModel group) {
    return group.copyWith(
      items: group.items.map((it) {
        final dish = _dishMap[it.componentDishId];
        return dish != null ? it.attachDishInfo(dish) : it;
      }).toList(),
    );
  }

  double get _fixedItemsTotal {
    return _fixedItems.fold(
      0.0,
      (sum, it) => sum + (it.dishPrice * it.qtyPerCombo),
    );
  }

  (double, double) get _groupsValueRange {
    if (_comboType == 'fixed' || _groups.isEmpty) {
      return (0.0, 0.0);
    }
    double minTotal = 0.0;
    double maxTotal = 0.0;
    for (final g in _groups) {
      if (g.items.isEmpty) continue;
      final prices = g.items.map((it) => it.dishPrice + it.extraPrice).toList()
        ..sort();
      final minCount = max(0, min(g.minPick, prices.length));
      final maxCount = max(minCount, min(g.maxPick, prices.length));

      for (var i = 0; i < minCount; i++) {
        minTotal += prices[i];
      }
      final reversedPrices = prices.reversed.toList();
      for (var i = 0; i < maxCount; i++) {
        maxTotal += reversedPrices[i];
      }
    }
    return (minTotal, maxTotal);
  }

  double get _maxSavings {
    final (_, maxGroupVal) = _groupsValueRange;
    final totalRawMax = _fixedItemsTotal + maxGroupVal;
    return max(0.0, totalRawMax - widget.headerDish.price);
  }

  Future<void> _addFixedItems() async {
    final excluded = _fixedItems.map((e) => e.componentDishId).toSet()
      ..add(widget.headerDish.id);
    final selected = await ComboDishSelectorDialog.show(
      context: context,
      allDishes: widget.allDishes,
      categories: widget.categories,
      excludedDishIds: excluded,
      title: '添加固定子菜',
    );
    if (selected != null && selected.isNotEmpty) {
      setState(() {
        for (final dish in selected) {
          _fixedItems.add(
            ComboFixedItemModel(
              componentDishId: dish.id,
              qtyPerCombo: 1,
              sortOrder: _fixedItems.length,
              dishName: dish.name,
              dishPrice: dish.price,
              dishImage: dish.image,
            ),
          );
        }
      });
    }
  }

  Future<void> _addGroupItems(int groupIndex) async {
    final group = _groups[groupIndex];
    final excluded = group.items.map((e) => e.componentDishId).toSet()
      ..add(widget.headerDish.id);
    final selected = await ComboDishSelectorDialog.show(
      context: context,
      allDishes: widget.allDishes,
      categories: widget.categories,
      excludedDishIds: excluded,
      title: '为【${group.title.isEmpty ? "分组" : group.title}】添加候选菜品',
    );
    if (selected != null && selected.isNotEmpty) {
      setState(() {
        final newItems = List<ComboGroupItemModel>.from(group.items);
        for (final dish in selected) {
          newItems.add(
            ComboGroupItemModel(
              componentDishId: dish.id,
              extraPrice: 0.0,
              sortOrder: newItems.length,
              dishName: dish.name,
              dishPrice: dish.price,
              dishImage: dish.image,
            ),
          );
        }
        _groups[groupIndex] = group.copyWith(items: newItems);
      });
    }
  }

  void _addNewGroup() {
    setState(() {
      final key = 'g_${DateTime.now().millisecondsSinceEpoch % 100000}';
      _groups.add(
        ComboGroupModel(
          groupKey: key,
          title: '自选分组 ${_groups.length + 1}',
          minPick: 1,
          maxPick: 1,
          sortOrder: _groups.length,
          items: [],
        ),
      );
    });
  }

  Future<void> _saveCombo() async {
    if (_fixedItems.isEmpty && (_comboType == 'fixed' || _groups.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('套餐必须包含至少一个固定子菜或自选分组！')));
      return;
    }

    if (_comboType == 'groups') {
      for (var i = 0; i < _groups.length; i++) {
        final g = _groups[i];
        if (g.title.trim().isEmpty) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('第 ${i + 1} 个分组标题不能为空！')));
          return;
        }
        if (g.minPick < 0 || g.minPick > g.maxPick) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('分组【${g.title}】的选菜规则不合法（最少选不得大于最多选）！')),
          );
          return;
        }
        if (g.items.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('分组【${g.title}】必须包含至少一个候选单品！')),
          );
          return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      final req = ComboSaveRequest(
        dishId: widget.headerDish.id,
        comboType: _comboType,
        status: _status,
        fixedItems: _fixedItems,
        groups: _comboType == 'fixed' ? [] : _groups,
        limitPerOrder: _limitPerOrder,
        limitPerUser: _limitPerUser,
        limitCycle: _limitCycle,
        startTime: _startTime,
        endTime: _endTime,
        availableDays: _availableDays.isEmpty
            ? null
            : (_availableDays.toList()..sort()).join(','),
        timeRangeStart: _timeRangeStart,
        timeRangeEnd: _timeRangeEnd,
        applyDiningType: _applyDiningType,
        allowCoupon: _allowCoupon,
        dailyStock: _dailyStock,
      );
      await widget.repository.saveCombo(req);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('套餐配置保存成功！')));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cashier = context.cashier;
    final (minGroupVal, maxGroupVal) = _groupsValueRange;
    final totalRawMin = _fixedItemsTotal + minGroupVal;
    final totalRawMax = _fixedItemsTotal + maxGroupVal;

    return Dialog(
      backgroundColor: cashier.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cashier.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1240, maxHeight: 820),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: cashier.canvas,
                border: Border(bottom: BorderSide(color: cashier.border)),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    '套餐可视化配置器',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: cashier.ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x338B5CF6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0x668B5CF6)),
                    ),
                    child: Text(
                      '${widget.headerDish.name} (售价: ¥${widget.headerDish.price.toStringAsFixed(2)})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC4B5FD),
                      ),
                    ),
                  ),
                  const Spacer(),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'content',
                        label: Text('内容编排', style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: 'rules',
                        label: Text('售卖规则', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {_editorSection},
                    onSelectionChanged: (selection) =>
                        setState(() => _editorSection = selection.first),
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 模式选择
                  if (_editorSection == 'content')
                    Row(
                      children: [
                        Text(
                          '配置模式: ',
                          style: TextStyle(
                            fontSize: 13,
                            color: cashier.inkSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'groups',
                              label: Text(
                                '分组自选',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            ButtonSegment(
                              value: 'fixed',
                              label: Text(
                                '全固定组合',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                          selected: {_comboType},
                          onSelectionChanged: (newSelection) {
                            if (newSelection.isNotEmpty) {
                              setState(() => _comboType = newSelection.first);
                            }
                          },
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: Icon(Icons.close, color: cashier.inkSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 主体内容
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: _loadComboDetail,
                            child: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(20),
                      child: _editorSection == 'content'
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: _buildFixedItemsPanel(cashier)),
                                const SizedBox(width: 20),
                                Expanded(
                                  child: _buildOptionGroupsPanel(cashier),
                                ),
                              ],
                            )
                          : _buildCommercialRulesLayout(cashier),
                    ),
            ),

            // 底部价格测算与省钱卡片 + 保存按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: cashier.canvas,
                border: Border(top: BorderSide(color: cashier.border)),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(14),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          cashier.selected.withValues(alpha: 0.12),
                          const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: cashier.selected.withValues(alpha: 0.3),
                      ),
                    ),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 700),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildSummaryItem(
                              '套餐售价',
                              '¥${widget.headerDish.price.toStringAsFixed(2)}',
                              cashier.ink,
                            ),
                            Text(
                              '|',
                              style: TextStyle(
                                color: cashier.border,
                                fontSize: 18,
                              ),
                            ),
                            _buildSummaryItem(
                              '固定项原价合计',
                              '¥${_fixedItemsTotal.toStringAsFixed(2)}',
                              cashier.ink,
                            ),
                            Text(
                              '+',
                              style: TextStyle(
                                color: cashier.border,
                                fontSize: 18,
                              ),
                            ),
                            _buildSummaryItem(
                              '自选组合总价值区间',
                              _comboType == 'fixed'
                                  ? '无自选项'
                                  : '¥${minGroupVal.toStringAsFixed(2)} ~ ¥${maxGroupVal.toStringAsFixed(2)}',
                              cashier.ink,
                            ),
                            Text(
                              '=',
                              style: TextStyle(
                                color: cashier.border,
                                fontSize: 18,
                              ),
                            ),
                            _buildSummaryItem(
                              '单品总原价值区间',
                              _comboType == 'fixed'
                                  ? '¥${_fixedItemsTotal.toStringAsFixed(2)}'
                                  : '¥${totalRawMin.toStringAsFixed(2)} ~ ¥${totalRawMax.toStringAsFixed(2)}',
                              cashier.ink,
                            ),
                            Text(
                              '|',
                              style: TextStyle(
                                color: cashier.border,
                                fontSize: 18,
                              ),
                            ),
                            _buildSummaryItem(
                              '预计为顾客最高省',
                              '¥${_maxSavings.toStringAsFixed(2)}',
                              const Color(0xFF10B981),
                              isHighlight: true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: cashier.ink,
                          side: BorderSide(color: cashier.border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        child: const Text('放弃并关闭'),
                      ),
                      const SizedBox(width: 14),
                      ElevatedButton(
                        onPressed: _saving ? null : _saveCombo,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: cashier.selected,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 12,
                          ),
                        ),
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                '保存套餐配置',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(
    String label,
    String value,
    Color color, {
    bool isHighlight = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: isHighlight ? 18 : 16,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }

  int? _positiveOrNull(String value) {
    final parsed = int.tryParse(value.trim());
    return parsed != null && parsed > 0 ? parsed : null;
  }

  String? _textOrNull(String value) {
    final text = value.trim();
    return text.isEmpty ? null : text;
  }

  Widget _buildCommercialRulesLayout(CashierTokens cashier) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rules = _buildCommercialRulesPanel(cashier);
        if (constraints.maxWidth < 900) return rules;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: rules),
            const SizedBox(width: 16),
            SizedBox(width: 292, child: _buildCommercialSummaryPanel(cashier)),
          ],
        );
      },
    );
  }

  Widget _buildCommercialSummaryPanel(CashierTokens cashier) {
    final selectedDays = _availableDays.toList()..sort();
    final dayLabel = selectedDays.isEmpty
        ? '每天'
        : selectedDays
              .map(
                (day) =>
                    '周${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
              )
              .join('、');
    final diningLabel = switch (_applyDiningType) {
      'dine_in' => '仅堂食',
      'take_out' => '仅打包',
      _ => '全部用餐方式',
    };
    return Container(
      key: const Key('combo-commercial-summary'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cashier.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cashier.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '规则摘要',
            style: TextStyle(
              color: cashier.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '收银端将按以下规则提前解释与阻断，最终以服务端校验为准。',
            style: TextStyle(
              color: cashier.inkMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          _buildCommercialSummaryRow(
            cashier,
            '售卖日期',
            _startTime == null && _endTime == null
                ? '不限制'
                : '${_startTime ?? '现在'} 至 ${_endTime ?? '长期'}',
          ),
          _buildCommercialSummaryRow(
            cashier,
            '可售时间',
            '$dayLabel  ${_timeRangeStart ?? '全天'}${_timeRangeEnd == null ? '' : '–$_timeRangeEnd'}',
          ),
          _buildCommercialSummaryRow(
            cashier,
            '限购',
            '每单 ${_limitPerOrder ?? '不限'} 份 / 每人${_limitCycle == 'lifetime' ? '活动期' : '每日'} ${_limitPerUser ?? '不限'} 份',
          ),
          _buildCommercialSummaryRow(
            cashier,
            '每日配额',
            _dailyStock == null ? '不限制' : '$_dailyStock 份',
          ),
          _buildCommercialSummaryRow(cashier, '用餐方式', diningLabel),
          _buildCommercialSummaryRow(
            cashier,
            '优惠券',
            _allowCoupon ? '允许叠加' : '不参与',
            valueColor: _allowCoupon ? null : cashier.warning,
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _buildCommercialSummaryRow(
    CashierTokens cashier,
    String label,
    String value, {
    Color? valueColor,
    bool showDivider = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: showDivider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: cashier.border)),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: cashier.inkMuted, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? cashier.ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommercialRulesPanel(CashierTokens cashier) {
    return ListView(
      key: const Key('combo-commercial-rules'),
      children: [
        _buildRuleSection(
          cashier,
          title: '就餐方式与优惠券',
          subtitle: '先设置套餐适用的就餐场景，以及套餐金额是否参与优惠券门槛与折扣。',
          children: [
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                key: const Key('combo-dining-type'),
                initialValue: _applyDiningType,
                decoration: const InputDecoration(
                  labelText: '用餐方式',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('全部')),
                  DropdownMenuItem(value: 'dine_in', child: Text('仅堂食')),
                  DropdownMenuItem(value: 'take_out', child: Text('仅打包')),
                ],
                onChanged: (value) =>
                    setState(() => _applyDiningType = value ?? 'all'),
              ),
            ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<bool>(
                key: const Key('combo-allow-coupon'),
                initialValue: _allowCoupon,
                decoration: const InputDecoration(
                  labelText: '优惠券叠加',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: true, child: Text('允许参与优惠券')),
                  DropdownMenuItem(value: false, child: Text('不参与优惠券')),
                ],
                onChanged: (value) =>
                    setState(() => _allowCoupon = value ?? true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildRuleSection(
          cashier,
          title: '售卖时间',
          subtitle: '不设置的条件视为不限制；最终以下单校验为准。',
          children: [
            _ruleField(
              key: const Key('combo-start-time'),
              label: '生效时间',
              initialValue: _startTime,
              hint: '例如 2026-10-20 00:00:00',
              onChanged: (value) =>
                  setState(() => _startTime = _textOrNull(value)),
            ),
            _ruleField(
              key: const Key('combo-end-time'),
              label: '结束时间',
              initialValue: _endTime,
              hint: '例如 2026-12-31 23:59:59',
              onChanged: (value) =>
                  setState(() => _endTime = _textOrNull(value)),
            ),
            _ruleField(
              label: '每日开始',
              initialValue: _timeRangeStart,
              hint: '11:00:00',
              onChanged: (value) =>
                  setState(() => _timeRangeStart = _textOrNull(value)),
            ),
            _ruleField(
              label: '每日结束',
              initialValue: _timeRangeEnd,
              hint: '14:00:00',
              onChanged: (value) =>
                  setState(() => _timeRangeEnd = _textOrNull(value)),
            ),
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '可售星期',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: cashier.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(
                            '周${const ['一', '二', '三', '四', '五', '六', '日'][day - 1]}',
                          ),
                          selected: _availableDays.contains(day),
                          onSelected: (selected) => setState(() {
                            if (selected) {
                              _availableDays.add(day);
                            } else {
                              _availableDays.remove(day);
                            }
                          }),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildRuleSection(
          cashier,
          title: '限购与配额',
          subtitle: '留空或 0 表示不限；同一订单中的套餐数量合并计算。',
          children: [
            _ruleField(
              key: const Key('combo-limit-per-order'),
              label: '每单限购',
              initialValue: _limitPerOrder?.toString(),
              hint: '不限',
              numeric: true,
              onChanged: (value) =>
                  setState(() => _limitPerOrder = _positiveOrNull(value)),
            ),
            _ruleField(
              label: '每日配额',
              initialValue: _dailyStock?.toString(),
              hint: '不限',
              numeric: true,
              onChanged: (value) =>
                  setState(() => _dailyStock = _positiveOrNull(value)),
            ),
            _ruleField(
              label: '每人限购',
              initialValue: _limitPerUser?.toString(),
              hint: '不限',
              numeric: true,
              onChanged: (value) =>
                  setState(() => _limitPerUser = _positiveOrNull(value)),
            ),
            SizedBox(
              width: 300,
              child: DropdownButtonFormField<String>(
                initialValue: _limitCycle,
                decoration: const InputDecoration(
                  labelText: '限购周期',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('每日')),
                  DropdownMenuItem(value: 'lifetime', child: Text('永久')),
                ],
                onChanged: (value) =>
                    setState(() => _limitCycle = value ?? 'daily'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRuleSection(
    CashierTokens cashier, {
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cashier.canvas,
        border: Border.all(color: cashier.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: cashier.ink,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(fontSize: 12, color: cashier.inkSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 14, runSpacing: 14, children: children),
        ],
      ),
    );
  }

  Widget _ruleField({
    Key? key,
    required String label,
    required String? initialValue,
    required String hint,
    required ValueChanged<String> onChanged,
    bool numeric = false,
  }) {
    return SizedBox(
      key: key,
      width: 300,
      child: TextFormField(
        initialValue: initialValue ?? '',
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFixedItemsPanel(CashierTokens cashier) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cashier.canvas,
        border: Border.all(color: cashier.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. 固定子菜 (每套必含)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cashier.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '无论顾客自选何种搭配均默认出餐的餐品',
                      style: TextStyle(
                        fontSize: 11,
                        color: cashier.inkSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('添加固定子菜', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cashier.selected,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                ),
                onPressed: _addFixedItems,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _fixedItems.isEmpty
                ? Center(
                    child: Text(
                      '暂无固定子菜，点击右上角添加',
                      style: TextStyle(
                        color: cashier.inkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: _fixedItems.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: cashier.border),
                    itemBuilder: (ctx, index) {
                      final it = _fixedItems[index];
                      final subtotal = it.dishPrice * it.qtyPerCombo;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    it.dishName.isNotEmpty
                                        ? it.dishName
                                        : '菜品 ID: ${it.componentDishId}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: cashier.ink,
                                    ),
                                  ),
                                  Text(
                                    '单价: ¥${it.dishPrice.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cashier.inkSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: cashier.border),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: it.qtyPerCombo <= 1
                                        ? null
                                        : () {
                                            setState(() {
                                              _fixedItems[index] = it.copyWith(
                                                qtyPerCombo: it.qtyPerCombo - 1,
                                              );
                                            });
                                          },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Icon(
                                        Icons.remove,
                                        size: 14,
                                        color: cashier.ink,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '${it.qtyPerCombo}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: cashier.selected,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(() {
                                        _fixedItems[index] = it.copyWith(
                                          qtyPerCombo: it.qtyPerCombo + 1,
                                        );
                                      });
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Icon(
                                        Icons.add,
                                        size: 14,
                                        color: cashier.ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Text(
                              '¥${subtotal.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: cashier.ink,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: Colors.redAccent,
                              ),
                              onPressed: () {
                                setState(() => _fixedItems.removeAt(index));
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Divider(height: 1, color: cashier.border),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '固定项合计原价: ¥${_fixedItemsTotal.toStringAsFixed(2)}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: cashier.selected,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionGroupsPanel(CashierTokens cashier) {
    final isFixedOnly = _comboType == 'fixed';
    return Opacity(
      opacity: isFixedOnly ? 0.35 : 1.0,
      child: IgnorePointer(
        ignoring: isFixedOnly,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cashier.canvas,
            border: Border.all(color: cashier.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '2. 自选分组 (供顾客选择)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: cashier.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '支持 N 选 M，候选品支持差异化加价规则',
                          style: TextStyle(
                            fontSize: 11,
                            color: cashier.inkSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('添加选择分组', style: TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cashier.selected,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: _addNewGroup,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _groups.isEmpty
                    ? Center(
                        child: Text(
                          isFixedOnly ? '当前为全固定组合模式，无需分组' : '暂无自选分组，点击右上角添加',
                          style: TextStyle(
                            color: cashier.inkSecondary,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _groups.length,
                        itemBuilder: (ctx, gIndex) {
                          final group = _groups[gIndex];
                          return Card(
                            color: cashier.surface,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: cashier.border),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: group.title,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: cashier.ink,
                                          ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                            hintText: '分组标题 (如: 饮品 2 选 1)',
                                            border: UnderlineInputBorder(),
                                          ),
                                          onChanged: (val) {
                                            _groups[gIndex] = group.copyWith(
                                              title: val,
                                            );
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '最少选: ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cashier.inkSecondary,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 32,
                                        child: TextFormField(
                                          initialValue: '${group.minPick}',
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cashier.ink,
                                          ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                          ),
                                          onChanged: (val) {
                                            final num = int.tryParse(val) ?? 1;
                                            _groups[gIndex] = group.copyWith(
                                              minPick: num,
                                            );
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '最多选: ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cashier.inkSecondary,
                                        ),
                                      ),
                                      SizedBox(
                                        width: 32,
                                        child: TextFormField(
                                          initialValue: '${group.maxPick}',
                                          textAlign: TextAlign.center,
                                          keyboardType: TextInputType.number,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: cashier.ink,
                                          ),
                                          decoration: const InputDecoration(
                                            isDense: true,
                                          ),
                                          onChanged: (val) {
                                            final num = int.tryParse(val) ?? 1;
                                            _groups[gIndex] = group.copyWith(
                                              maxPick: num,
                                            );
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: Colors.redAccent,
                                        ),
                                        onPressed: () {
                                          setState(
                                            () => _groups.removeAt(gIndex),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ...group.items.asMap().entries.map((entry) {
                                    final itemIndex = entry.key;
                                    final item = entry.value;
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.dishName.isNotEmpty
                                                      ? item.dishName
                                                      : '菜品 ID: ${item.componentDishId}',
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: cashier.ink,
                                                  ),
                                                ),
                                                Text(
                                                  '原价 ¥${item.dishPrice.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: cashier.inkSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '+¥',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: cashier.inkSecondary,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          SizedBox(
                                            width: 46,
                                            child: TextFormField(
                                              initialValue:
                                                  '${item.extraPrice}',
                                              textAlign: TextAlign.center,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFFF59E0B),
                                                fontWeight: FontWeight.w700,
                                              ),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                              ),
                                              onChanged: (val) {
                                                final p =
                                                    double.tryParse(val) ?? 0.0;
                                                final updatedItems =
                                                    List<
                                                      ComboGroupItemModel
                                                    >.from(group.items);
                                                updatedItems[itemIndex] = item
                                                    .copyWith(extraPrice: p);
                                                _groups[gIndex] = group
                                                    .copyWith(
                                                      items: updatedItems,
                                                    );
                                                setState(() {});
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.close,
                                              size: 16,
                                              color: Colors.grey,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                final updated =
                                                    List<
                                                        ComboGroupItemModel
                                                      >.from(group.items)
                                                      ..removeAt(itemIndex);
                                                _groups[gIndex] = group
                                                    .copyWith(items: updated);
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 6),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      icon: const Icon(Icons.add, size: 14),
                                      label: const Text(
                                        '添加候选单品',
                                        style: TextStyle(fontSize: 11),
                                      ),
                                      onPressed: () => _addGroupItems(gIndex),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
