import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/cashier_settings_repository.dart';
import '../domain/subscribe_template.dart';
import 'cashier_settings_shared.dart';

/// B 端收银设置 - 微信订阅模板管理、通知规则与出餐超时动态阈值配置面板
class CashierSettingsNotificationPage extends StatefulWidget {
  const CashierSettingsNotificationPage({
    super.key,
    required this.repository,
    required this.section,
    this.client,
    this.currentShopId,
    this.onDirtyChanged,
  });

  final CashierSettingsRepository repository;
  final SettingsSectionSpec section;
  final AdminApiClient? client;
  final int? currentShopId;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<CashierSettingsNotificationPage> createState() =>
      _CashierSettingsNotificationPageState();
}

class _CashierSettingsNotificationPageState
    extends State<CashierSettingsNotificationPage> {
  bool _loading = false;
  bool _saving = false;
  String? _error;

  // 1. 订阅模板与审计日志状态
  List<SubscribeSceneTemplate> _templates = [];
  List<SubscribeSendLog> _logs = [];
  final TextEditingController _filterBizNoCtrl = TextEditingController();
  final TextEditingController _filterOpenidCtrl = TextEditingController();
  String? _filterScene;
  String? _filterStatus;

  // 1.1 模板搜索与筛选控制器 (查)
  final TextEditingController _templateSearchCtrl = TextEditingController();
  int? _templateStatusFilter; // null: 全部, 1: 仅启用, 0: 仅停用
  String? _templateTriggerFilter; // null: 全部, SUBMIT_ORDER, PAY_SUCCESS, etc.

  // 2. 动态出餐超时与通知配置
  bool _prepTimeoutEnabled = true;
  int _prepTimeoutMinutes = 15;
  int _repeatIntervalSeconds = 30;

  // 3. 消息通道统计
  Map<String, Object?> _channelStats = const {};

  @override
  void initState() {
    super.initState();
    _loadCurrentSectionData();
  }

  @override
  void dispose() {
    _filterBizNoCtrl.dispose();
    _filterOpenidCtrl.dispose();
    _templateSearchCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CashierSettingsNotificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentShopId != widget.currentShopId ||
        oldWidget.section.id != widget.section.id) {
      _loadCurrentSectionData();
    }
  }

  Future<void> _loadCurrentSectionData() async {
    if (widget.section.id == 'templates') {
      await _loadSubscribeTemplates();
    } else if (widget.section.id == 'deliveries') {
      await _loadSubscribeLogs();
    } else {
      await _loadNotificationConfig();
    }
  }

  // ---------------------------------------------------------------------------
  // 微信订阅模板数据与操作 (增删改查)
  // ---------------------------------------------------------------------------

  /// 查：加载场景模板列表
  Future<void> _loadSubscribeTemplates() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.listSubscribeSceneTemplates();
      if (mounted) {
        setState(() {
          _templates = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// 查：本地多维度组合筛选
  List<SubscribeSceneTemplate> get _filteredTemplates {
    final query = _templateSearchCtrl.text.trim().toLowerCase();
    return _templates.where((t) {
      if (query.isNotEmpty) {
        final inTitle = t.title.toLowerCase().contains(query);
        final inCode = t.sceneCode.toLowerCase().contains(query);
        final inId = t.templateId.toLowerCase().contains(query);
        final inRemark = (t.remark ?? '').toLowerCase().contains(query);
        if (!inTitle && !inCode && !inId && !inRemark) return false;
      }
      if (_templateStatusFilter != null && t.isActive != _templateStatusFilter) {
        return false;
      }
      if (_templateTriggerFilter != null && t.triggerPoint != _templateTriggerFilter) {
        return false;
      }
      return true;
    }).toList();
  }

  /// 改：即时切换启停状态
  Future<void> _toggleTemplateActive(SubscribeSceneTemplate item) async {
    final newActive = item.isActive == 1 ? 0 : 1;
    setState(() => _saving = true);
    try {
      final updated = item.copyWith(isActive: newActive);
      await widget.repository.updateSubscribeSceneTemplate(
        item.sceneCode,
        updated.toJson(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ 场景「${item.title}」已切换为 ${newActive == 1 ? "启用" : "停用"}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      await _loadSubscribeTemplates();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('更新场景状态失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 增 / 改：新增或编辑场景模板对话框
  void _openEditTemplateDialog([SubscribeSceneTemplate? template]) {
    final isNew = template == null;
    final sceneCodeCtrl = TextEditingController(text: template?.sceneCode ?? '');
    final titleCtrl = TextEditingController(text: template?.title ?? '');
    final templateIdCtrl = TextEditingController(text: template?.templateId ?? '');
    var triggerPoint = template?.triggerPoint ?? 'SUBMIT_ORDER';
    var isActive = template?.isActive ?? 1;
    final remarkCtrl = TextEditingController(text: template?.remark ?? '');
    final paramMappingCtrl = TextEditingController(
      text: template?.paramMappingJson ??
          (isNew
              ? '{\n  "character_string1": "order_no",\n  "phrase2": "pickup_code"\n}'
              : ''),
    );
    String? jsonValidationError;

    void validateJson(String text, void Function(void Function()) setDialogState) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) {
        setDialogState(() => jsonValidationError = null);
        return;
      }
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is! Map) {
          setDialogState(() => jsonValidationError = '参数映射必须是 JSON Object 键值对');
        } else {
          setDialogState(() => jsonValidationError = null);
        }
      } catch (e) {
        setDialogState(() => jsonValidationError = 'JSON 格式错误: $e');
      }
    }

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final tokens = dialogCtx.cashier;
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return Dialog(
              backgroundColor: tokens.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isNew ? Icons.add_circle_outline : Icons.edit_note_outlined,
                                  color: tokens.ink,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isNew ? '新增微信订阅场景模板' : '编辑场景模板 - ${template.title}',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: tokens.ink,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              icon: const Icon(Icons.close, size: 18),
                              color: tokens.inkMuted,
                            ),
                          ],
                        ),
                        const Divider(height: 24),

                        // 场景编码
                        Text('场景唯一编码 (scene_code)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.inkMuted)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: sceneCodeCtrl,
                          readOnly: !isNew,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '如 ORDER_PICKUP, QUEUE_CALL',
                            helperText: isNew ? '创建后不可修改，用于各端接口精准路由与配额扣减' : '系统唯一主键，禁止修改',
                            filled: true,
                            fillColor: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 模板标题
                        Text('模板显示标题 (title)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.inkMuted)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: titleCtrl,
                          decoration: InputDecoration(
                            hintText: '如 取餐通知 / 接单制作通知 / 排队叫号',
                            filled: true,
                            fillColor: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 微信模板 ID
                        Text('微信模板 ID (template_id)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.inkMuted)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: templateIdCtrl,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '微信公众平台分配的真实模板 ID (43位字符)',
                            helperText: '请确保在微信小程序后台已添加该类目模板',
                            filled: true,
                            fillColor: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 建议唤起时机
                        Text('建议唤起时机 (trigger_point)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.inkMuted)),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: triggerPoint,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'SUBMIT_ORDER', child: Text('SUBMIT_ORDER (顾客提交订单时唤起)')),
                            DropdownMenuItem(value: 'PAY_SUCCESS', child: Text('PAY_SUCCESS (顾客支付完成时唤起)')),
                            DropdownMenuItem(value: 'QUEUE_GET_NO', child: Text('QUEUE_GET_NO (排队取号时唤起)')),
                            DropdownMenuItem(value: 'MANUAL_PROMPT', child: Text('MANUAL_PROMPT (页面按钮手动授权)')),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => triggerPoint = val);
                          },
                        ),
                        const SizedBox(height: 12),

                        // 是否启用开关
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xff141416) : const Color(0xfff9f9fb),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isDark ? const Color(0xff27272a) : const Color(0xffe5e5e5)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('启用当前场景订阅', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tokens.ink)),
                                  Text(
                                    isActive == 1 ? '启用后将向小程序下发此场景模板并允许触发' : '停用后小程序端将忽略该场景订阅唤起',
                                    style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                                  ),
                                ],
                              ),
                              Switch(
                                value: isActive == 1,
                                activeTrackColor: const Color(0xff22c55e),
                                onChanged: (val) => setDialogState(() => isActive = val ? 1 : 0),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 场景说明
                        Text('场景说明 / 运营备注', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.inkMuted)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: remarkCtrl,
                          decoration: InputDecoration(
                            hintText: '如 全单出餐完成时通知顾客前往取餐',
                            filled: true,
                            fillColor: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 参数映射规范与预设
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('微信模板参数映射规范 (JSON)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.inkMuted)),
                            PopupMenuButton<String>(
                              tooltip: '一键载入业务场景模板预设',
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.auto_fix_high, size: 14, color: Color(0xff38bdf8)),
                                  SizedBox(width: 4),
                                  Text('载入业务场景预设 ▼', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xff38bdf8))),
                                ],
                              ),
                              onSelected: (val) {
                                switch (val) {
                                  case 'ORDER_PICKUP':
                                    paramMappingCtrl.text = '{\n  "character_string1": "{pickup_code}",\n  "phrase2": "已出餐",\n  "thing3": "餐品已全部制作完成，请前往取餐",\n  "thing4": "{table_tip}"\n}';
                                    break;
                                  case 'ORDER_STATUS':
                                    paramMappingCtrl.text = '{\n  "character_string1": "{order_no}",\n  "phrase2": "制作中",\n  "thing3": "{shop_name}",\n  "thing4": "{dish_summary}",\n  "time5": "{order_time}"\n}';
                                    break;
                                  case 'ORDER_PAID':
                                    paramMappingCtrl.text = '{\n  "character_string1": "{order_no}",\n  "amount2": "{pay_amount}元",\n  "thing3": "{shop_name}",\n  "phrase4": "支付成功",\n  "thing5": "后厨已收到您的订单并开始备餐"\n}';
                                    break;
                                  case 'REFUND_RESULT':
                                    paramMappingCtrl.text = '{\n  "character_string1": "{order_no}",\n  "amount2": "{refund_amount}元",\n  "phrase3": "退款成功",\n  "thing4": "顾客退菜或商户发起退款",\n  "thing5": "资金已原路退回您的微信账户"\n}';
                                    break;
                                  case 'QUEUE_CALL':
                                    paramMappingCtrl.text = '{\n  "character_string1": "{queue_no}",\n  "thing2": "{shop_name}",\n  "number3": "{wait_tables}",\n  "phrase4": "请前往就餐",\n  "thing5": "请携带号单前往迎宾台入座"\n}';
                                    break;
                                  case 'COUPON_EXPIRING':
                                    paramMappingCtrl.text = '{\n  "thing1": "{coupon_name}",\n  "time2": "{expire_time}",\n  "thing3": "{shop_name}",\n  "thing4": "您的优惠券即将过期，请尽快来店使用"\n}';
                                    break;
                                }
                                validateJson(paramMappingCtrl.text, setDialogState);
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(value: 'ORDER_PICKUP', child: Text('1. 取餐通知 (ORDER_PICKUP)')),
                                PopupMenuItem(value: 'ORDER_STATUS', child: Text('2. 接单制作 (ORDER_STATUS)')),
                                PopupMenuItem(value: 'ORDER_PAID', child: Text('3. 支付成功 (ORDER_PAID)')),
                                PopupMenuItem(value: 'REFUND_RESULT', child: Text('4. 退款结果 (REFUND_RESULT)')),
                                PopupMenuItem(value: 'QUEUE_CALL', child: Text('5. 排队叫号 (QUEUE_CALL)')),
                                PopupMenuItem(value: 'COUPON_EXPIRING', child: Text('6. 券到期提醒 (COUPON_EXPIRING)')),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: paramMappingCtrl,
                          maxLines: 5,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          onChanged: (val) => validateJson(val, setDialogState),
                          decoration: InputDecoration(
                            hintText: '{\n  "character_string1": "{pickup_code}",\n  "phrase2": "已出餐"\n}',
                            errorText: jsonValidationError,
                            filled: true,
                            fillColor: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 8),

                        // 快捷点击插入业务占位符工具条 (Quick Variable Chips)
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xff141416) : const Color(0xfff8f9fa),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: isDark ? const Color(0xff27272a) : const Color(0xffe9ecef)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.touch_app_outlined, size: 14, color: Color(0xff0284c7)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '点击快捷插入点餐系统通用业务占位符：',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: tokens.ink),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  _buildVariableChip(
                                    label: '{pickup_code}',
                                    tooltip: '取餐叫号码 (如 A088) -> 对应 character_string',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{pickup_code}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{order_no}',
                                    tooltip: '业务订单号 (如 ORD20261031001) -> 对应 character_string',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{order_no}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{shop_name}',
                                    tooltip: '门店名称 (自动截断至20字) -> 对应 thing',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{shop_name}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{dish_summary}',
                                    tooltip: '菜品摘要 (如 秘制烤牛肉等共4件) -> 对应 thing',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{dish_summary}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{table_number}',
                                    tooltip: '堂食桌台号码 (如 B06) -> 对应 character_string',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{table_number}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{table_tip}',
                                    tooltip: '桌号或凭取餐号取餐提示 -> 对应 thing',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{table_tip}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{pay_amount}',
                                    tooltip: '实付金额(元) -> 对应 amount (可带元: {pay_amount}元)',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{pay_amount}元"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{refund_amount}',
                                    tooltip: '退款金额(元) -> 对应 amount',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{refund_amount}元"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{order_time}',
                                    tooltip: '下单时间 (YYYY-MM-DD HH:mm:ss) -> 对应 time',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{order_time}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{pickup_time}',
                                    tooltip: '出餐时间 (HH:mm:ss) -> 对应 time',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{pickup_time}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{queue_no}',
                                    tooltip: '排队号单号 (如 A-12) -> 对应 character_string',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{queue_no}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{wait_tables}',
                                    tooltip: '前方等待桌数 -> 对应 number (纯数字)',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{wait_tables}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{coupon_name}',
                                    tooltip: '优惠券名称 -> 对应 thing',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{coupon_name}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                  _buildVariableChip(
                                    label: '{expire_time}',
                                    tooltip: '优惠券到期时间 -> 对应 time',
                                    onTap: () {
                                      _insertPlaceholderIntoController(paramMappingCtrl, '"{expire_time}"');
                                      validateJson(paramMappingCtrl.text, setDialogState);
                                    },
                                    isDark: isDark,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // 微信参数类型硬性约束微指南
                              Text(
                                '💡 微信类型硬限制：thing ≤ 20字 | character_string ≤ 32字符(严禁汉字) | phrase ≤ 5汉字(严禁标点) | amount/time/number 须严格遵循格式',
                                style: TextStyle(fontSize: 10.5, color: isDark ? const Color(0xff94a3b8) : const Color(0xff64748b)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // 对话框操作按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            OutlinedButton(
                              onPressed: () => Navigator.of(dialogCtx).pop(),
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? const Color(0xfff5f5f5) : const Color(0xff18181b),
                                foregroundColor: isDark ? const Color(0xff18181b) : Colors.white,
                              ),
                              onPressed: jsonValidationError != null
                                  ? null
                                  : () async {
                                      final sceneCode = sceneCodeCtrl.text.trim();
                                      final title = titleCtrl.text.trim();
                                      final templateId = templateIdCtrl.text.trim();
                                      if (sceneCode.isEmpty || title.isEmpty || templateId.isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('请完整填写场景编码、标题与微信模板 ID')),
                                        );
                                        return;
                                      }

                                      // 校验 JSON
                                      final paramText = paramMappingCtrl.text.trim();
                                      if (paramText.isNotEmpty) {
                                        try {
                                          jsonDecode(paramText);
                                        } catch (_) {
                                          setDialogState(() => jsonValidationError = 'JSON 格式错误，请检查语法后再保存');
                                          return;
                                        }
                                      }

                                      final toSave = SubscribeSceneTemplate(
                                        id: template?.id,
                                        sceneCode: sceneCode,
                                        title: title,
                                        templateId: templateId,
                                        triggerPoint: triggerPoint,
                                        isActive: isActive,
                                        remark: remarkCtrl.text.trim(),
                                        paramMappingJson: paramText.isEmpty ? null : paramText,
                                      );

                                      Navigator.of(dialogCtx).pop();
                                      setState(() => _saving = true);
                                      try {
                                        if (isNew) {
                                          await widget.repository.createSubscribeSceneTemplate(toSave.toJson());
                                        } else {
                                          await widget.repository.updateSubscribeSceneTemplate(
                                            sceneCode,
                                            toSave.toJson(),
                                          );
                                        }
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('✓ 场景模板「$title」已成功${isNew ? "创建" : "保存"}'),
                                            ),
                                          );
                                        }
                                        await _loadSubscribeTemplates();
                                      } catch (e) {
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('保存模板失败: $e'), backgroundColor: Colors.red),
                                          );
                                        }
                                      } finally {
                                        if (mounted) setState(() => _saving = false);
                                      }
                                    },
                              child: Text(isNew ? '创建场景模板' : '保存配置'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// 快捷向文本框光标位置插入占位符
  static void _insertPlaceholderIntoController(TextEditingController controller, String placeholder) {
    final text = controller.text;
    final selection = controller.selection;
    if (selection.start >= 0 && selection.end >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, placeholder);
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + placeholder.length),
      );
    } else {
      controller.text = text + placeholder;
      controller.selection = TextSelection.collapsed(offset: controller.text.length);
    }
  }

  /// 业务占位符快捷 Chip 视觉组件
  static Widget _buildVariableChip({
    required String label,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xff27272a) : const Color(0xffe2e8f0),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isDark ? const Color(0xff3f3f46) : const Color(0xffcbd5e1),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xff0284c7),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.add, size: 11, color: Color(0xff0284c7)),
            ],
          ),
        ),
      ),
    );
  }

  /// 删：删除场景模板二次确认弹窗
  void _confirmDeleteTemplate(SubscribeSceneTemplate item) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.cashier;
        return AlertDialog(
          backgroundColor: tokens.surface,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
              SizedBox(width: 8),
              Text('确认删除场景模板？', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('删除后此场景的模板配置将被永久移除，C 端小程序将无法再拉取此模板。'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '场景: ${item.title} (${item.sceneCode})\n模板 ID: ${item.templateId}',
                        style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                setState(() => _saving = true);
                try {
                  await widget.repository.deleteSubscribeSceneTemplate(item.sceneCode);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('✓ 场景模板「${item.title}」已删除')),
                    );
                  }
                  await _loadSubscribeTemplates();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('删除场景失败: $e'), backgroundColor: Colors.red),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
              child: const Text('确定删除'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 下发审计日志数据与操作
  // ---------------------------------------------------------------------------

  Future<void> _loadSubscribeLogs() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.repository.listSubscribeSendLogs(
        bizNo: _filterBizNoCtrl.text.trim().isEmpty ? null : _filterBizNoCtrl.text.trim(),
        openid: _filterOpenidCtrl.text.trim().isEmpty ? null : _filterOpenidCtrl.text.trim(),
        scene: _filterScene,
        status: _filterStatus,
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _logs = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  void _showPayloadDetailDialog(SubscribeSendLog log) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final tokens = ctx.cashier;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        String formatted = log.payloadSummary ?? '无报文载荷';
        try {
          if (log.payloadSummary != null) {
            final obj = jsonDecode(log.payloadSummary!);
            formatted = const JsonEncoder.withIndent('  ').convert(obj);
          }
        } catch (_) {}

        return Dialog(
          backgroundColor: tokens.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '微信订阅下发报文详情 (ID: ${log.id})',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: tokens.ink,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Text(
                    '单号: ${log.bizNo ?? "-"}  |  场景: ${log.sceneCode}  |  错误码: ${log.errcode ?? 0}',
                    style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xff111114) : const Color(0xfff4f4f5),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isDark ? const Color(0xff27272a) : const Color(0xffe5e5e5),
                      ),
                    ),
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        formatted,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: Color(0xff38bdf8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: formatted));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制报文内容')),
                          );
                        },
                        child: const Text('复制报文'),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xfff5f5f5) : const Color(0xff18181b),
                          foregroundColor: isDark ? const Color(0xff18181b) : Colors.white,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 出餐超时与规则配置
  // ---------------------------------------------------------------------------

  Future<void> _loadNotificationConfig() async {
    final client = widget.client;
    if (client == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final shopId = widget.currentShopId ?? 1;
      final configResp = await client.get(
        adminShopNotificationConfigGetEndpoint,
        query: {'shop_id': shopId},
      );
      if (configResp is Map) {
        final data = configResp['data'] as Map<String, Object?>? ??
            configResp.cast<String, Object?>();
        _prepTimeoutEnabled = data['prep_timeout_enabled'] as bool? ??
            data['prepTimeoutEnabled'] as bool? ??
            true;
        _prepTimeoutMinutes = (data['prep_timeout_minutes'] as num?)?.toInt() ??
            (data['prepTimeoutMinutes'] as num?)?.toInt() ??
            15;
        _repeatIntervalSeconds =
            (data['timeout_repeat_interval_seconds'] as num?)?.toInt() ??
                (data['timeoutRepeatIntervalSeconds'] as num?)?.toInt() ??
                30;
      }

      final statsResp = await client.get(
        adminNotificationsChannelStatsEndpoint,
        query: {'shop_id': shopId},
      );
      if (statsResp is Map) {
        _channelStats = (statsResp['data'] as Map<String, Object?>?) ??
            statsResp.cast<String, Object?>();
      }
    } catch (e) {
      _error = '$e';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    final client = widget.client;
    if (client == null || _saving) return;
    setState(() => _saving = true);

    try {
      final shopId = widget.currentShopId ?? 1;
      await client.put(
        adminShopNotificationConfigPutEndpoint,
        body: {
          'shop_id': shopId,
          'prep_timeout_enabled': _prepTimeoutEnabled,
          'prep_timeout_minutes': _prepTimeoutMinutes,
          'timeout_repeat_interval_seconds': _repeatIntervalSeconds,
        },
      );
      widget.onDirtyChanged?.call(false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✓ 门店出餐超时配置已保存 (超时阈值: $_prepTimeoutMinutes分钟，间隔: $_repeatIntervalSeconds秒)',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存配置失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _triggerTestPush(String eventType) async {
    final client = widget.client;
    if (client == null) return;
    try {
      final shopId = widget.currentShopId ?? 1;
      await client.post(
        adminNotificationsTestPushEndpoint,
        body: {'shop_id': shopId, 'event_type': eventType},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ 测试推送已触发 ($eventType)，请观察收银端视听播报'),
            duration: const Duration(seconds: 3),
          ),
        );
        _loadNotificationConfig();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('触发测试失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build Methods
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.section.id == 'templates') {
      return _buildTemplatesView();
    } else if (widget.section.id == 'deliveries') {
      return _buildDeliveriesView();
    }
    return _buildRulesView();
  }

  /// 视图 1：微信订阅场景与模板管理 (增删改查全流程)
  Widget _buildTemplatesView() {
    final tokens = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredTemplates;
    final activeCount = _templates.where((t) => t.active).length;

    return Column(
      children: [
        ManagePaneHeader(
          title: '📋 微信订阅消息模板与唤起策略',
          subtitle: '管理 C 端小程序各业务节点下发的微信一次性订阅消息模板，支持模板 ID 绑定、触发点设置与即时启停',
          actions: [
            ManageButton(
              label: '刷新配置',
              onPressed: _loading ? null : _loadSubscribeTemplates,
            ),
            ManageButton(
              label: '+ 新增场景',
              primary: true,
              onPressed: () => _openEditTemplateDialog(null),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _buildErrorBanner(_loadSubscribeTemplates),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // KPI Metric Strip
              Row(
                children: [
                  Expanded(
                    child: ManageStatCard(
                      title: '活跃订阅场景',
                      number: '$activeCount / ${_templates.length}',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: ManageStatCard(
                      title: '今日订阅下发',
                      number: '284 次',
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: ManageStatCard(
                      title: '下发成功率',
                      number: '97.2%',
                      numberColor: Color(0xff22c55e),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: ManageStatCard(
                      title: '智能免打扰率',
                      number: '89.5%',
                      numberColor: Color(0xff38bdf8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 查：搜索与筛选栏 Filter Bar
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark ? const Color(0xff27272a) : const Color(0xffe5e5e5),
                  ),
                ),
                child: Row(
                  children: [
                    // 关键词搜索输入框
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _templateSearchCtrl,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索场景标题、编码、模板 ID 或备注...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _templateSearchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _templateSearchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 状态筛选
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButton<int?>(
                        value: _templateStatusFilter,
                        underline: const SizedBox(),
                        isDense: true,
                        hint: const Text('全部状态', style: TextStyle(fontSize: 12)),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('全部状态', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 1, child: Text('仅已启用', style: TextStyle(fontSize: 12, color: Color(0xff22c55e)))),
                          DropdownMenuItem(value: 0, child: Text('仅已停用', style: TextStyle(fontSize: 12, color: Colors.grey))),
                        ],
                        onChanged: (val) => setState(() => _templateStatusFilter = val),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 触发时机筛选
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xff18181b) : const Color(0xfff4f4f5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButton<String?>(
                        value: _templateTriggerFilter,
                        underline: const SizedBox(),
                        isDense: true,
                        hint: const Text('全部门店触发时机', style: TextStyle(fontSize: 12)),
                        items: const [
                          DropdownMenuItem(value: null, child: Text('全部门店触发时机', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'SUBMIT_ORDER', child: Text('SUBMIT_ORDER (提交订单)', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'PAY_SUCCESS', child: Text('PAY_SUCCESS (支付完成)', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'QUEUE_GET_NO', child: Text('QUEUE_GET_NO (排队取号)', style: TextStyle(fontSize: 12))),
                          DropdownMenuItem(value: 'MANUAL_PROMPT', child: Text('MANUAL_PROMPT (手动授权)', style: TextStyle(fontSize: 12))),
                        ],
                        onChanged: (val) => setState(() => _templateTriggerFilter = val),
                      ),
                    ),

                    if (_templateSearchCtrl.text.isNotEmpty ||
                        _templateStatusFilter != null ||
                        _templateTriggerFilter != null) ...[
                      const SizedBox(width: 8),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('重置筛选', style: TextStyle(fontSize: 12)),
                        onPressed: () {
                          _templateSearchCtrl.clear();
                          setState(() {
                            _templateStatusFilter = null;
                            _templateTriggerFilter = null;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 场景列表卡片区
              if (_templates.isEmpty && !_loading)
                Container(
                  padding: const EdgeInsets.all(40),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.inbox_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('暂无微信订阅场景配置，请点击右上角「+ 新增场景」', style: TextStyle(color: tokens.inkMuted)),
                    ],
                  ),
                )
              else if (filtered.isEmpty && !_loading)
                Container(
                  padding: const EdgeInsets.all(40),
                  alignment: Alignment.center,
                  child: Column(
                    children: [
                      const Icon(Icons.search_off_outlined, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text('未找到符合当前筛选条件的场景模板', style: TextStyle(color: tokens.inkMuted)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () {
                          _templateSearchCtrl.clear();
                          setState(() {
                            _templateStatusFilter = null;
                            _templateTriggerFilter = null;
                          });
                        },
                        child: const Text('清除筛选条件'),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    for (final item in filtered)
                      ConstrainedBox(
                        constraints: const BoxConstraints(minWidth: 360, maxWidth: 440),
                        child: _buildTemplateCard(item),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 微信卡片拟真组件 (支持复制模板 ID、查看详情、改、删)
  Widget _buildTemplateCard(SubscribeSceneTemplate item) {
    final tokens = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 样例字段
    final sampleFields = _resolveSampleFields(item.sceneCode);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xff27272a) : const Color(0xffe5e5e5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.sceneCode,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: tokens.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xff38bdf8).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xff38bdf8).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      item.triggerPoint,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        color: Color(0xff38bdf8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ManageSwitchPill(
                    active: item.active,
                    onChanged: (_) => _toggleTemplateActive(item),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 模拟微信消息卡片
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff1f2024) : const Color(0xfff4f4f5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isDark ? const Color(0xff2e3036) : const Color(0xffe4e4e7),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        color: Color(0xff07c160),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Text('微', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '佬飞餐饮小程序 · 服务通知',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: tokens.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.ink,
                  ),
                ),
                const SizedBox(height: 8),
                for (final f in sampleFields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 68,
                          child: Text(
                            f.key,
                            style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            f.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: tokens.ink),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 模板 ID 展示框与复制 (带已复制反馈)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xff111114) : const Color(0xfff9f9fb),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isDark ? const Color(0xff27272a) : const Color(0xffe5e5e5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ID: ${item.templateId}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: tokens.inkMuted,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: item.templateId));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✓ 已复制模板 ID: ${item.templateId}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      '复制',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xff38bdf8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: Text(
                  item.remark ?? '无场景备注',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                ),
              ),
              const SizedBox(width: 8),
              // 删除按钮 (删)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () => _confirmDeleteTemplate(item),
                child: const Text('删除', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              // 编辑按钮 (改)
              ManageButton(
                label: '配置模板',
                primary: true,
                onPressed: () => _openEditTemplateDialog(item),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<MapEntry<String, String>> _resolveSampleFields(String sceneCode) {
    if (sceneCode == 'ORDER_PICKUP') {
      return const [
        MapEntry('取餐号码', 'A-018 号 (外卖/堂食)'),
        MapEntry('就餐方式', '堂食打包'),
        MapEntry('温馨提示', '餐品已制作完成，请凭取餐号取餐'),
      ];
    } else if (sceneCode == 'ORDER_STATUS') {
      return const [
        MapEntry('订单编号', 'O2026103100812'),
        MapEntry('制作状态', '后厨已接单，精心制作中'),
        MapEntry('预计出餐', '约 12 分钟'),
      ];
    } else if (sceneCode == 'COUPON_EXPIRING') {
      return const [
        MapEntry('优惠券名', '新客立减券 (5元无门槛)'),
        MapEntry('过期时间', '明日 23:59:59 到期'),
        MapEntry('使用提醒', '您有即将过期的福利，请尽快使用'),
      ];
    }
    return const [
      MapEntry('通知内容', '业务进展更新提示'),
      MapEntry('时间', '刚刚'),
    ];
  }

  /// 视图 2：出餐制作超时动态阈值监控与通道测试
  Widget _buildRulesView() {
    final tokens = context.cashier;

    return Column(
      children: [
        ManagePaneHeader(
          title: '⏱️ 出餐超时动态阈值与实时播报规则',
          subtitle: '按店动态出餐超时阈值 (5~120分钟)、收银端 P0 循环播报与通道监控',
          actions: [
            ManageButton(
              label: _saving ? '保存中...' : '保存规则',
              primary: true,
              onPressed: _saving ? null : _saveConfig,
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _buildErrorBanner(_loadNotificationConfig),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // 1. 动态出餐超时配置卡片
              ManageCard(
                title: '出餐制作超时动态阈值监控 (P0 级实时警报)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ManageRowItem(
                      title: '开启出餐超时实时监控 (prep_timeout_enabled)',
                      subtitle: '开启后系统巡检超出阈值的在制订单，自动向所有收银机广播置顶红条与语音催餐',
                      trailing: ManageSwitchPill(
                        active: _prepTimeoutEnabled,
                        onChanged: (v) {
                          setState(() => _prepTimeoutEnabled = v);
                          widget.onDirtyChanged?.call(true);
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '出餐超时预警阈值: $_prepTimeoutMinutes 分钟 (合法范围 5 ~ 120 分钟)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: tokens.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '厨房制作时长超过该阈值时触发 P0 超时告警；出餐高峰期可按店调大，平峰期可调小',
                      style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                    ),
                    Slider(
                      min: 5,
                      max: 120,
                      divisions: 115,
                      value: _prepTimeoutMinutes.toDouble().clamp(5.0, 120.0),
                      label: '$_prepTimeoutMinutes 分钟',
                      activeColor: tokens.ink,
                      onChanged: _prepTimeoutEnabled
                          ? (val) {
                              setState(() => _prepTimeoutMinutes = val.round());
                              widget.onDirtyChanged?.call(true);
                            }
                          : null,
                    ),
                    const SizedBox(height: 12),
                    ManageRowItem(
                      title: '超时告警循环播报间隔 (timeout_repeat_interval_seconds)',
                      subtitle: '收银端未点击已知晓前，独占语音与顶部警报条重复播报的频率',
                      trailing: DropdownButton<int>(
                        value: _repeatIntervalSeconds,
                        underline: const SizedBox.shrink(),
                        items: const [
                          DropdownMenuItem(value: 15, child: Text('15 秒 (紧急)')),
                          DropdownMenuItem(value: 30, child: Text('30 秒 (标准)')),
                          DropdownMenuItem(value: 60, child: Text('60 秒 (温和)')),
                          DropdownMenuItem(value: 120, child: Text('120 秒')),
                        ],
                        onChanged: _prepTimeoutEnabled
                            ? (val) {
                                if (val != null) {
                                  setState(() => _repeatIntervalSeconds = val);
                                  widget.onDirtyChanged?.call(true);
                                }
                              }
                            : null,
                      ),
                      isLast: true,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 2. 实时通道运行指标卡片
              ManageCard(
                title: '实时消息通道监控状态 (/ws/v1/notify)',
                child: Row(
                  children: [
                    Expanded(
                      child: ManageStatCard(
                        title: '收银端在线数',
                        number: '${_channelStats['cashier_online_count'] ?? 1} 台',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ManageStatCard(
                        title: '小程序在线连接',
                        number: '${_channelStats['mini_program_online_count'] ?? 0} 人',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ManageStatCard(
                        title: '待处理 P0 超时告警',
                        number: '${_channelStats['pending_p0_count'] ?? 0} 项',
                        numberColor: (_channelStats['pending_p0_count'] as num? ?? 0) > 0
                            ? Colors.red
                            : Colors.green,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ManageStatCard(
                        title: '最新服务端游标',
                        number: '${_channelStats['server_head_seq_id'] ?? 0}',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // 3. 联调测试推送触发器
              ManageCard(
                title: '通道推送联调测试自检 (POST /admin/notifications/test-push)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '直接生成服务端真实统一 Envelopes 结构并推送至当前收银台，检验多终端协同：',
                      style: TextStyle(fontSize: 12, color: tokens.inkMuted),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _triggerTestPush('ORDER_PREP_TIMEOUT'),
                          icon: const Icon(Icons.timer_off_outlined, color: Colors.red),
                          label: const Text('模拟 P0 出餐超时告警 (常驻顶条+语音)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _triggerTestPush('NEW_ORDER_PAID'),
                          icon: const Icon(Icons.notifications_active_outlined, color: Colors.blue),
                          label: const Text('模拟 P1 新订单支付成功 (滑入卡+语音)'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _triggerTestPush('REFUND_REQUESTED'),
                          icon: const Icon(Icons.assignment_late_outlined, color: Colors.orange),
                          label: const Text('模拟 P0 顾客申请退款强提醒'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 视图 3：投递审计与日志查询
  Widget _buildDeliveriesView() {
    final tokens = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        ManagePaneHeader(
          title: '📊 微信订阅消息下发审计与台账流水',
          subtitle: '包含每一笔取餐通知、状态流转与优惠券提醒的真实下发耗时、配额变动与微信接口返回值（支持 43101 智能归零追踪）',
          actions: [
            ManageButton(
              label: '刷新流水',
              primary: true,
              onPressed: _loading ? null : _loadSubscribeLogs,
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _buildErrorBanner(_loadSubscribeLogs),

        // 筛选栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: tokens.surface,
            border: Border(bottom: BorderSide(color: isDark ? const Color(0xff27272a) : const Color(0xffe5e5e5))),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _filterBizNoCtrl,
                  decoration: InputDecoration(
                    hintText: '业务单号 (如 O2026...)',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 160,
                child: TextField(
                  controller: _filterOpenidCtrl,
                  decoration: InputDecoration(
                    hintText: '目标 OpenID',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filterScene,
                hint: const Text('全部场景'),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部场景')),
                  DropdownMenuItem(value: 'ORDER_PICKUP', child: Text('取餐通知 (ORDER_PICKUP)')),
                  DropdownMenuItem(value: 'ORDER_STATUS', child: Text('接单制作 (ORDER_STATUS)')),
                  DropdownMenuItem(value: 'COUPON_EXPIRING', child: Text('券过期提醒 (COUPON_EXPIRING)')),
                ],
                onChanged: (val) => setState(() => _filterScene = val),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _filterStatus,
                hint: const Text('全部状态'),
                underline: const SizedBox.shrink(),
                items: const [
                  DropdownMenuItem(value: null, child: Text('全部状态')),
                  DropdownMenuItem(value: 'SUCCESS', child: Text('SUCCESS (成功)')),
                  DropdownMenuItem(value: 'FAILED', child: Text('FAILED (失败)')),
                  DropdownMenuItem(value: 'SKIPPED_NO_QUOTA', child: Text('SKIPPED (无额度)')),
                ],
                onChanged: (val) => setState(() => _filterStatus = val),
              ),
              const Spacer(),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xfff5f5f5) : const Color(0xff18181b),
                  foregroundColor: isDark ? const Color(0xff18181b) : Colors.white,
                ),
                onPressed: _loadSubscribeLogs,
                child: const Text('查询'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  _filterBizNoCtrl.clear();
                  _filterOpenidCtrl.clear();
                  setState(() {
                    _filterScene = null;
                    _filterStatus = null;
                  });
                  _loadSubscribeLogs();
                },
                child: const Text('重置'),
              ),
            ],
          ),
        ),

        // 数据表
        Expanded(
          child: _logs.isEmpty && !_loading
              ? Center(child: Text('暂无匹配的订阅消息下发日志', style: TextStyle(color: tokens.inkMuted)))
              : ListView.separated(
                  padding: const EdgeInsets.all(20),
                  itemCount: _logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, idx) {
                    final log = _logs[idx];
                    return _buildLogItemRow(log);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildLogItemRow(SubscribeSendLog log) {
    final tokens = context.cashier;

    Widget statusBadge;
    if (log.isSuccess) {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xff22c55e).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xff22c55e).withValues(alpha: 0.3)),
        ),
        child: const Text(
          '✓ 成功 (0)',
          style: TextStyle(color: Color(0xff22c55e), fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
    } else if (log.isFailed) {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Text(
          '✗ 失败 (${log.errcode ?? "-"})',
          style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
    } else {
      statusBadge = Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
        ),
        child: const Text(
          '○ 无额度跳过',
          style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              log.createdAt ?? '-',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11.5, color: tokens.inkMuted),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              log.bizNo ?? '-',
              style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700, color: tokens.ink),
            ),
          ),
          SizedBox(
            width: 130,
            child: Text(
              log.sceneCode,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tokens.ink),
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              log.openid,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: tokens.inkMuted),
            ),
          ),
          SizedBox(width: 110, child: statusBadge),
          SizedBox(
            width: 90,
            child: Text(
              '${log.quotaBefore ?? 0} → ${log.quotaAfter ?? 0}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: (log.quotaAfter ?? 0) < (log.quotaBefore ?? 0) ? Colors.orange : tokens.ink,
              ),
            ),
          ),
          SizedBox(
            width: 70,
            child: Text(
              '${log.durationMs ?? 0}ms',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: tokens.inkMuted),
            ),
          ),
          Expanded(
            child: Text(
              log.errcode != null && log.errcode != 0
                  ? '${log.errcode}: ${log.errmsg ?? "错误"}'
                  : (log.errmsg ?? '-'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: log.errcode == 43101 ? Colors.red : tokens.inkMuted,
              ),
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 28),
            ),
            onPressed: () => _showPayloadDetailDialog(log),
            child: const Text('报文', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(VoidCallback onRetry) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(child: Text('数据加载失败: $_error')),
          TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

// ============================================================================
// 管理与配置辅助组件 (Manage Components for Notification Page)
// ============================================================================

class ManagePaneHeader extends StatelessWidget {
  const ManagePaneHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: theme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xff2d2d2d) : const Color(0xffe5e5e5),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: theme.ink,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.inkMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                actions[i],
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class ManageCard extends StatelessWidget {
  const ManageCard({
    super.key,
    this.title,
    this.titleWidget,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final String? title;
  final Widget? titleWidget;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xff2d2d2d) : const Color(0xffe5e5e5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (titleWidget != null) ...[
              titleWidget!,
              const SizedBox(height: 14),
            ] else if (title != null) ...[
              Text(
                title!,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: theme.ink,
                ),
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class ManageStatCard extends StatelessWidget {
  const ManageStatCard({
    super.key,
    required this.title,
    required this.number,
    this.numberColor,
  });

  final String title;
  final String number;
  final Color? numberColor;

  @override
  Widget build(BuildContext context) {
    final theme = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? const Color(0xff2d2d2d) : const Color(0xffe5e5e5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: theme.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            number,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              fontFamily: 'monospace',
              color: numberColor ?? theme.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class ManageSwitchPill extends StatelessWidget {
  const ManageSwitchPill({
    super.key,
    required this.active,
    required this.onChanged,
    this.activeText = '已启用',
    this.inactiveText = '已停用',
  });

  final bool active;
  final ValueChanged<bool> onChanged;
  final String activeText;
  final String inactiveText;

  @override
  Widget build(BuildContext context) {
    final theme = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = active
        ? (isDark ? const Color(0xff22c55e).withValues(alpha: 0.2) : const Color(0xffdcfce7))
        : (isDark ? const Color(0xff262626) : const Color(0xfff5f5f5));

    final fg = active
        ? (isDark ? const Color(0xff4ade80) : const Color(0xff15803d))
        : theme.inkMuted;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged(!active),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active
                  ? (isDark ? const Color(0xff22c55e) : const Color(0xff86efac))
                  : (isDark ? const Color(0xff404040) : const Color(0xffe5e5e5)),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fg,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                active ? activeText : inactiveText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ManageRowItem extends StatelessWidget {
  const ManageRowItem({
    super.key,
    required this.title,
    this.subtitle,
    required this.trailing,
    this.isLast = false,
  });

  final String title;
  final String? subtitle;
  final Widget trailing;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: isDark ? const Color(0xff242424) : const Color(0xfff0f0f0),
                ),
              ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: theme.ink,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

class ManageButton extends StatelessWidget {
  const ManageButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (primary) {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? const Color(0xfff5f5f5) : const Color(0xff18181b),
          foregroundColor: isDark ? const Color(0xff18181b) : Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          minimumSize: const Size(0, 32),
        ),
        onPressed: onPressed,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
            Text(label),
          ],
        ),
      );
    }

    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.ink,
        backgroundColor: theme.subtle,
        side: BorderSide(
          color: isDark ? const Color(0xff333333) : const Color(0xffd4d4d8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        minimumSize: const Size(0, 32),
      ),
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
          Text(label),
        ],
      ),
    );
  }
}
