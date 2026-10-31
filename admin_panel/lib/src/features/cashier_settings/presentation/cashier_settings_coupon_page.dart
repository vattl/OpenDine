import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../data/cashier_settings_repository.dart';
import '../data/coupon_repository.dart';
import '../data/real_coupon_repository.dart';
import '../domain/coupon_models.dart';
import 'cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 优惠券管理页（M-J 优惠券管理）。
/// coupons（券模板）/ redeem-codes（兑换码核销与二维码）/
/// grant（Excel 批量发券）/ user-coupons（用户券解绑作废）四分区闭环。
/// 所有数据与操作走真实仓库；无接口客户端时显示错误态，不回退占位页。
class CashierSettingsCouponPage extends StatelessWidget {
  const CashierSettingsCouponPage({
    super.key,
    required this.repository,
    required this.client,
    required this.section,
    this.now,
  });

  final CashierSettingsRepository repository;
  final AdminApiClient? client;
  final SettingsSectionSpec section;

  /// 可注入时钟（截图/测试固定时间；缺省为实时）。
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final apiClient = client;
    if (apiClient == null) {
      return const SettingsErrorState(
        message: '接口未连接，无法加载优惠券数据。请检查登录状态或网络后重试。',
      );
    }
    final coupon = RealCouponRepository(apiClient);
    switch (section.id) {
      case 'coupons':
        return _CouponsSection(repository: coupon, client: apiClient, now: now);
      case 'redeem-codes':
        return _RedeemCodesSection(repository: coupon, now: now);
      case 'grant':
        return _GrantSection(repository: coupon);
      case 'user-coupons':
        return _UserCouponsSection(repository: coupon, now: now);
      default:
        return SettingsErrorState(message: '未知优惠券分区：${section.id}');
    }
  }
}

const _couponStatusLabels = {0: '未启用', 1: '可用', 2: '已下架'};
const _redeemStatusLabels = {0: '未核销', 1: '已核销'};
const _userCouponStatusLabels = {0: '未使用', 1: '已使用', 2: '已失效'};
const _couponTypeLabels = {
  'full_reduction': '满减',
  'discount': '折扣',
  'direct_reduction': '直减',
};

class _CouponsSection extends StatefulWidget {
  const _CouponsSection({
    required this.repository,
    required this.client,
    this.now,
  });

  final CouponRepository repository;
  final AdminApiClient client;

  /// 可注入时钟（测试/截图用固定时间；缺省为实时）。
  final DateTime Function()? now;

  @override
  State<_CouponsSection> createState() => _CouponsSectionState();
}

class _CouponsSectionState extends State<_CouponsSection> {
  int? _statusFilter;
  late Future<List<CouponTemplate>> _future;
  int _totalCount = 0;
  DateTime? _lastUpdated;
  var _refreshing = false;

  /// 行内写操作（上架/下架/删除）进行中的券 id（防连点 + 按钮 loading）。
  final _rowBusy = <int>{};

  /// 鼠标悬停高亮的行 id（对齐原型 tbody tr:hover）。
  int? _hoverRowId;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<CouponTemplate>> _load() async {
    final list = await widget.repository.loadCoupons(status: _statusFilter);
    if (mounted) {
      setState(() {
        _totalCount = list.length;
        _lastUpdated = _now();
      });
    }
    return list;
  }

  void _reload() => setState(() {
    _refreshing = true;
    _future = _load().whenComplete(() {
      if (mounted) setState(() => _refreshing = false);
    });
  });

  void _applyFilter(int? status) => setState(() {
    _statusFilter = status;
    _refreshing = true;
    _future = _load().whenComplete(() {
      if (mounted) setState(() => _refreshing = false);
    });
  });

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _statusFilter == null,
                      onSelected: (_) => _applyFilter(null),
                    ),
                    for (final entry in _couponStatusLabels.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _statusFilter == entry.key,
                        onSelected: (_) => _applyFilter(entry.key),
                      ),
                  ],
                ),
              ),
              Text(
                '共 $_totalCount 条',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _lastUpdated == null ? '' : '更新于 ${_formatUpdatedTime(_lastUpdated!)}',
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
              const SizedBox(width: 4),
              _RefreshButton(
                key: const Key('coupon-coupons-refresh'),
                busy: _refreshing,
                onPressed: _reload,
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                key: const Key('coupon-add-button'),
                onPressed: () => _openForm(null),
                style: FilledButton.styleFrom(
                  backgroundColor: context.cashier.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增优惠券'),
              ),
            ],
          ),
          if (_refreshing) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
          Expanded(
            child: FutureBuilder<List<CouponTemplate>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SettingsErrorState(
                    message: '加载券模板失败：${snapshot.error}',
                    onRetry: _reload,
                  );
                }
                if (!snapshot.hasData) {
                  return const SettingsSkeletonLoader(rows: 3);
                }
                final coupons = snapshot.data!;
                if (coupons.isEmpty) {
                  return SettingsEmptyState(
                    title: '暂无优惠券模板',
                    description: '可在运营后台创建券模板后在此管理。',
                    primaryActionLabel: '新增优惠券',
                    onPrimaryAction: () => _openForm(null),
                  );
                }
                return LayoutBuilder(
                  builder: (context, constraints) {
                    const minTableWidth = 1232.0;
                    final tableWidth = math.max(
                      constraints.maxWidth,
                      minTableWidth,
                    );
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: Table(
                          columnWidths: _tableColumns(
                            constraints.maxWidth,
                            minWidth: minTableWidth,
                            fixed: const [
                              (1, 90),
                              (2, 110),
                              (3, 92),
                              (5, 70),
                              (7, 110),
                              (8, 230),
                            ],
                            flex: const [
                              (0, 200, 1.7),
                              (4, 150, 1.0),
                              (6, 180, 1.2),
                            ],
                          ),
                          defaultVerticalAlignment:
                              TableCellVerticalAlignment.middle,
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(
                                color: Color(0xfff5f5f5),
                                border: Border(
                                  bottom: BorderSide(color: Color(0xffe5e7eb)),
                                ),
                              ),
                              children: [
                                _tableHeader(context, '券模板'),
                                _tableHeader(context, '类型'),
                                _tableHeader(context, '面值'),
                                _tableHeader(context, '门槛'),
                                _tableHeader(context, '库存'),
                                _tableHeader(context, '已发'),
                                _tableHeader(context, '有效期'),
                                _tableHeader(context, '状态'),
                                _tableHeader(context, '操作'),
                        ],
                      ),
                              for (var i = 0; i < coupons.length; i++)
                                _couponTableRow(
                                  context,
                                  coupons[i],
                                  zebra: i.isOdd,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
              },
            ),
          ),
        ],
      ),
    );
  }

  TableRow _couponTableRow(
    BuildContext context,
    CouponTemplate coupon, {
    bool zebra = false,
  }) {
    final statusLabel = _couponStatusLabels[coupon.status] ?? '未知';
    final statusType = switch (coupon.status) {
      1 => StatusBadgeType.success,
      2 => StatusBadgeType.neutral,
      _ => StatusBadgeType.warning,
    };
    final typeLabel =
        _couponTypeLabels[coupon.couponType] ?? coupon.couponType;
    final busy = _rowBusy.contains(coupon.id);
    final hovered = _hoverRowId == coupon.id;
    Widget cell(Widget child) => MouseRegion(
      onEnter: (_) => setState(() => _hoverRowId = coupon.id),
      onExit: (_) => setState(() => _hoverRowId = null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );
    // 库存：占比条（已发/库存），无限库存显示「无限」。
    final stockWidget = coupon.stock == -1
        ? const Text(
            '无限',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  width: 110,
                  height: 5,
                  child: LinearProgressIndicator(
                    value: coupon.stock <= 0
                        ? 0.0
                        : (coupon.grantedCount / coupon.stock).clamp(0.0, 1.0),
                    backgroundColor: context.cashier.subtle,
                    valueColor: AlwaysStoppedAnimation(
                      coupon.stock > 0 &&
                              (coupon.grantedCount / coupon.stock) > 0.9
                          ? context.cashier.warning
                          : context.cashier.success,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '已发 ${coupon.grantedCount}/${coupon.stock}',
                style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
              ),
            ],
          );
    // 有效期：已过期 / 30 天内到期着色。
    final expiryWidget = _expiryCell(context, coupon);
    return TableRow(
      decoration: BoxDecoration(
        color: hovered
            ? const Color(0xfff5f5f5)
            : (zebra ? const Color(0xfffafafa) : null),
        border: const Border(
          bottom: BorderSide(color: Color(0xfff1f1f1))),
      ),
      children: [
        // 券模板：名称 + 规则说明。
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              coupon.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                ),
            ),
            const SizedBox(height: 2),
            Text(
              '#${coupon.id} · ${coupon.description ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
            ),
          ],
        ),
        ),
        // 类型。
        cell(Text(typeLabel, style: const TextStyle(fontSize: 13))),
        // 面值块。
        cell(Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: context.cashier.successBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '¥${coupon.discountValue.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xff166534),
                ),
              ),
              const SizedBox(height: 1),
              Text(
                typeLabel,
                style: TextStyle(
                  fontSize: 10,
                  color: context.cashier.inkSecondary,
                ),
              ),
            ],
          ),
        ),
        ),
        // 门槛。
        cell(Text(
          '¥${coupon.minAmount.toStringAsFixed(2)}',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 13),
        ),
        ),
        // 库存。
        cell(stockWidget),
        // 已发。
        cell(Text(
          '${coupon.grantedCount}',
          textAlign: TextAlign.right,
          style: const TextStyle(fontSize: 13),
        ),
        ),
        // 有效期。
        cell(expiryWidget),
        // 状态。
        cell(FittedBox(
          fit: BoxFit.scaleDown,
          child: SettingsStatusBadge(label: statusLabel, type: statusType),
        ),
        ),
        // 操作：两行（详情/编辑；上架下架/删除）。
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  key: Key('coupon-detail-${coupon.id}'),
                  onPressed: busy ? null : () => _showDetail(coupon),
                  icon: const Icon(Icons.info_outline, size: 15),
                  label: const Text('详情'),
                ),
                TextButton.icon(
                  key: Key('coupon-edit-${coupon.id}'),
                  onPressed: busy ? null : () => _openForm(coupon),
                  icon: const Icon(Icons.edit_outlined, size: 15),
                  label: const Text('编辑'),
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (coupon.status == 1)
                  TextButton.icon(
                    key: Key('coupon-status-toggle-${coupon.id}'),
                    onPressed: busy ? null : () => _toggleStatus(coupon, 2),
                    icon: busy
                        ? _busyIndicator(context)
                        : Icon(
                            Icons.visibility_off_outlined,
                            size: 15,
                            color: context.cashier.warning,
                          ),
                    label: Text(
                      '下架',
                      style: TextStyle(color: context.cashier.warning),
                    ),
                  )
                else
                  TextButton.icon(
                    key: Key('coupon-status-toggle-${coupon.id}'),
                    onPressed: busy ? null : () => _toggleStatus(coupon, 1),
                    icon: busy
                        ? _busyIndicator(context)
                        : Icon(
                            Icons.play_circle_outline,
                            size: 15,
                            color: context.cashier.success,
                          ),
                    label: Text(
                      '上架',
                      style: TextStyle(color: context.cashier.success),
                    ),
                  ),
                TextButton.icon(
                  key: Key('coupon-delete-${coupon.id}'),
                  onPressed: busy ? null : () => _deleteCoupon(coupon),
                  icon: busy
                      ? _busyIndicator(context)
                      : Icon(
                          Icons.delete_outline,
                          size: 15,
                          color: context.cashier.danger,
                        ),
                  label: Text(
                    '删除',
                    style: TextStyle(color: context.cashier.danger),
                  ),
                ),
              ],
            ),
          ],
        ),
        ),
      ],
    );
  }

  Widget _expiryCell(BuildContext context, CouponTemplate coupon) {
    final startRaw = coupon.startTime;
    final endRaw = coupon.endTime;
    final startText = startRaw != null && startRaw.length >= 10
        ? startRaw.substring(0, 10)
        : '-';
    final endText = endRaw != null && endRaw.length >= 10
        ? endRaw.substring(0, 10)
        : '-';
    final end = DateTime.tryParse(endRaw ?? '');
    if (end == null) {
      return Text(
        '$startText ~ $endText',
        style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
      );
    }
    final days = end.difference(DateTime.now()).inDays;
    if (days < 0) {
      return Text(
        '$endText · 已过期',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.cashier.danger,
        ),
      );
    }
    if (days <= 30) {
      return Text(
        '$endText · 即将到期',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: context.cashier.warning,
        ),
      );
    }
    return Text(
      '$startText ~ $endText',
      style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
    );
  }

  void _showDetail(CouponTemplate coupon) {
    showCouponDrawer<void>(
      context: context,
      title: '券模板详情：${coupon.name}',
      child: _CouponDetailDrawer(
        repository: widget.repository,
        couponId: coupon.id,
      ),
    );
  }

  Future<void> _openForm(CouponTemplate? existing) async {
    final result = await showCouponFormDrawer(
      context,
      existing,
      repository: widget.repository,
      client: widget.client,
    );
    if (result == null || !mounted) return;
    setState(() {
      _refreshing = true;
      _future = _load().whenComplete(() {
        if (mounted) setState(() => _refreshing = false);
      });
    });
    showSettingsSaved(
      context,
      result.created ? '优惠券已创建（ID ${result.id}）' : '优惠券已更新',
    );
  }

  Future<void> _deleteCoupon(CouponTemplate coupon) async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '删除优惠券模板',
      message: '删除「${coupon.name}」？已发放的用户券不受影响，但无法再领取该券。',
      destructive: true,
      confirmLabel: '删除',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rowBusy.add(coupon.id));
    try {
      await widget.repository.deleteCoupon(coupon.id);
      if (!mounted) return;
      showSettingsSaved(context, '优惠券已删除');
      setState(() {
        _rowBusy.remove(coupon.id);
        _refreshing = true;
        _future = _load().whenComplete(() {
          if (mounted) setState(() => _refreshing = false);
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _rowBusy.remove(coupon.id));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('删除失败：$error')));
    }
  }

  /// 快捷上架/下架（INV-COUPON-001）：已下架仅允许切回可用；可用只能下架。
  Future<void> _toggleStatus(CouponTemplate coupon, int target) async {
    final up = target == 1;
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: up ? '上架优惠券' : '下架优惠券',
      message: up
          ? '上架「${coupon.name}」后，用户可正常领取该券。'
          : '下架「${coupon.name}」后用户无法再领取，已发放的用户券仍可正常核销。',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rowBusy.add(coupon.id));
    try {
      await widget.repository.updateCoupon(
        CouponTemplate(
          id: coupon.id,
          name: coupon.name,
          couponType: coupon.couponType,
          status: target,
          discountValue: coupon.discountValue,
          minAmount: coupon.minAmount,
          startTime: coupon.startTime,
          endTime: coupon.endTime,
          stock: coupon.stock,
          grantedCount: coupon.grantedCount,
          description: coupon.description,
          validityTime: coupon.validityTime,
          applyDishIds: coupon.applyDishIds,
          applyDiningType: coupon.applyDiningType,
        ),
      );
      if (!mounted) return;
      showSettingsSaved(context, up ? '优惠券已上架' : '优惠券已下架');
      setState(() {
        _rowBusy.remove(coupon.id);
        _refreshing = true;
        _future = _load().whenComplete(() {
          if (mounted) setState(() => _refreshing = false);
        });
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _rowBusy.remove(coupon.id));
      ScaffoldMessenger.of(context,
      ).showSnackBar(
        SnackBar(content: Text('状态切换失败：$error')));
    }
  }
}

/// 表单抽屉提交结果（created=true 时 id 为服务端真实返回）。
class _CouponSaveResult {
  const _CouponSaveResult({required this.created, this.id});

  final bool created;
  final int? id;
}

/// 新增/编辑券模板共用表单（抽屉形态，右侧滑出）。
/// 提交在抽屉内直接调用真实接口：成功关闭并返回结果；失败内联错误、表单数据保留。
class _CouponFormDrawer extends StatefulWidget {
  const _CouponFormDrawer({
    required this.repository,
    required this.client,
    this.initial,
  });

  final CouponRepository repository;
  final AdminApiClient client;
  final CouponTemplate? initial;

  @override
  State<_CouponFormDrawer> createState() => _CouponFormDrawerState();
}

class _CouponFormDrawerState extends State<_CouponFormDrawer> {
  late final TextEditingController _name;
  late final TextEditingController _discountValue;
  late final TextEditingController _minAmount;
  late final TextEditingController _stock;
  late final TextEditingController _startTime;
  late final TextEditingController _endTime;
  late final TextEditingController _validityTime;
  late final TextEditingController _description;
  String _couponType;
  String _applyDiningType;
  int _status;
  String? _error;
  var _submitting = false;

  /// 适用菜品可视化选择：已选菜品 id 集合（提交时自动序列化为 JSON）。
  Set<int> _selectedDishIds = <int>{};

  _CouponFormDrawerState()
    : _couponType = 'full_reduction',
      _applyDiningType = 'all',
      _status = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _discountValue = TextEditingController(
      text: initial == null ? '' : initial.discountValue.toStringAsFixed(2),
    );
    _minAmount = TextEditingController(
      text: initial == null ? '' : initial.minAmount.toStringAsFixed(2),
    );
    _stock = TextEditingController(
      text: initial == null ? '' : '${initial.stock}',
    );
    _startTime = TextEditingController(text: initial?.startTime ?? '');
    _endTime = TextEditingController(text: initial?.endTime ?? '');
    _validityTime = TextEditingController(
      text: initial?.validityTime == null ? '' : '${initial!.validityTime}',
    );
    _description = TextEditingController(text: initial?.description ?? '');
    _selectedDishIds = _parseDishIds(initial?.applyDishIds);
    if (initial != null) {
      _couponType = initial.couponType;
      _applyDiningType = initial.applyDiningType;
      _status = initial.status;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _discountValue.dispose();
    _minAmount.dispose();
    _stock.dispose();
    _startTime.dispose();
    _endTime.dispose();
    _validityTime.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写优惠券名称');
      return;
    }
    final discountValue = double.tryParse(_discountValue.text.trim()) ?? 0;
    final minAmount = double.tryParse(_minAmount.text.trim()) ?? 0;
    final stock = int.tryParse(_stock.text.trim());
    if (stock == null) {
      setState(() => _error = '库存需为整数（-1 表示无限）');
      return;
    }
    final validityTime = _validityTime.text.trim().isEmpty
        ? null
        : int.tryParse(_validityTime.text.trim());
    if (_validityTime.text.trim().isNotEmpty && validityTime == null) {
      setState(() => _error = '有效期小时数需为整数');
      return;
    }
    final initial = widget.initial;
    final template = CouponTemplate(
      id: initial?.id ?? 0,
      name: name,
      couponType: _couponType,
      status: initial == null ? 0 : _status,
      discountValue: discountValue,
      minAmount: minAmount,
      startTime: _startTime.text.trim().isEmpty
          ? null
          : _startTime.text.trim(),
      endTime: _endTime.text.trim().isEmpty ? null : _endTime.text.trim(),
      stock: stock,
      grantedCount: initial?.grantedCount ?? 0,
      description: _description.text.trim().isEmpty
          ? null
          : _description.text.trim(),
      validityTime: validityTime,
      applyDiningType: _applyDiningType,
      applyDishIds: _selectedDishIds.isEmpty
          ? '[]'
          : jsonEncode(_selectedDishIds.toList()..sort()),
    );
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (initial == null) {
        final id = await widget.repository.addCoupon(template);
        if (!mounted) return;
        Navigator.of(context).pop(_CouponSaveResult(created: true, id: id));
      } else {
        await widget.repository.updateCoupon(template);
        if (!mounted) return;
        Navigator.of(context,
        ).pop(
          _CouponSaveResult(created: false, id: initial.id));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '保存失败：$error';
      });
    }
  }

  Future<void> _openDishPicker() async {
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (context) => _DishPickerDialog(
        client: widget.client,
        initial: _selectedDishIds),
    );
    if (result != null && mounted) {
      setState(() => _selectedDishIds = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  isEdit ? '编辑优惠券' : '新增优惠券',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
                tooltip: '关闭',
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: AbsorbPointer(
            absorbing: _submitting,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                _formSectionTitle(context, '基本信息'),
                TextField(
                  key: const Key('coupon-form-name'),
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: '名称 *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  key: const Key('coupon-form-type'),
                  initialValue: _couponType,
                  decoration: const InputDecoration(
                    labelText: '类型',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'full_reduction',
                      child: Text('满减'),
                    ),
                    DropdownMenuItem(
                      value: 'discount',
                      child: Text('折扣')),
                    DropdownMenuItem(
                      value: 'direct_reduction',
                      child: Text('直减'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _couponType = value ?? 'full_reduction'),
                ),
                const SizedBox(height: 14),
                _formSectionTitle(context, '面值与门槛'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('coupon-form-discount'),
                        controller: _discountValue,
                        decoration: const InputDecoration(
                          labelText: '面值（元）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('coupon-form-min-amount'),
                        controller: _minAmount,
                        decoration: const InputDecoration(
                          labelText: '使用门槛（元）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _formSectionTitle(context, '适用与库存'),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        key: const Key('coupon-form-dining-type'),
                        initialValue: _applyDiningType,
                        decoration: const InputDecoration(
                          labelText: '适用就餐方式',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('全部')),
                          DropdownMenuItem(value: 'dine_in', child: Text('堂食'),
                            ),
                          DropdownMenuItem(value: 'take_out', child: Text('打包'),
                            ),
                        ],
                        onChanged: (value) => setState(
                          () => _applyDiningType = value ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('coupon-form-stock'),
                        controller: _stock,
                        decoration: const InputDecoration(
                          labelText: '库存（-1 无限）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // 适用菜品可视化选择（客户端自动转 JSON 提交；留空=不限制）。
                _DishPickerField(
                  selectedIds: _selectedDishIds,
                  onRemove: (id) => setState(() => _selectedDishIds.remove(id)),
                  onPick: _openDishPicker,
                ),
                const SizedBox(height: 14),
                _formSectionTitle(context, '有效期'),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('coupon-form-start'),
                        controller: _startTime,
                        decoration: const InputDecoration(
                          labelText: '开始时间（yyyy-MM-dd HH:mm:ss）',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        key: const Key('coupon-form-end'),
                        controller: _endTime,
                        decoration: const InputDecoration(
                          labelText: '结束时间',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  key: const Key('coupon-form-validity'),
                  controller: _validityTime,
                  decoration: const InputDecoration(
                    labelText: '领券后有效期（小时，可空）',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),
                _formSectionTitle(context, '说明与状态'),
                TextField(
                  key: const Key('coupon-form-description'),
                  controller: _description,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: '说明',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (isEdit) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    key: const Key('coupon-form-status'),
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: '状态',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('未启用')),
                      DropdownMenuItem(value: 1, child: Text('可用')),
                      DropdownMenuItem(value: 2, child: Text('已下架')),
                    ],
                    onChanged: (value) => setState(() => _status = value ?? 0),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  _InlineError(_error!),
                ],
              ],
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                key: const Key('coupon-form-submit'),
                onPressed: _submitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: context.cashier.ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(isEdit ? '保存' : '创建'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _formSectionTitle(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.cashier.inkSecondary,
      ),
    ),
  );
}

/// 券模板新增/编辑表单抽屉（表单字段 Key 与既有测试兼容；提交在抽屉内完成）。
Future<_CouponSaveResult?> showCouponFormDrawer(
  BuildContext context,
  CouponTemplate? initial, {
  required CouponRepository repository,
  required AdminApiClient client,
}) {
  return showGeneralDialog<_CouponSaveResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x590f172a),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.cashier.surface,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: _CouponFormDrawer(
            repository: repository,
            client: client,
            initial: initial,
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
  );
}

/// 详情抽屉（三态：骨架 → 真实详情 / 失败错误态 + 重试；不静默回退列表数据）。
class _CouponDetailDrawer extends StatefulWidget {
  const _CouponDetailDrawer({required this.repository, required this.couponId});

  final CouponRepository repository;
  final int couponId;

  @override
  State<_CouponDetailDrawer> createState() => _CouponDetailDrawerState();
}

class _CouponDetailDrawerState extends State<_CouponDetailDrawer> {
  CouponTemplate? _detail;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _detail = null;
      _error = null;
    });
    try {
      final detail = await widget.repository.loadCouponDetail(widget.couponId);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SettingsErrorState(
        message: '详情加载失败：$_error',
        onRetry: _load);
    }
    final detail = _detail;
    if (detail == null) {
      return const SettingsSkeletonLoader(rows: 4);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailRow(context, '名称', detail.name),
        _detailRow(
          context,
          '类型',
          _couponTypeLabels[detail.couponType] ?? detail.couponType,
        ),
        _detailRow(
          context,
          '状态',
          _couponStatusLabels[detail.status] ?? '${detail.status}',
        ),
        _detailRow(
          context,
          '面值',
          '¥${detail.discountValue.toStringAsFixed(2)}',
        ),
        _detailRow(context, '门槛', '¥${detail.minAmount.toStringAsFixed(2)}'),
        _detailRow(context, '库存', detail.stock == -1 ? '无限' : '${detail.stock}',
        ),
        _detailRow(context, '已发放', '${detail.grantedCount}'),
        _detailRow(
          context,
          '有效期',
          '${detail.startTime ?? '-'} ~ ${detail.endTime ?? '-'}',
        ),
        if (detail.validityTime != null)
          _detailRow(context, '券有效期', '${detail.validityTime} 小时'),
        _detailRow(
          context,
          '适用菜品',
          detail.applyDishIds == null || detail.applyDishIds!.trim().isEmpty
              ? '全部菜品'
              : detail.applyDishIds!,
        ),
        if (detail.description != null && detail.description!.isNotEmpty)
          _detailRow(context, '说明', detail.description!),
      ],
    );
  }
}

Widget _detailRow(BuildContext context, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 3),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 90,
        child: Text(
          label,
          style: TextStyle(color: context.cashier.inkMuted)),
      ),
      Expanded(child: Text(value)),
    ],
  ),
);

/// 适用菜品选择器字段：摘要 + 已选 chips（可移除）+ 「选择菜品」+ JSON 预览。
class _DishPickerField extends StatelessWidget {
  const _DishPickerField({
    required this.selectedIds,
    required this.onRemove,
    required this.onPick,
  });

  final Set<int> selectedIds;
  final ValueChanged<int> onRemove;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final ids = selectedIds.toList()..sort();
    final jsonPreview = ids.isEmpty
        ? '（空）不限制'
        : jsonEncode(ids);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '适用菜品（留空 = 不限制，客户端自动转 JSON）',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.cashier.inkSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: ids.isEmpty
                      ? context.cashier.subtle
                      : context.cashier.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: ids.isEmpty
                      ? Border.all(color: context.cashier.border)
                      : Border.all(color: context.cashier.success),
                ),
                child: Text(
                  ids.isEmpty ? '未选择 · 该券适用于全部菜品' : '已选 ${ids.length} 项',
                  style: TextStyle(
                    fontSize: 13,
                    color: ids.isEmpty
                        ? context.cashier.inkMuted
                        : context.cashier.success,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.menu_open_outlined, size: 16),
              label: const Text('选择菜品'),
            ),
          ],
        ),
        if (ids.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in ids)
                InputChip(
                  key: Key('coupon-form-dish-chip-$id'),
                  label: Text('#$id'),
                  onDeleted: () => onRemove(id),
                  deleteIcon: const Icon(Icons.close, size: 15),
                  backgroundColor: context.cashier.successBackground,
                  side: BorderSide.none,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.cashier.success,
                  ),
                ),
            ],
          ),
        ],
        const SizedBox(height: 4),
        Text(
          '提交 JSON：$jsonPreview',
          style: TextStyle(fontSize: 11, color: context.cashier.inkMuted),
        ),
      ],
    );
  }
}

/// 菜品选项（数据源 GET /dish/listAll，公开端点，无需 dish:manage）。
class _DishOption {
  const _DishOption({
    required this.id,
    required this.name,
    required this.category,
    this.price = '',
  });

  final int id;
  final String name;
  final String category;
  final String price;
}

Future<List<_DishOption>> _loadDishOptions(AdminApiClient client) async {
  final raw = await client.get(customerDishListAllEndpoint);
  final data = raw is Map<String, Object?>
      ? raw
      : (raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{});
  final categories = _namedList(data, const ['allDish', 'all_dish']);
  final options = <_DishOption>[];
  final seen = <int>{};
  for (final rawCategory in categories) {
    final category = rawCategory is Map
        ? rawCategory.cast<String, Object?>()
        : const <String, Object?>{};
    final categoryName =
        '${category['name'] ?? category['label'] ?? category['value'] ?? '其他'}'
            .trim();
    for (final rawDish
        in _namedList(category, const ['dishList', 'dish_list',
    ])) {
      if (rawDish is! Map) continue;
      final dish = rawDish.cast<String, Object?>();
      final id = int.tryParse('${dish['id'] ?? dish['dish_id'] ?? 0}') ?? 0;
      if (id <= 0 || !seen.add(id)) continue;
      final name = '${dish['name'] ?? dish['dish_name'] ?? ''}'.trim();
      final price =
          dish['unitprice'] ?? dish['unit_price'] ?? dish['price'];
      options.add(
        _DishOption(
          id: id,
          name: name.isEmpty ? '#$id' : name,
          category: categoryName.isEmpty ? '其他' : categoryName,
          price: price == null ? '' : '¥$price',
        ),
      );
    }
  }
  return options;
}

List<Object?> _namedList(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) return value;
    if (value is Map) {
      final nested = value.cast<String, Object?>();
      for (final inner in keys) {
        if (nested[inner] is List) return nested[inner]! as List;
      }
    }
  }
  return const [];
}

/// 菜品多选弹窗：加载（骨架/失败重试）→ 搜索 + 分类分组复选框 + 已选计数。
class _DishPickerDialog extends StatefulWidget {
  const _DishPickerDialog({required this.client, required this.initial});

  final AdminApiClient client;
  final Set<int> initial;

  @override
  State<_DishPickerDialog> createState() => _DishPickerDialogState();
}

class _DishPickerDialogState extends State<_DishPickerDialog> {
  late final Set<int> _selected = {...widget.initial};
  final _search = TextEditingController();
  List<_DishOption> _options = const [];
  var _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final options = await _loadDishOptions(widget.client);
      if (!mounted) return;
      setState(() {
        _options = options;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择适用菜品'),
      content: SizedBox(
        width: 520,
        child: _buildContent(context)),
      actions: [
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _selected.clear();
                    _search.clear();
                  }),
          child: const Text('清空'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('coupon-dish-picker-confirm'),
          onPressed: _loading ? null : () => Navigator.of(context).pop(_selected),
          style: FilledButton.styleFrom(
            backgroundColor: context.cashier.ink),
          child: const Text('确定'),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _InlineError('菜品加载失败：$_error'),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('重试'),
          ),
        ],
      );
    }
    final keyword = _search.text.trim().toLowerCase();
    final filtered = keyword.isEmpty
        ? _options
        : _options.where((o) => o.name.toLowerCase().contains(keyword)).toList();
    final grouped = <String, List<_DishOption>>{};
    for (final option in filtered) {
      grouped.putIfAbsent(option.category, () => []).add(option);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('coupon-dish-picker-search'),
          controller: _search,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            hintText: '搜索菜品名称…',
            prefixIcon: Icon(Icons.search, size: 18),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 360),
          child: grouped.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Text('未找到匹配菜品', style: TextStyle(fontSize: 13)),
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in grouped.entries) ...[
                      Container(
                        color: context.cashier.subtle,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 7,
                        ),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: context.cashier.inkSecondary,
                          ),
                        ),
                      ),
                      for (final option in entry.value)
                        CheckboxListTile(
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _selected.contains(option.id),
                          onChanged: (checked) => setState(() {
                            if (checked == true) {
                              _selected.add(option.id);
                            } else {
                              _selected.remove(option.id);
                            }
                          }),
                          title: Text(
                            option.name,
                            style: const TextStyle(fontSize: 13),
                          ),
                          secondary: option.price.isEmpty
                              ? null
                              : Text(
                                  option.price,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.cashier.inkMuted,
                                  ),
                                ),
                        ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Text(
          '已选 ${_selected.length} 项',
          key: const Key('coupon-dish-picker-count'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: context.cashier.inkSecondary,
          ),
        ),
      ],
    );
  }
}

/// 解析服务端返回的 apply_dish_ids JSON 字符串为菜品 id 集合。
Set<int> _parseDishIds(String? raw) {
  if (raw == null || raw.trim().isEmpty) return <int>{};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      final ids = <int>{
        for (final value in decoded)
          int.tryParse('$value') ?? 0,
      }..remove(0);
      return ids;
    }
  } catch (_) {}
  return <int>{};
}

/// 行内/按钮 16px 转圈（写操作提交中）。
Widget _busyIndicator(BuildContext context) => const SizedBox(
  width: 16,
  height: 16,
  child: CircularProgressIndicator(strokeWidth: 2),
);

/// 更新于 HH:mm:ss。
String _formatUpdatedTime(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  final s = time.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// 工具条刷新按钮（busy 时转圈 + 禁用）。
class _RefreshButton extends StatelessWidget {
  const _RefreshButton({super.key, required this.busy, required this.onPressed,
  });

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: busy ? null : onPressed,
    tooltip: '刷新',
    icon: busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.refresh, size: 20),
  );
}

/// 分区内统一的红底错误条（跨分区复用，替代散落红字）。
class _InlineError extends StatelessWidget {
  const _InlineError(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: context.cashier.dangerBackground,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      message,
      style: TextStyle(color: context.cashier.danger)),
  );
}

/// 数据表格统一表头（UI026-v3 锁定）。
Widget _tableHeader(BuildContext context, String label) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  child: Text(
    label,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: context.cashier.inkMuted,
    ),
  ),
);

/// 表格列宽：固定列 + 弹性列（有最小宽度与权重），
/// 容器更宽时按权重把多余空间分给弹性列，实现表格两端对齐；
/// 窄于最小宽度时保持固定布局并交给横向滚动兜底。
Map<int, TableColumnWidth> _tableColumns(
  double availableWidth, {
  required double minWidth,
  required List<(int, double)> fixed,
  required List<(int, double, double)> flex,
}) {
  final fixedWidth = fixed.fold(0.0, (sum, e) => sum + e.$2);
  final minFlexWidth = flex.fold(0.0, (sum, e) => sum + e.$2);
  final width = math.max(availableWidth, minWidth);
  final extra = math.max(0.0, width - fixedWidth - minFlexWidth);
  final totalWeight = flex.fold(0.0, (sum, e) => sum + e.$3);
  final map = <int, TableColumnWidth>{
    for (final (index, width) in fixed) index: FixedColumnWidth(width),
  };
  for (final (index, min, weight) in flex) {
    map[index] = FixedColumnWidth(min + extra * weight / totalWeight);
  }
  return map;
}

/// 右侧滑出抽屉容器（UI026-v3 锁定：宽 520、220ms 滑入、barrier 可点关闭）。
Future<T?> showCouponDrawer<T>({
  required BuildContext context,
  required String title,
  required Widget child,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color(0x590f172a),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: context.cashier.surface,
        borderRadius: const BorderRadius.horizontal(
          left: Radius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: 520,
          height: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                      tooltip: '关闭',
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) =>
        SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero,
          ).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
  );
}

class _RedeemCodesSection extends StatefulWidget {
  const _RedeemCodesSection({required this.repository, this.now});

  final CouponRepository repository;

  /// 可注入时钟（测试/截图用固定时间；缺省为实时）。
  final DateTime Function()? now;

  @override
  State<_RedeemCodesSection> createState() => _RedeemCodesSectionState();
}

class _RedeemCodesSectionState extends State<_RedeemCodesSection> {
  List<CouponTemplate> _coupons = const [];
  int? _couponId;
  int? _statusFilter;
  List<CouponRedeemCode> _codes = const [];
  final _selected = <int>{};
  var _busy = false;
  String? _error;
  int _totalCount = 0;
  DateTime? _lastUpdated;

  /// 鼠标悬停高亮的行 id（对齐原型 tbody tr:hover）。
  int? _hoverRowId;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final coupons = await widget.repository.loadCoupons();
      if (!mounted) return;
      setState(() => _coupons = coupons);
      if (coupons.isNotEmpty) {
        _couponId = coupons.first.id;
      }
      await _loadCodes();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _loadCodes() async {
    setState(() => _busy = true);
    try {
      final codes = await widget.repository.loadRedeemCodes(
        couponId: _couponId,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _codes = codes;
        _selected.clear();
        _busy = false;
        _error = null;
        _totalCount = codes.length;
        _lastUpdated = _now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _openCreateDialog() async {
    final couponId = _couponId;
    if (couponId == null) return;
    final created = await showDialog<int>(
      context: context,
      builder: (context) => _CreateRedeemCodesDialog(
        repository: widget.repository,
        couponId: couponId,
      ),
    );
    if (created == null || !mounted) return;
    showSettingsSaved(context, '已生成 $created 个兑换码');
    await _loadCodes();
  }

  void _copyCode(CouponRedeemCode code) {
    Clipboard.setData(ClipboardData(text: code.redeemCode));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('兑换码已复制')));
  }

  Future<void> _showQrcode(CouponRedeemCode code) async {    var verified = false;
    try {
      verified = await widget.repository.verifyRedeemCodeQrcode(
        code.redeemCode,
      );
    } catch (_) {
      verified = false;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('兑换码二维码'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QrImageView(
                data: code.redeemCode,
                version: QrVersions.auto,
                size: 220,
              ),
              const SizedBox(height: 10),
              Text(
                code.redeemCode,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                verified ? '服务端小程序码接口校验通过' : '本地二维码（服务端校验不可用）',
                style: TextStyle(
                  fontSize: 12,
                  color: verified
                      ? context.cashier.success
                      : context.cashier.inkMuted,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            key: const Key('coupon-redeem-code-copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code.redeemCode));
              ScaffoldMessenger.of(context,
              ).showSnackBar(
                const SnackBar(content: Text('兑换码已复制')));
            },
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('复制券码'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selected.isEmpty) return;
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '删除所选兑换码',
      message: '将删除 ${_selected.length} 个兑换码，删除后无法再核销。',
    );    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final deleted = await widget.repository.deleteRedeemCodes(
        _selected.toList()..sort(),
      );
      if (!mounted) return;
      showSettingsSaved(context, '已删除 $deleted 个兑换码');
      await _loadCodes();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 第一行：券模板 + 核销状态筛选 + 计数/更新时间/刷新。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '券模板',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.cashier.inkSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    DropdownButton<int?>(
                      key: const Key('coupon-redeem-code-filter'),
                      value: _couponId,
                      items: [
                        for (final coupon in _coupons)
                          DropdownMenuItem<int?>(
                            value: coupon.id,
                            child: Text(
                              coupon.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                                _couponId = value;
                                _loadCodes();
                              }),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _statusFilter == null,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                                _statusFilter = null;
                                _loadCodes();
                              }),
                    ),
                    for (final entry in _redeemStatusLabels.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _statusFilter == entry.key,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                  _statusFilter = entry.key;
                                  _loadCodes();
                                }),
                      ),
                  ],
                ),
              ),
              Text(
                '共 $_totalCount 条',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _lastUpdated == null ? '' : '更新于 ${_formatUpdatedTime(_lastUpdated!)}',
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
              const SizedBox(width: 4),
              _RefreshButton(
                key: const Key('coupon-redeem-code-refresh'),
                busy: _busy,
                onPressed: _loadCodes,
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 第二行：生成 / 全选（删除统一走底部批量操作条）。
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton.icon(
                  key: const Key('coupon-redeem-code-create'),
                  onPressed: _busy || _couponId == null
                      ? null
                      : _openCreateDialog,
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('生成兑换码'),
                ),
                TextButton.icon(
                  key: const Key('coupon-redeem-code-select-all'),
                  onPressed: _busy || _codes.isEmpty
                      ? null
                      : () => setState(() {
                            if (_selected.length == _codes.length) {
                              _selected.clear();
                            } else {
                              _selected
                                ..clear()
                                ..addAll(_codes.map((code) => code.id));
                            }
                          }),
                  icon: const Icon(
                    Icons.select_all_outlined,
                    size: 18),
                  label: Text(
                    _selected.isNotEmpty && _selected.length == _codes.length
                        ? '取消全选'
                        : '全选',
                  ),
                ),
              ],
            ),
          ),
          if (_busy && _codes.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InlineError(_error!),
            ),
          Expanded(
            child: _busy && _codes.isEmpty
                ? const SettingsSkeletonLoader(rows: 4)
                : _codes.isEmpty && _error == null
                ? const SettingsEmptyState(
                    title: '暂无兑换码',
                    description: '先在上方选择券模板，或在运营后台生成兑换码。',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const minTableWidth = 782.0;
                      final tableWidth = math.max(
                        constraints.maxWidth,
                        minTableWidth,
                      );
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Table(
                            columnWidths: _tableColumns(
                              constraints.maxWidth,
                              minWidth: minTableWidth,
                              fixed: const [
                                (0, 44),
                                (2, 100),
                                (4, 88)],
                              flex: const [
                                (1, 220, 1.0),
                                (3, 330, 1.3)],
                            ),
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(
                                  color: Color(0xfff5f5f5),
                                  border: Border(
                                    bottom:
                                        BorderSide(color: Color(0xffe5e7eb),
                                    ),
                                  ),
                                ),
                                children: [
                                  const SizedBox(width: 44),
                                  _tableHeader(context, '兑换码'),
                                  _tableHeader(context, '状态'),
                                  _tableHeader(context, '创建 / 核销信息'),
                                  _tableHeader(context, '二维码'),
                                ],
                              ),
                              for (var i = 0; i < _codes.length; i++)
                                _redeemCodeTableRow(
                                  context,
                                  _codes[i],
                                  zebra: i.isOdd,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          // 底部批量操作条（选中后出现）。
          if (_selected.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: context.cashier.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffe5e7eb)),
              ),
              child: Row(
                children: [
                  Text(
                    '已选 ${_selected.length} 项',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.cashier.inkSecondary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => setState(() => _selected.clear()),
                    child: const Text('取消选择'),
                  ),
                  TextButton.icon(
                    key: const Key('coupon-redeem-code-delete'),
                    onPressed: _selected.isEmpty || _busy
                        ? null
                        : _deleteSelected,
                    icon: _busy
                        ? _busyIndicator(context)
                        : const Icon(Icons.delete_outline, size: 16),
                    label: Text(
                      '删除所选',
                      style: TextStyle(color: context.cashier.danger),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  TableRow _redeemCodeTableRow(
    BuildContext context,
    CouponRedeemCode code, {
    bool zebra = false,
  }) {
    final hovered = _hoverRowId == code.id;
    Widget cell(Widget child) => MouseRegion(
      onEnter: (_) => setState(() => _hoverRowId = code.id),
      onExit: (_) => setState(() => _hoverRowId = null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: child,
      ),
    );
    return TableRow(
      decoration: BoxDecoration(
        color: hovered
            ? const Color(0xfff5f5f5)
            : (zebra ? const Color(0xfffafafa) : null),
        border: const Border(
          bottom: BorderSide(color: Color(0xfff1f1f1))),
      ),
      children: [
        cell(Checkbox(
          key: Key('coupon-redeem-code-${code.id}'),
          value: _selected.contains(code.id),
          onChanged: _busy
              ? null
              : (checked) => setState(() {
                    if (checked == true) {
                      _selected.add(code.id);
                    } else {
                      _selected.remove(code.id);
                    }
                  }),
        ),
        ),
        cell(Row(
          children: [
            Expanded(
              child: Text(
                code.redeemCode,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              key: Key('coupon-redeem-code-copy-${code.id}'),
              tooltip: '复制券码',
              visualDensity: VisualDensity.compact,
              onPressed: _busy ? null : () => _copyCode(code),
              icon: const Icon(Icons.copy_outlined, size: 15),
            ),
          ],
        ),
        ),
        cell(FittedBox(
          fit: BoxFit.scaleDown,
          child: code.status == 1
              ? const SettingsStatusBadge(
                  label: '已核销',
                  type: StatusBadgeType.neutral,
                )
              : const SettingsStatusBadge(
                  label: '未核销',
                  type: StatusBadgeType.success,
                ),
        ),
        ),
        cell(Text(
          code.status == 1
              ? '核销于 ${code.usedTime ?? '-'}'
                      '${code.usedOpenid != null && code.usedOpenid!.isNotEmpty ? ' · ${code.usedOpenid}' : ''}'
              : '创建于 ${code.createTime ?? '-'}',
          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
        ),
        ),
        cell(IconButton(
          key: Key('coupon-redeem-code-qrcode-${code.id}'),
          tooltip: '生成二维码',
          onPressed: _busy ? null : () => _showQrcode(code),
          icon: const Icon(Icons.qr_code_2_outlined),
        ),
        ),
      ],
    );
  }
}

class _CreateRedeemCodesDialog extends StatefulWidget {
  const _CreateRedeemCodesDialog({
    required this.repository,
    required this.couponId,
  });

  final CouponRepository repository;
  final int couponId;

  @override
  State<_CreateRedeemCodesDialog> createState() =>
      _CreateRedeemCodesDialogState();
}

class _CreateRedeemCodesDialogState extends State<_CreateRedeemCodesDialog> {
  final _count = TextEditingController(text: '10');
  String? _error;
  var _submitting = false;

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final count = int.tryParse(_count.text.trim());
    if (count == null || count < 1 || count > 500) {
      setState(() => _error = '数量需为 1~500 的整数');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final created = await widget.repository.createRedeemCodes(
        couponId: widget.couponId,
        count: count,
      );
      if (!mounted) return;
      Navigator.of(context).pop(created.length);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '生成失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('生成兑换码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('为当前券模板批量生成兑换码，一次最多 500 个。'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('coupon-redeem-code-count'),
            controller: _count,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: '数量（1~500）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _InlineError(_error!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('coupon-redeem-code-create-submit'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: context.cashier.ink),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('生成'),
        ),
      ],
    );
  }
}

class _GrantSection extends StatefulWidget {
  const _GrantSection({required this.repository});

  final CouponRepository repository;

  @override
  State<_GrantSection> createState() => _GrantSectionState();
}

class _GrantSectionState extends State<_GrantSection> {
  List<CouponTemplate> _coupons = const [];
  int? _couponId;
  final _path = TextEditingController();
  List<int>? _pendingBytes;
  var _busy = false;
  String? _error;
  CouponGrantExcelResult? _result;
  String? _fileName;
  String? _fileSizeKb;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  Future<void> _loadCoupons() async {
    try {
      final coupons = await widget.repository.loadCoupons(status: 1);
      if (!mounted) return;
      setState(() {
        _coupons = coupons;
        if (coupons.isNotEmpty && _couponId == null) {
          _couponId = coupons.first.id;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'xls'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      setState(() {
        _error = null;
        _result = null;
        _fileName = file.name;
        _fileSizeKb = file.size > 0
            ? (file.size / 1024).toStringAsFixed(1)
            : null;
        if (file.bytes != null && file.bytes!.isNotEmpty) {
          _pendingBytes = file.bytes;
          _path.text = file.name;
        } else if (file.path != null) {
          _pendingBytes = null;
          _path.text = file.path!;
        } else {
          _error = '无法读取所选 Excel 文件，请重试';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _grant() async {
    final couponId = _couponId;
    final path = _path.text.trim();
    if (couponId == null) {
      setState(() => _error = '请先选择优惠券模板');
      return;
    }
    if (path.isEmpty) {
      setState(() => _error = '请选择或输入 Excel 文件路径');
      return;
    }
    List<int> bytes;
    final pending = _pendingBytes;
    if (pending != null) {
      bytes = pending;
    } else {
      try {
        bytes = File(path).readAsBytesSync();
      } catch (error) {
        setState(() => _error = '读取文件失败：$error');
        return;
      }
    }
    if (bytes.isEmpty) {
      setState(() => _error = '文件为空');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.repository.grantByExcel(
        couponId: couponId,
        bytes: bytes,
        fileName: path.split(RegExp(r'[\\/]')).last,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _openGrantDialog() async {
    final couponId = _couponId;
    if (couponId == null) return;
    final granted = await showDialog<bool>(
      context: context,
      builder: (context) => _GrantCouponDialog(
        repository: widget.repository,
        couponId: couponId),
    );
    if (granted != true || !mounted) return;
    showSettingsSaved(context, '定向发券成功');
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: SettingsPanel(
        title: 'Excel 批量发券',
        trailing: TextButton.icon(
          key: const Key('coupon-grant-direct'),
          onPressed: _busy ? null : _openGrantDialog,
          icon: const Icon(Icons.person_add_alt_outlined, size: 18),
          label: const Text('定向发券（单用户）'),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _stepHeader(context, 1, '选择优惠券'),
            DropdownButtonFormField<int?>(
              key: const Key('coupon-grant-coupon'),
              initialValue: _couponId,
              decoration: const InputDecoration(
                labelText: '优惠券模板（可用）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final coupon in _coupons)
                  DropdownMenuItem<int?>(
                    value: coupon.id,
                    child: Text(
                      '${coupon.name}（库存 ${coupon.stock == -1 ? '无限' : coupon.stock}）',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _couponId = value),
            ),
            const SizedBox(height: 18),
            _stepHeader(context, 2, '选择 Excel 文件'),
            const Text(
              '第一张工作表需含 openid 表头，服务端自动去重后发券。',
              style: TextStyle(fontSize: 13, color: Color(0xff667085)),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('coupon-grant-excel-path'),
                    controller: _path,
                    enabled: !_busy,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Excel 文件（.xlsx/.xls）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                    key: const Key('coupon-grant-excel-pick'),
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('选择文件'),
                  ),
                ),
              ],
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.cashier.subtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: context.cashier.inkSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_fileName${_fileSizeKb != null ? ' · $_fileSizeKb KB' : ''}',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SettingsStatusBadge(
                      label: '格式正确',
                      type: StatusBadgeType.success,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            _stepHeader(context, 3, '上传并发券'),
            SettingsPrimaryButton(
              key: const Key('coupon-grant-submit'),
              label: '上传并发券',
              loading: _busy,
              onPressed: _grant,
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _InlineError(_error!),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.cashier.successBackground,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '发券完成：成功 ${_result!.grantedCount} 张',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _grantMetric(
                          context,
                          '成功发放',
                          '${_result!.grantedCount}',
                        ),
                        _grantMetric(
                          context,
                          '读取行数',
                          '${_result!.readCount}'),
                        _grantMetric(
                          context,
                          '去重行数',
                          '${_result!.duplicateCount}',
                        ),
                        _grantMetric(
                          context,
                          '目标用户',
                          '${_result!.targetOpenidCount}',
                        ),
                      ],
                    ),
                    if (_result!.fileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '文件 ${_result!.fileName}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cashier.inkSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stepHeader(BuildContext context, int step, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: context.cashier.ink,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              '$step',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: context.cashier.inkSecondary,
          ),
        ),
      ],
    ),
  );

  Widget _grantMetric(BuildContext context, String label, String value) =>
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xff166534),
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: context.cashier.inkSecondary,
              ),
            ),
          ],
        ),
      );
}

class _GrantCouponDialog extends StatefulWidget {
  const _GrantCouponDialog({required this.repository, required this.couponId});

  final CouponRepository repository;
  final int couponId;

  @override
  State<_GrantCouponDialog> createState() => _GrantCouponDialogState();
}

class _GrantCouponDialogState extends State<_GrantCouponDialog> {
  final _openid = TextEditingController();
  final _phone = TextEditingController();
  String? _error;
  var _submitting = false;

  @override
  void dispose() {
    _openid.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final openid = _openid.text.trim();
    final phone = _phone.text.trim();
    if (openid.isEmpty && phone.isEmpty) {
      setState(() => _error = '请填写 openid 或手机号（二选一）');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.repository.grantCoupon(
        couponId: widget.couponId,
        openid: openid,
        phone: phone,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = '发券失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('定向发券'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('向单个用户发券，openid 与手机号二选一（手机号须已绑定用户）。'),
          const SizedBox(height: 12),
          TextField(
            key: const Key('coupon-grant-direct-openid'),
            controller: _openid,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: 'openid',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            key: const Key('coupon-grant-direct-phone'),
            controller: _phone,
            enabled: !_submitting,
            decoration: const InputDecoration(
              labelText: '手机号',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            _InlineError(_error!),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('coupon-grant-direct-submit'),
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(backgroundColor: context.cashier.ink),
          child: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('发券'),
        ),
      ],
    );
  }
}

class _UserCouponsSection extends StatefulWidget {
  const _UserCouponsSection({required this.repository, this.now});

  final CouponRepository repository;

  /// 可注入时钟（测试/截图用固定时间；缺省为实时）。
  final DateTime Function()? now;

  @override
  State<_UserCouponsSection> createState() => _UserCouponsSectionState();
}

class _UserCouponsSectionState extends State<_UserCouponsSection> {
  List<CouponTemplate> _coupons = const [];
  int? _couponId;
  int? _statusFilter;
  List<UserCoupon> _couponsRows = const [];
  var _busy = false;
  String? _error;
  int _totalCount = 0;
  DateTime? _lastUpdated;
  final _rowBusy = <int>{};

  /// 鼠标悬停高亮的行 id（对齐原型 tbody tr:hover）。
  int? _hoverRowId;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final coupons = await widget.repository.loadCoupons();
      if (!mounted) return;
      setState(() => _coupons = coupons);
      if (coupons.isNotEmpty) {
        _couponId = coupons.first.id;
      }
      await _loadRows();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _loadRows() async {
    setState(() => _busy = true);
    try {
      final rows = await widget.repository.loadUserCoupons(
        couponId: _couponId,
        status: _statusFilter,
      );
      if (!mounted) return;
      setState(() {
        _couponsRows = rows;
        _busy = false;
        _error = null;
        _totalCount = rows.length;
        _lastUpdated = _now();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$error';
      });
    }
  }

  Future<void> _voidRow(UserCoupon row) async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '作废用户券',
      message: '作废 #${row.id} 用户券（仅未使用券可作废）？',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rowBusy.add(row.id));
    try {
      await widget.repository.voidUserCoupon(row.id);
      if (!mounted) return;
      setState(() => _rowBusy.remove(row.id));
      showSettingsSaved(context, '用户券已作废');
      await _loadRows();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rowBusy.remove(row.id);
        _error = '$error';
      });
    }
  }

  Future<void> _unbindRow(UserCoupon row) async {
    final confirmed = await showSettingsConfirmDialog(
      context: context,
      title: '解除订单占用',
      message: '解除 #${row.id} 用户券与订单号占用（后台纠错用）？',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _rowBusy.add(row.id));
    try {
      await widget.repository.unbindUserCoupon(row.id);
      if (!mounted) return;
      setState(() => _rowBusy.remove(row.id));
      showSettingsSaved(context, '已解除订单占用');
      await _loadRows();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _rowBusy.remove(row.id);
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsPagePadding(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 工具条：券模板 + 状态筛选 + 计数/更新时间/刷新。
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '券模板',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.cashier.inkSecondary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    DropdownButton<int?>(
                      key: const Key('coupon-user-coupon-filter'),
                      value: _couponId,
                      items: [
                        for (final coupon in _coupons)
                          DropdownMenuItem<int?>(
                            value: coupon.id,
                            child: Text(
                              coupon.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) => setState(() {
                                _couponId = value;
                                _loadRows();
                              }),
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('全部'),
                      selected: _statusFilter == null,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                                _statusFilter = null;
                                _loadRows();
                              }),
                    ),
                    for (final entry in _userCouponStatusLabels.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _statusFilter == entry.key,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() {
                                  _statusFilter = entry.key;
                                  _loadRows();
                                }),
                      ),
                  ],
                ),
              ),
              Text(
                '共 $_totalCount 条',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _lastUpdated == null ? '' : '更新于 ${_formatUpdatedTime(_lastUpdated!)}',
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
              const SizedBox(width: 4),
              _RefreshButton(
                key: const Key('coupon-user-coupon-refresh'),
                busy: _busy,
                onPressed: _loadRows,
              ),
            ],
          ),
          if (_busy && _couponsRows.isNotEmpty) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _InlineError(_error!),
            ),
          Expanded(
            child: _busy && _couponsRows.isEmpty
                ? const SettingsSkeletonLoader(rows: 4)
                : _couponsRows.isEmpty && _error == null
                ? const SettingsEmptyState(
                    title: '暂无用户券',
                    description: '调整筛选条件，或先在批量发券/运营后台发券。',
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      const minTableWidth = 1080.0;
                      final tableWidth = math.max(
                        constraints.maxWidth,
                        minTableWidth,
                      );
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Table(
                            columnWidths: _tableColumns(
                              constraints.maxWidth,
                              minWidth: minTableWidth,
                              fixed: const [
                                (4, 100),
                                (5, 260)],
                              flex: const [
                                (0, 180, 1.25),
                                (1, 220, 1.4),
                                (2, 150, 1.0),
                                (3, 170, 1.0),
                              ],
                            ),
                            defaultVerticalAlignment:
                                TableCellVerticalAlignment.middle,
                            children: [
                              TableRow(
                                decoration: const BoxDecoration(
                                  color: Color(0xfff5f5f5),
                                  border: Border(
                                    bottom:
                                        BorderSide(color: Color(0xffe5e7eb),
                                    ),
                                  ),
                                ),
                                children: [
                                  _tableHeader(context, '券名'),
                                  _tableHeader(context, '用户 openid'),
                                  _tableHeader(context, '关联订单'),
                                  _tableHeader(context, '领取时间'),
                                  _tableHeader(context, '状态'),
                                  _tableHeader(context, '操作'),
                                ],
                              ),
                              for (var i = 0; i < _couponsRows.length; i++)
                                _userCouponTableRow(
                                  context,
                                  _couponsRows[i],
                                  zebra: i.isOdd,
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
    );
  }

  TableRow _userCouponTableRow(
    BuildContext context,
    UserCoupon row, {
    bool zebra = false,
  }) {
    final statusLabel = _userCouponStatusLabels[row.status] ?? '未知';
    final statusType = switch (row.status) {
      1 => StatusBadgeType.info,
      2 => StatusBadgeType.neutral,
      _ => StatusBadgeType.success,
    };
    final hovered = _hoverRowId == row.id;
    Widget cell(Widget child) => MouseRegion(
      onEnter: (_) => setState(() => _hoverRowId = row.id),
      onExit: (_) => setState(() => _hoverRowId = null),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: child,
      ),
    );
    return TableRow(
      decoration: BoxDecoration(
        color: hovered
            ? const Color(0xfff5f5f5)
            : (zebra ? const Color(0xfffafafa) : null),
        border: const Border(
          bottom: BorderSide(color: Color(0xfff1f1f1))),
      ),
      children: [
        cell(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.couponName ?? '券 #${row.id}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                ),
            ),
            const SizedBox(height: 2),
            Text(
              '#${row.id}',
              style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
            ),
          ],
        ),
        ),
        cell(Text(
          row.openid ?? '-',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          overflow: TextOverflow.ellipsis,
        ),
        ),
        cell(Text(
          row.orderNo != null && row.orderNo!.isNotEmpty ? row.orderNo! : '-',
          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
        ),
        ),
        cell(Text(
          row.getTime ?? '-',
          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
        ),
        ),
        cell(FittedBox(
          fit: BoxFit.scaleDown,
          child: SettingsStatusBadge(label: statusLabel, type: statusType),
        ),
        ),
        cell(row.status == 0
            ? Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  TextButton.icon(
                    key: Key('coupon-user-coupon-void-${row.id}'),
                    onPressed: _busy || _rowBusy.contains(row.id)
                        ? null
                        : () => _voidRow(row),
                    icon: _rowBusy.contains(row.id)
                        ? _busyIndicator(context)
                        : Icon(
                            Icons.block_outlined,
                            size: 15,
                            color: context.cashier.danger,
                          ),
                    label: Text(
                      '作废',
                      style: TextStyle(color: context.cashier.danger),
                    ),
                  ),
                  TextButton.icon(
                    key: Key('coupon-user-coupon-unbind-${row.id}'),
                    onPressed: _busy || _rowBusy.contains(row.id)
                        ? null
                        : () => _unbindRow(row),
                    icon: _rowBusy.contains(row.id)
                        ? _busyIndicator(context)
                        : const Icon(Icons.link_off_outlined, size: 15),
                    label: const Text('解除占用'),
                  ),
                ],
              )
            : const Text('—'),
        ),
      ],
    );
  }
}
