import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/cashier_settings_repository.dart';
import '../domain/cashier_settings.dart';
import 'cashier_settings_shared.dart';

/// 设置页「外卖管理」：外卖平台 / 配送规则 / 真省钱配送 / 配送记录。
class CashierSettingsDeliveryPage extends StatefulWidget {
  const CashierSettingsDeliveryPage({
    super.key,
    required this.repository,
    required this.section,
    this.onDirtyChanged,
  });

  final CashierSettingsRepository repository;
  final SettingsSectionSpec section;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<CashierSettingsDeliveryPage> createState() =>
      _CashierSettingsDeliveryPageState();
}

class _CashierSettingsDeliveryPageState
    extends State<CashierSettingsDeliveryPage> {
  @override
  Widget build(BuildContext context) {
    switch (widget.section.id) {
      case 'platforms':
        return _PlatformsSection(repository: widget.repository);
      case 'rules':
        return _RulesSection(
          repository: widget.repository,
          onDirtyChanged: widget.onDirtyChanged,
        );
      case 'zsq':
        return _ZsqSection(
          repository: widget.repository,
          onDirtyChanged: widget.onDirtyChanged,
        );
      case 'records':
        return _RecordsSection(repository: widget.repository);
      default:
        return CashierSettingsDeliveryScaffold(
          section: widget.section,
          child: SettingsErrorState(
            message: '不支持的外卖管理页面：${widget.section.id}',
            onRetry: null,
          ),
        );
    }
  }
}

class CashierSettingsDeliveryScaffold extends StatelessWidget {
  const CashierSettingsDeliveryScaffold({
    super.key,
    required this.section,
    required this.child,
  });

  final SettingsSectionSpec section;
  final Widget child;

  static String _sectionSubtitle(String id) {
    switch (id) {
      case 'platforms':
      case 'delivery:platforms':
        return '平台接入 · 外卖开通';
      case 'rules':
      case 'delivery:rules':
        return '起送价、配送费与距离阶梯';
      case 'zsq':
      case 'delivery:zsq':
        return '聚合配送开关与配送操作';
      case 'records':
      case 'delivery:records':
        return '配送批次、骑手与状态';
      default:
        return '外卖管理';
    }
  }

  @override
  Widget build(BuildContext context) => SettingsPagePadding(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          section.label,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: context.cashier.ink,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _sectionSubtitle(section.id),
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
        const SizedBox(height: 18),
        Expanded(child: child),
      ],
    ),
  );
}

// ============ 外卖平台 ============

class _PlatformsSection extends StatefulWidget {
  const _PlatformsSection({required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_PlatformsSection> createState() => _PlatformsSectionState();
}

class _PlatformsSectionState extends State<_PlatformsSection> {
  _PlatformsData? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final results = await Future.wait([
        widget.repository.loadTakeoutConfig(),
        widget.repository.loadZsqAutoApi(),
      ]);
      if (!mounted) return;
      setState(() {
        _data = _PlatformsData(
          config: results[0] as ShopTakeoutConfig,
          zsq: results[1] as ZsqAutoApiConfig,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _retry() => _load();

  Future<void> _toggleEnabled(bool value) async {
    final data = _data;
    if (data == null) return;
    try {
      final saved = await widget.repository.saveTakeoutConfig(
        data.config.copyWith(enabled: value ? 1 : 0),
      );
      if (!mounted) return;
      setState(() {
        _data = _PlatformsData(config: saved, zsq: data.zsq);
      });
      showSettingsSaved(context, value ? '已开启门店外卖' : '已关闭门店外卖');
    } catch (e) {
      if (!mounted) return;
      showSettingsSaved(context, '保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const SettingsSkeletonLoader();
    } else if (_error != null) {
      body = SettingsErrorState(
        message: '外卖配置加载失败：$_error',
        onRetry: _retry,
      );
    } else {
      final data = _data!;
      final enabled = data.config.enabled == 1;
      body = ListView(
        padding: EdgeInsets.zero,
        children: [
          _DeliveryHeroCard(
            icon: Icons.storefront_outlined,
            title: '门店外卖开通',
            description: '控制本店是否接受外卖订单。关闭后小程序外卖配置返回 enabled=0，'
                '用户无法提交外卖单；已接单配送不受影响。',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  key: const Key('delivery-platforms-enabled'),
                  value: enabled,
                  activeTrackColor: context.cashier.selected,
                  onChanged: _toggleEnabled,
                ),
                const SizedBox(width: 10),
                SettingsStatusBadge(
                  type: enabled
                      ? StatusBadgeType.success
                      : StatusBadgeType.neutral,
                  label: enabled ? '已开启' : '已关闭',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _PlatformsOverviewCard(
            config: data.config,
            zsq: data.zsq,
          ),
          const SizedBox(height: 16),
          SettingsPanel(
            title: '数据说明',
            child: Text(
              '页面数据来自店铺外卖配置与聚合配送配置，'
              '开关保存即时生效。',
              style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
            ),
          ),
        ],
      );
    }
    return CashierSettingsDeliveryScaffold(
      section: const SettingsSectionSpec(
        'delivery:platforms',
        '外卖平台',
        Icons.storefront_outlined,
      ),
      child: body,
    );
  }
}

class _PlatformsData {
  const _PlatformsData({required this.config, required this.zsq});

  final ShopTakeoutConfig config;
  final ZsqAutoApiConfig zsq;
}

class _DeliveryHeroCard extends StatelessWidget {
  const _DeliveryHeroCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: context.cashier.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cashier.border),
    ),
    child: Row(
      children: [
        Icon(icon, size: 34, color: context.cashier.selected),
        const SizedBox(width: 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: context.cashier.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.6,
                  color: context.cashier.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        trailing,
      ],
    ),
  );
}

class _PlatformsOverviewCard extends StatelessWidget {
  const _PlatformsOverviewCard({required this.config, required this.zsq});

  final ShopTakeoutConfig config;
  final ZsqAutoApiConfig zsq;

  @override
  Widget build(BuildContext context) => SettingsPanel(
    title: '平台通道',
    child: Column(
      children: [
        _KvRow(
          label: '下单渠道',
          child: const Text('自营小程序外卖'),
        ),
        _KvRow(
          label: '外卖状态',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsStatusBadge(
                type: StatusBadgeType.info,
                label: config.enabled == 1 ? '营业中' : '已关闭',
              ),
              const SizedBox(width: 10),
              Text(
                'enabled=${config.enabled}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.cashier.inkMuted,
                ),
              ),
            ],
          ),
        ),
        _KvRow(
          label: '真省钱聚合配送',
          child: SettingsStatusBadge(
            type: zsq.autoDispatchEnabled
                ? StatusBadgeType.success
                : StatusBadgeType.neutral,
            label: zsq.autoDispatchEnabled ? '自动发单已开启' : '自动发单未开启',
          ),
        ),
        _KvRow(
          label: '外卖状态定时同步',
          child: SettingsStatusBadge(
            type: zsq.takeoutSyncEnabled
                ? StatusBadgeType.success
                : StatusBadgeType.neutral,
            label: zsq.takeoutSyncEnabled ? '定时同步已开启' : '定时同步未开启',
          ),
        ),
      ],
    ),
  );
}

class _KvRow extends StatelessWidget {
  const _KvRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
    decoration: BoxDecoration(
      border: Border(
        top: BorderSide(color: context.cashier.row, width: 1),
      ),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 190,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: context.cashier.inkSecondary),
          ),
        ),
        Expanded(child: child),
      ],
    ),
  );
}

// ============ 配送规则 ============

class _RulesSection extends StatefulWidget {
  const _RulesSection({required this.repository, this.onDirtyChanged});

  final CashierSettingsRepository repository;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<_RulesSection> createState() => _RulesSectionState();
}

class _RulesSectionState extends State<_RulesSection> {
  late Future<ShopTakeoutConfig> _future;
  late TextEditingController _minOrder;
  late TextEditingController _leadTime;
  late TextEditingController _deliveryFee;
  late TextEditingController _maxDistance;
  late TextEditingController _freeThreshold;
  late TextEditingController _freeMaxDistance;
  late TextEditingController _remark;
  List<DeliveryFeeTier> _tiers = const [];
  bool _saving = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ShopTakeoutConfig> _load() async {
    final config = await widget.repository.loadTakeoutConfig();
    _bind(config);
    return config;
  }

  void _bind(ShopTakeoutConfig config) {
    _minOrder = TextEditingController(
      text: _fmt(config.minOrderAmount, '68'),
    );
    _leadTime = TextEditingController(
      text: config.leadTimeMinutes?.toString() ?? '30',
    );
    _deliveryFee = TextEditingController(text: _fmt(config.deliveryFee, '0'));
    _maxDistance = TextEditingController(
      text: _fmt(config.maxDeliveryDistanceKm, '5'),
    );
    _freeThreshold = TextEditingController(
      text: _fmt(config.freeDeliveryThreshold, '168'),
    );
    _freeMaxDistance = TextEditingController(
      text: _fmt(config.freeDeliveryMaxDistanceKm, '5'),
    );
    _remark = TextEditingController(text: config.remark);
    _tiers = config.tiers.isEmpty ? _defaultTiers() : config.tiers;
  }

  static List<DeliveryFeeTier> _defaultTiers() => const [
    DeliveryFeeTier(toKm: 3, fee: 5),
    DeliveryFeeTier(toKm: 4, fee: 8),
    DeliveryFeeTier(toKm: 5, fee: 10),
  ];

  static String _fmt(double? value, String fallback) {
    if (value == null) return fallback;
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _minOrder.dispose();
    _leadTime.dispose();
    _deliveryFee.dispose();
    _maxDistance.dispose();
    _freeThreshold.dispose();
    _freeMaxDistance.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
    widget.onDirtyChanged?.call(true);
  }

  void _retry() => setState(() => _future = _load());

  ShopTakeoutConfig _collect() {
    return ShopTakeoutConfig(
      enabled: 1,
      minOrderAmount: double.tryParse(_minOrder.text),
      leadTimeMinutes: int.tryParse(_leadTime.text),
      deliveryFee: double.tryParse(_deliveryFee.text),
      maxDeliveryDistanceKm: double.tryParse(_maxDistance.text),
      freeDeliveryThreshold: double.tryParse(_freeThreshold.text),
      freeDeliveryMaxDistanceKm: double.tryParse(_freeMaxDistance.text),
      remark: _remark.text,
      tiers: List.of(_tiers),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.repository.saveTakeoutConfig(_collect());
      _dirty = false;
      widget.onDirtyChanged?.call(false);
      showSettingsSaved(context, '配送规则已保存');
    } catch (e) {
      showSettingsSaved(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _restoreDefaults() {
    setState(() {
      _minOrder.text = '68';
      _leadTime.text = '30';
      _deliveryFee.text = '0';
      _maxDistance.text = '5';
      _freeThreshold.text = '168';
      _freeMaxDistance.text = '5';
      _remark.text = '起送68元；1-3km 5元、3-4km 8元、4-5km 10元；满168元5公里内免配送费';
      _tiers = _defaultTiers();
      _dirty = true;
    });
    widget.onDirtyChanged?.call(true);
  }

  @override
  Widget build(BuildContext context) => CashierSettingsDeliveryScaffold(
    section: const SettingsSectionSpec(
      'delivery:rules',
      '配送规则',
      Icons.alt_route_outlined,
    ),
    child: FutureBuilder<ShopTakeoutConfig>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SettingsSkeletonLoader();
        }
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '配送规则加载失败：${snapshot.error}',
            onRetry: _retry,
          );
        }
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            SettingsPanel(
              title: '配送规则',
              child: Column(
                children: [
                  _ruleRow(
                    label: '起送价（元）',
                    controller: _minOrder,
                    hint: '低于起送价的订单不可下单',
                  ),
                  _ruleRow(
                    label: '预计送达（分钟）',
                    controller: _leadTime,
                  ),
                  _ruleRow(
                    label: '固定配送费（元）',
                    controller: _deliveryFee,
                    hint: '配置距离阶梯时以阶梯为准',
                  ),
                  _ruleRow(
                    label: '最远配送距离（km）',
                    controller: _maxDistance,
                    hint: '超出不可下单',
                  ),
                  _ruleRow(
                    label: '满额免配送费（元）',
                    controller: _freeThreshold,
                  ),
                  _ruleRow(
                    label: '免配送费最远距离（km）',
                    controller: _freeMaxDistance,
                  ),
                  _ruleRow(
                    label: '备注',
                    controller: _remark,
                    expanded: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SettingsPanel(
              title: '距离阶梯运费',
              child: Column(
                children: [
                  Text(
                    '按送达距离阶梯计费（delivery_fee_tiers_json），可增删行。',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._tiers.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tier = entry.value;
                    final fromKm = index == 0
                        ? 0.0
                        : _tiers[index - 1].toKm;
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        key: Key('delivery-tier-$index'),
                        children: [
                          SizedBox(
                            width: 110,
                            child: Text(
                              '$fromKm 公里起',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.cashier.inkSecondary,
                              ),
                            ),
                          ),
                          _tierNumberField(
                            key: Key('delivery-tier-to-$index'),
                            value: tier.toKm,
                            unit: 'km 内',
                            onChanged: (text) {
                              final v = double.tryParse(text);
                              if (v == null) return;
                              setState(() {
                                _tiers = List.of(_tiers)
                                  ..[index] = DeliveryFeeTier(
                                    toKm: v,
                                    fee: _tiers[index].fee,
                                  );
                              });
                              _markDirty();
                            },
                          ),
                          const SizedBox(width: 12),
                          _tierNumberField(
                            key: Key('delivery-tier-fee-$index'),
                            value: tier.fee,
                            unit: '元',
                            onChanged: (text) {
                              final v = double.tryParse(text);
                              if (v == null) return;
                              setState(() {
                                _tiers = List.of(_tiers)
                                  ..[index] = DeliveryFeeTier(
                                    toKm: _tiers[index].toKm,
                                    fee: v,
                                  );
                              });
                              _markDirty();
                            },
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton(
                            key: Key('delivery-tier-remove-$index'),
                            onPressed: () {
                              if (_tiers.length <= 1) return;
                              setState(() => _tiers = List.of(_tiers)
                                ..removeAt(index));
                              _markDirty();
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: context.cashier.danger,
                              minimumSize: const Size(64, 34),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text('删除', style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const Key('delivery-tier-add'),
                      onPressed: () {
                        final last = _tiers.isNotEmpty
                            ? _tiers.last.toKm
                            : 3.0;
                        setState(() {
                          _tiers = List.of(_tiers)
                            ..add(DeliveryFeeTier(
                              toKm: last + 1,
                              fee: _tiers.isNotEmpty ? _tiers.last.fee : 5,
                            ));
                        });
                        _markDirty();
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('新增阶梯'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '超过最远距离的订单不可下单',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _restoreDefaults,
                  child: const Text('恢复默认'),
                ),
                const SizedBox(width: 12),
                SettingsPrimaryButton(
                  label: '保存规则',
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  Widget _ruleRow({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool expanded = false,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.cashier.row, width: 1)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 190,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: context.cashier.inkSecondary),
          ),
        ),
        SizedBox(
          width: expanded ? 360 : 170,
          child: TextField(
            controller: controller,
            keyboardType: expanded
                ? TextInputType.multiline
                : const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _markDirty(),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hint,
              style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
            ),
          ),
        ],
      ],
    ),
  );

  Widget _tierNumberField({
    required Key key,
    required double value,
    required String unit,
    required ValueChanged<String> onChanged,
  }) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 90,
        child: TextField(
          key: key,
          controller: TextEditingController(text: _fmt(value, '0')),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
      const SizedBox(width: 6),
      Text(unit, style: TextStyle(fontSize: 13, color: context.cashier.inkMuted)),
    ],
  );
}

// ============ 真省钱配送 ============

class _ZsqSection extends StatefulWidget {
  const _ZsqSection({required this.repository, this.onDirtyChanged});

  final CashierSettingsRepository repository;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<_ZsqSection> createState() => _ZsqSectionState();
}

class _ZsqSectionState extends State<_ZsqSection> {
  late Future<ZsqAutoApiConfig> _future;
  late ZsqAutoApiConfig _current;
  bool _auto = false;
  bool _sync = false;
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<ZsqAutoApiConfig> _load() async {
    final config = await widget.repository.loadZsqAutoApi();
    _current = config;
    _auto = config.autoDispatchEnabled;
    _sync = config.takeoutSyncEnabled;
    return config;
  }

  void _retry() => setState(() => _future = _load());

  void _markDirty() {
    if (_dirty) return;
    setState(() => _dirty = true);
    widget.onDirtyChanged?.call(true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final saved = await widget.repository.saveZsqAutoApi(
        _current.copyWith(
          autoDispatchEnabled: _auto,
          takeoutSyncEnabled: _sync,
        ),
      );
      _current = saved;
      _dirty = false;
      widget.onDirtyChanged?.call(false);
      showSettingsSaved(context, '真省钱开关已保存');
    } catch (e) {
      showSettingsSaved(context, '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => CashierSettingsDeliveryScaffold(
    section: const SettingsSectionSpec(
      'delivery:zsq',
      '真省钱配送',
      Icons.delivery_dining_outlined,
    ),
    child: FutureBuilder<ZsqAutoApiConfig>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SettingsSkeletonLoader();
        }
        if (snapshot.hasError) {
          return SettingsErrorState(
            message: '真省钱配置加载失败：${snapshot.error}',
            onRetry: _retry,
          );
        }
        return ListView(
          padding: EdgeInsets.zero,
          children: [
            _DeliveryHeroCard(
              icon: Icons.delivery_dining_outlined,
              title: '真省钱聚合配送',
              description: '接入真省钱平台叫骑手。开关写入 t_system_config'
                  '（zsq.auto_api.enabled / zsq.takeout_sync.enabled），按门店隔离。',
              trailing: SettingsStatusBadge(
                type: StatusBadgeType.info,
                label: '已接入',
              ),
            ),
            const SizedBox(height: 16),
            SettingsPanel(
              title: '配送开关',
              child: Column(
                children: [
                  _switchRow(
                    key: const Key('delivery-zsq-auto'),
                    label: '接单后自动发配送',
                    hint: 'autoDispatchEnabled：商家接单后自动向真省钱叫骑手',
                    value: _auto,
                    onChanged: (v) {
                      setState(() => _auto = v);
                      _markDirty();
                    },
                  ),
                  _switchRow(
                    key: const Key('delivery-zsq-sync'),
                    label: '外卖状态定时同步',
                    hint: 'takeoutSyncEnabled：定时回写骑手位置与履约状态',
                    value: _sync,
                    onChanged: (v) {
                      setState(() => _sync = v);
                      _markDirty();
                    },
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SettingsPrimaryButton(
                      label: '保存开关',
                      loading: _saving,
                      onPressed: _save,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SettingsPanel(
              title: '配送操作说明',
              child: Text(
                '手动叫骑手、重发与同步均以配送记录中的订单为入口：\n'
                '发单：为订单呼叫聚合配送骑手\n'
                '重发：订单异常或取消后重新发单\n'
                '同步：手动刷新配送状态\n'
                '追踪：查看骑手定位与预计送达时间',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.9,
                  fontFamily: 'monospace',
                  color: context.cashier.inkSecondary,
                ),
              ),
            ),
          ],
        );
      },
    ),
  );

  Widget _switchRow({
    required Key key,
    required String label,
    required String hint,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: context.cashier.row, width: 1)),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 190,
          child: Text(
            label,
            style: TextStyle(fontSize: 14, color: context.cashier.inkSecondary),
          ),
        ),
        Switch(
          key: key,
          value: value,
          activeTrackColor: context.cashier.selected,
          onChanged: onChanged,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            hint,
            style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
          ),
        ),
      ],
    ),
  );
}

// ============ 配送记录 ============

class _RecordsSection extends StatefulWidget {
  const _RecordsSection({required this.repository});

  final CashierSettingsRepository repository;

  @override
  State<_RecordsSection> createState() => _RecordsSectionState();
}

class _RecordsSectionState extends State<_RecordsSection> {
  int _page = 1;
  String? _dispatchStatus;
  String _timeRange = 'all'; // all / today / yesterday / 7d
  PagedTakeoutDeliveries? _data;
  Object? _error;
  bool _loading = true;
  int _requestSeq = 0;

  /// 快捷时间范围 → [start, end]（年月日，营业日截止由后端按 settle_time 补全）。
  (DateTime?, DateTime?) _windowOf(String range) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (range) {
      'today' => (today, today),
      'yesterday' => (
          DateTime(now.year, now.month, now.day - 1),
          DateTime(now.year, now.month, now.day - 1),
        ),
      '7d' => (DateTime(now.year, now.month, now.day - 6), today),
      _ => (null, null),
    };
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final seq = ++_requestSeq;
    if (mounted) setState(() => _loading = true);
    try {
      final (start, end) = _windowOf(_timeRange);
      final result = await widget.repository.loadTakeoutDeliveries(
        page: _page,
        pageSize: 20,
        dispatchStatus: _dispatchStatus,
        start: start,
        end: end,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _data = result;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _retry() => _load();

  void _reload() {
    _page = 1;
    _load();
  }

  void _setFilter(String? status) {
    _dispatchStatus = status;
    _page = 1;
    _load();
  }

  void _setTimeRange(String range) {
    if (range == _timeRange) return;
    _timeRange = range;
    _page = 1;
    _load();
  }

  void _goPage(int page) {
    if (page < 1 || page == _page || _loading) return;
    _page = page;
    _load();
  }

  Future<void> _openDetail(int orderId) async {
    try {
      final detail = await widget.repository.loadTakeoutDeliveryDetail(orderId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _DeliveryDetailDialog(detail: detail),
      );
    } catch (e) {
      showSettingsSaved(context, '详情加载失败：$e');
    }
  }

  Future<void> _openTracking(int orderId) async {
    try {
      final tracking = await widget.repository.loadTakeoutTracking(orderId);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _TrackingDialog(
          tracking: tracking,
          onRedispatch: () async {
            Navigator.of(context).pop();
            await _operate(orderId, 'redispatch');
          },
        ),
      );
    } catch (e) {
      showSettingsSaved(context, '追踪加载失败：$e');
    }
  }

  Future<void> _operate(int orderId, String action) async {
    final confirmLabels = <String, String>{
      'complete': '完成配送',
      'cancel': '取消配送',
      'dispatch': '发送配送',
      'redispatch': '重发配送',
    };
    final confirm = await showSettingsConfirmDialog(
      context: context,
      title: confirmLabels[action] ?? '操作确认',
      message: '确定对订单 #$orderId 执行「${confirmLabels[action] ?? action}」？',
      destructive: action == 'cancel',
    );
    if (confirm != true) return;
    try {
      switch (action) {
        case 'complete':
          await widget.repository.updateTakeoutDeliveryStatus(
            orderId,
            'completed',
          );
          break;
        case 'cancel':
          await widget.repository.updateTakeoutDeliveryStatus(orderId, 'cancelled');
          break;
        case 'dispatch':
          await widget.repository.zsqDispatch(orderId);
          break;
        case 'redispatch':
          await widget.repository.zsqDispatch(orderId, redispatch: true);
          break;
        case 'sync':
          await widget.repository.zsqSync(orderId);
          break;
      }
      showSettingsSaved(context, '操作成功');
      _reload();
    } catch (e) {
      showSettingsSaved(context, '操作失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_loading) {
      body = const SettingsSkeletonLoader();
    } else if (_error != null) {
      body = SettingsErrorState(
        message: '配送记录加载失败：$_error',
        onRetry: _retry,
      );
    } else {
      final data = _data!;
      final items = data.items;
      final totalPages = (data.total / 20).ceil().clamp(1, 1 << 31);
      body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RecordsStatsStrip(items: items),
            const SizedBox(height: 16),
            Row(
              children: [
                DropdownButton<String>(
                  key: const Key('delivery-records-time-range'),
                  value: _timeRange,
                  items: const [
                    DropdownMenuItem<String>(
                      value: 'all',
                      child: Text('全部时间'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'today',
                      child: Text('今日'),
                    ),
                    DropdownMenuItem<String>(
                      value: 'yesterday',
                      child: Text('昨日'),
                    ),
                    DropdownMenuItem<String>(
                      value: '7d',
                      child: Text('近7天'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) _setTimeRange(v);
                  },
                ),
                const SizedBox(width: 16),
                DropdownButton<String?>(
                  key: const Key('delivery-records-filter'),
                  value: _dispatchStatus,
                  items: const [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text('全部状态'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'accepted',
                      child: Text('待配送'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'delivering',
                      child: Text('配送中'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'completed',
                      child: Text('已完成'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'cancelled',
                      child: Text('已取消'),
                    ),
                    DropdownMenuItem<String?>(
                      value: 'dispatch_failed',
                      child: Text('配送失败'),
                    ),
                  ],
                  onChanged: _setFilter,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? SettingsEmptyState(
                      title: _dispatchStatus == null
                          ? '暂无配送记录'
                          : '没有符合条件的配送记录',
                      description: '配送记录来自配送管理数据接口',
                      primaryActionLabel: _dispatchStatus == null
                          ? null
                          : '查看全部',
                      onPrimaryAction: _dispatchStatus == null
                          ? null
                          : () => _setFilter(null),
                    )
                  : _RecordsTable(
                      items: items,
                      onDetail: _openDetail,
                      onTracking: _openTracking,
                      onComplete: (id) => _operate(id, 'complete'),
                      onCancel: (id) => _operate(id, 'cancel'),
                      onDispatch: (id) => _operate(id, 'dispatch'),
                      onRedispatch: (id) => _operate(id, 'redispatch'),
                      onSync: (id) => _operate(id, 'sync'),
                    ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '共 ${data.total} 条 · 第 $_page/$totalPages 页（统计为当前页）',
                  style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
                ),
                const Spacer(),
                OutlinedButton(
                  onPressed: _page <= 1 ? null : () => _goPage(_page - 1),
                  child: const Text('上一页'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _page >= totalPages
                      ? null
                      : () => _goPage(_page + 1),
                  child: const Text('下一页'),
                ),
              ],
            ),
          ],
        );
      }
      return CashierSettingsDeliveryScaffold(
        section: const SettingsSectionSpec(
          'delivery:records',
          '配送记录',
          Icons.history_outlined,
        ),
        child: body,
      );
    }
}

class _RecordsStatsStrip extends StatelessWidget {
  const _RecordsStatsStrip({required this.items});

  final List<TakeoutDeliveryRecord> items;

  @override
  Widget build(BuildContext context) {
    var delivering = 0;
    var completed = 0;
    var abnormal = 0;
    var feeTotal = 0.0;
    for (final item in items) {
      final status = item.dispatchStatus;
      if (status == 'accepted' || status == 'delivering') delivering++;
      if (status == 'completed') completed++;
      if (status == 'dispatch_failed' ||
          status == 'rider_cancelled' ||
          item.zsqDispatchStatus == 'order_missing' ||
          item.zsqDispatchStatus == 'failed') {
        abnormal++;
      }
      feeTotal += item.deliveryFee ?? 0;
    }
    return Row(
      children: [
        _statCard(context, '配送中（本页）', '$delivering', null),
        _statCard(context, '已完成（本页）', '$completed', null),
        _statCard(
          context,
          '异常待处理（本页）',
          '$abnormal',
          abnormal > 0 ? context.cashier.danger : null,
        ),
        _statCard(
          context,
          '配送费合计（本页）',
          '¥${feeTotal.toStringAsFixed(2)}',
          null,
        ),
      ],
    );
  }

  Widget _statCard(
    BuildContext context,
    String label,
    String value,
    Color? valueColor,
  ) => Expanded(
    child: Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: valueColor ?? context.cashier.ink,
            ),
          ),
        ],
      ),
    ),
  );
}

class _RecordsTable extends StatelessWidget {
  const _RecordsTable({
    required this.items,
    required this.onDetail,
    required this.onTracking,
    required this.onComplete,
    required this.onCancel,
    required this.onDispatch,
    required this.onRedispatch,
    required this.onSync,
  });

  final List<TakeoutDeliveryRecord> items;
  final void Function(int) onDetail;
  final void Function(int) onTracking;
  final void Function(int) onComplete;
  final void Function(int) onCancel;
  final void Function(int) onDispatch;
  final void Function(int) onRedispatch;
  final void Function(int) onSync;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: context.cashier.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: context.cashier.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1230,
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(150),
            1: FixedColumnWidth(150),
            2: FixedColumnWidth(220),
            3: FixedColumnWidth(80),
            4: FixedColumnWidth(110),
            5: FixedColumnWidth(120),
            6: FixedColumnWidth(140),
            7: FixedColumnWidth(260),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: context.cashier.row,
                border: Border(
                  bottom: BorderSide(
                    color: context.cashier.border,
                    width: 1,
                  ),
                ),
              ),
              children: [
                _header(context, '订单号'),
                _header(context, '收货信息'),
                _header(context, '地址'),
                _header(context, '配送费'),
                _header(context, '履约状态'),
                _header(context, '真省钱状态'),
                _header(context, '下单时间'),
                _header(context, '操作'),
              ],
            ),
            ...items.map((item) => TableRow(
              decoration: BoxDecoration(
                color: context.cashier.surface,
                border: Border(
                  bottom: BorderSide(color: context.cashier.row, width: 1),
                ),
              ),
              children: [
                _cell(
                  context,
                  Text(
                    item.orderNo.isEmpty
                        ? '#${item.orderId}'
                        : item.orderNo,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: context.cashier.ink,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.receiverName.isEmpty ? '-' : item.receiverName,
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        item.receiverPhone.isEmpty ? '' : item.receiverPhone,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                _cell(
                  context,
                  Text(
                    item.addressFull.isEmpty ? '-' : item.addressFull,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.deliveryFee == null
                            ? '-'
                            : '¥${item.deliveryFee!.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (item.actualDeliveryFee != null &&
                          item.actualDeliveryFee != item.deliveryFee)
                        Text(
                          '实付 ¥${item.actualDeliveryFee!.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.cashier.inkMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                _cell(
                  context,
                  SettingsStatusBadge(
                    type: _statusType(item.dispatchStatus),
                    label: _statusLabel(item.dispatchStatus),
                  ),
                ),
                _cell(
                  context,
                  SettingsStatusBadge(
                    type: _zsqStatusType(item),
                    label: _zsqStatusLabel(item),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    _formatTime(item.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _rowAction(context, '详情', () => onDetail(item.orderId)),
                      if (item.dispatchStatus == 'accepted' ||
                          item.dispatchStatus == 'delivering') ...[
                        _rowAction(
                          context,
                          '追踪',
                          () => onTracking(item.orderId),
                        ),
                        _rowAction(context, '同步', () => onSync(item.orderId)),
                        _rowAction(
                          context,
                          '完成',
                          () => onComplete(item.orderId),
                        ),
                      ],
                      if (item.dispatchStatus == 'dispatch_failed') ...[
                        _rowAction(
                          context,
                          '重发',
                          () => onRedispatch(item.orderId),
                        ),
                        _rowAction(
                          context,
                          '取消',
                          () => onCancel(item.orderId),
                        ),
                      ],
                      if (item.dispatchStatus == 'cancelled')
                        _rowAction(
                          context,
                          '重发',
                          () => onRedispatch(item.orderId),
                        ),
                      if (item.dispatchStatus == 'paid' ||
                          item.dispatchStatus == 'submitted') ...[
                        _rowAction(
                          context,
                          '发配送',
                          () => onDispatch(item.orderId),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            )),
          ],
        ),
      ),
    ),
  );

  Widget _header(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.cashier.inkMuted,
      ),
    ),
  );

  Widget _cell(BuildContext context, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: child,
  );

  Widget _rowAction(
    BuildContext context,
    String label,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(52, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    ),
  );
}

StatusBadgeType _statusType(String status) {
  switch (status) {
    case 'completed':
      return StatusBadgeType.success;
    case 'cancelled':
      return StatusBadgeType.danger;
    case 'dispatch_failed':
    case 'rider_cancelled':
      return StatusBadgeType.warning;
    case 'accepted':
    case 'delivering':
      return StatusBadgeType.info;
    default:
      return StatusBadgeType.neutral;
  }
}

String _statusLabel(String status) {
  switch (status) {
    case 'submitted':
      return '已提交';
    case 'paid':
      return '已付款';
    case 'accepted':
      return '已接单';
    case 'delivering':
      return '配送中';
    case 'completed':
      return '已完成';
    case 'cancelled':
      return '已取消';
    case 'dispatch_failed':
      return '配送失败';
    case 'rider_cancelled':
      return '骑手取消';
    default:
      return status.isEmpty ? '-' : status;
  }
}

StatusBadgeType _zsqStatusType(TakeoutDeliveryRecord item) {
  switch (item.zsqDispatchStatus) {
    case 'completed':
      return StatusBadgeType.success;
    case 'cancelled':
    case 'rider_cancelled':
    case 'order_missing':
      return StatusBadgeType.danger;
    case 'failed':
      return StatusBadgeType.warning;
    case 'dispatched':
    case 'pending':
      return StatusBadgeType.info;
    default:
      return StatusBadgeType.neutral;
  }
}

String _zsqStatusLabel(TakeoutDeliveryRecord item) {
  final phase = item.zsqPhase;
  if (phase == 'ORDER_MISSING') return '订单缺失';
  switch (item.zsqDispatchStatus) {
    case 'completed':
      return '已送达';
    case 'dispatched':
      return '已发单';
    case 'pending':
      return '等待中';
    case 'failed':
      return item.zsqRiderName.isEmpty ? '发单失败' : '失败';
    case 'rider_cancelled':
      return '骑手取消';
    case 'cancelled':
      return '已取消';
    case 'order_missing':
      return '订单缺失';
    default:
      return item.zsqDispatchStatus.isEmpty ? '-' : item.zsqDispatchStatus;
  }
}

String _formatTime(DateTime? time) {
  if (time == null) return '-';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

// ============ 详情 / 追踪弹窗 ============

class _DeliveryDetailDialog extends StatelessWidget {
  const _DeliveryDetailDialog({required this.detail});

  final TakeoutDeliveryDetail detail;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(Icons.receipt_long_outlined, color: context.cashier.selected),
        const SizedBox(width: 10),
        const Text('配送单详情'),
      ],
    ),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detailRow(context, '订单号', detail.orderNo),
            if (detail.delivery != null) ...[
              _detailRow(
                context,
                '收货人',
                '${detail.delivery!.receiverName}'
                    '${detail.delivery!.receiverPhone.isEmpty ? '' : ' · ${detail.delivery!.receiverPhone}'}',
              ),
              _detailRow(context, '配送地址', detail.delivery!.addressFull),
              _detailRow(
                context,
                '配送费',
                detail.delivery!.deliveryFee == null
                    ? '-'
                    : '¥${detail.delivery!.deliveryFee!.toStringAsFixed(2)}',
              ),
              if (detail.delivery!.actualDeliveryFee != null &&
                  detail.delivery!.actualDeliveryFee !=
                      detail.delivery!.deliveryFee)
                _detailRow(
                  context,
                  '实际配送费',
                  '¥${detail.delivery!.actualDeliveryFee!.toStringAsFixed(2)}'
                      '（平台实付，取自 zsq_actual_fee）',
                ),
              _detailRow(
                context,
                '履约状态',
                '${_statusLabel(detail.delivery!.dispatchStatus)}'
                    '（${detail.delivery!.zsqPhase.isEmpty ? '-' : detail.delivery!.zsqPhase}）',
              ),
              if (detail.delivery!.zsqRiderName.isNotEmpty)
                _detailRow(context, '骑手', detail.delivery!.zsqRiderName),
              if (detail.delivery!.zsqOrderId.isNotEmpty)
                _detailRow(context, '真省钱订单', detail.delivery!.zsqOrderId),
            ],
            _detailRow(context, '下单时间', _formatTime(detail.createdAt)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  );

  Widget _detailRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: context.cashier.inkMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
}

class _TrackingDialog extends StatelessWidget {
  const _TrackingDialog({
    required this.tracking,
    this.onRedispatch,
  });

  final ZsqRiderTracking tracking;
  final VoidCallback? onRedispatch;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(Icons.delivery_dining_outlined, color: context.cashier.selected),
        const SizedBox(width: 10),
        const Text('骑手实时定位'),
      ],
    ),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (tracking.canRedispatch) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.cashier.warningBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '真省钱远端订单已不存在/已删除（order_missing），可重发配送。',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.cashier.warning,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            _detailRow(
              context,
              '骑手',
              tracking.riderName == null
                  ? '暂无骑手'
                  : '${tracking.riderName}'
                      '${tracking.riderPhone == null ? '' : ' · ${tracking.riderPhone}'}',
            ),
            _detailRow(
              context,
              '状态',
              '${tracking.statusDesc ?? '-'}'
                  '${tracking.phase == null ? '' : '（${tracking.phase}）'}',
            ),
            if (tracking.platformDistanceText != null ||
                tracking.platformDurationText != null)
              _detailRow(
                context,
                '距离 / 时长',
                '${tracking.platformDistanceText ?? '-'} · '
                    '${tracking.platformDurationText ?? '-'}',
              ),
            if (tracking.toShopMinutes != null)
              _detailRow(context, '预计到店', '${tracking.toShopMinutes} 分钟'),
            if (tracking.toUserMinutes != null)
              _detailRow(context, '预计送达', '${tracking.toUserMinutes} 分钟'),
            const SizedBox(height: 8),
            Text(
              '配送时间线',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.cashier.inkSecondary,
              ),
            ),
            const SizedBox(height: 6),
            if (tracking.logs.isEmpty)
              Text(
                '暂无轨迹日志',
                style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
              )
            else
              ...tracking.logs.reversed.map(
                (log) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 130,
                        child: Text(
                          _formatTime(log.time),
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            color: context.cashier.inkMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          log.text,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (tracking.canRedispatch && onRedispatch != null)
        FilledButton(
          key: const Key('delivery-tracking-redispatch'),
          onPressed: onRedispatch,
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink,
          ),
          child: const Text('重发配送'),
        ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('关闭'),
      ),
    ],
  );

  Widget _detailRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: context.cashier.inkMuted,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value.isEmpty ? '-' : value,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
}
