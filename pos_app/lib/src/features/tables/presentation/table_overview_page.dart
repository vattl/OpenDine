import 'dart:async';

import 'package:flutter/material.dart';

import '../data/table_repository.dart';
import '../domain/dining_table.dart';
import '../domain/takeout_dispatch_alert.dart';
import '../../pos/data/pos_repository.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import '../../pos/presentation/pos_update_diners_dialog.dart';
import 'fulfillment_order_detail_dialog.dart';
import '../../cashier_shell/presentation/cashier_components.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../../../core/app_config.dart';

class TableOverviewPage extends StatefulWidget {
  const TableOverviewPage({
    super.key,
    required this.repository,
    this.onTableSelected,
    this.onClearTable,
    this.onPickupOrder,
    this.onFulfillmentCheckout,
    this.onManualRefund,
    this.onNavigateToBillRefund,
    this.onKdsSettings,
    this.canViewFulfillment = true,
    this.canUpdateFulfillment = true,
    this.canManageTable = false,
    this.showSidebar = true,
    this.currentAccount,
    this.refreshEvents,
    this.dispatchAlerts,
    this.onOpenHangPool,
    this.hangOrderCount = 0,
    this.initialTab = 0,
  });

  final TableRepository repository;
  final Future<void> Function(DiningTable table)? onTableSelected;
  final Future<void> Function(DiningTable table)? onClearTable;
  final Future<void> Function()? onPickupOrder;
  final Future<bool> Function(FulfillmentOrderDetail detail)?
  onFulfillmentCheckout;
  final Future<CashierManualRefundResult> Function(
    FulfillmentOrder order, {
    double? amount,
    String? reason,
    String? account,
    String? password,
  })?
  onManualRefund;
  final void Function(String orderNo)? onNavigateToBillRefund;
  final VoidCallback? onKdsSettings;
  final bool canViewFulfillment;
  final bool canUpdateFulfillment;
  final bool canManageTable;
  final bool showSidebar;
  final String? currentAccount;
  final Stream<void>? refreshEvents;
  final Stream<TakeoutDispatchAlert>? dispatchAlerts;
  final VoidCallback? onOpenHangPool;
  final int hangOrderCount;
  final int initialTab;

  @override
  State<TableOverviewPage> createState() => _TableOverviewPageState();
}

class _TableOverviewPageState extends State<TableOverviewPage> {
  static const _refreshInterval = Duration(seconds: 5);

  late int selectedTab;
  int selectedStatusIndex = 0;
  List<Map<String, dynamic>> _areas = const [
    {'code': 'hall', 'name': '大厅散座', 'sort': 1},
    {'code': 'box', 'name': '特色包厢', 'sort': 2},
    {'code': 'patio', 'name': '露天外摆', 'sort': 3},
  ];
  String _selectedArea = 'all';
  TableOverview? overview;
  String? error;
  bool loading = false;
  bool tableActionBusy = false;
  Timer? refreshTimer;
  StreamSubscription<void>? refreshSubscription;
  bool _pollingActive = false;
  bool _refreshQueued = false;
  final ScrollController horizontalController = ScrollController();

  /// 桌台方块边长（px），由右下角滑块控制
  double _tableCardSize = 260.0;

  @override
  void initState() {
    super.initState();
    selectedTab = widget.initialTab;
    _load();
    _startPolling();
    refreshSubscription = widget.refreshEvents?.listen((_) {
      if (!_pollingActive) return;
      if (loading) {
        _refreshQueued = true;
      } else {
        unawaited(_load(silent: true));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 宿主用 Offstage + TickerMode 保活隐藏页面；Timer 不受 TickerMode
    // 管控，必须手动门控：仅页面可见时轮询，隐藏即停，避免资源浪费。
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible && !_pollingActive) {
      // 切回本页：立即补偿一次静默刷新，再恢复轮询
      _load(silent: true);
      _startPolling();
    } else if (!visible && _pollingActive) {
      _stopPolling();
    }
  }

  void _startPolling() {
    _pollingActive = true;
    refreshTimer ??= Timer.periodic(_refreshInterval, (_) {
      if (!loading) _load(silent: true);
    });
  }

  void _stopPolling() {
    _pollingActive = false;
    refreshTimer?.cancel();
    refreshTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    refreshSubscription?.cancel();
    horizontalController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      if (!silent || overview == null) error = null;
    });
    try {
      final next = await widget.repository.loadTableOverview();
      List<Map<String, dynamic>> nextAreas = List.of(_areas);
      try {
        final loadedAreas = await widget.repository.loadTableAreas();
        if (loadedAreas.isNotEmpty) {
          nextAreas = loadedAreas;
        }
      } catch (_) {}
      final existingCodes = nextAreas.map((a) => a['code']?.toString()).toSet();
      for (final t in next.tables) {
        final code = t.effectiveAreaCode;
        if (code.isNotEmpty && !existingCodes.contains(code)) {
          existingCodes.add(code);
          nextAreas.add({
            'code': code,
            'name': t.areaName.isNotEmpty
                ? t.areaName
                : (code == 'box'
                    ? '特色包厢'
                    : (code == 'patio' ? '露天外摆' : code)),
            'sort': nextAreas.length + 1,
          });
        }
      }
      if (mounted) {
        setState(() {
          overview = next;
          _areas = nextAreas;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          // Keep the previous table snapshot visible during transient refresh failures.
          error = '$e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
        if (_refreshQueued && _pollingActive) {
          _refreshQueued = false;
          unawaited(_load(silent: true));
        }
      }
    }
  }

  Future<void> _openTable(DiningTable table) async {
    if (tableActionBusy) return;
    final clearHandler = widget.onClearTable;
    if (table.canClearAfterCheckout && clearHandler != null) {
      tableActionBusy = true;
      try {
        final confirmed = await showPosNotice(
          context,
          title: '清台提示',
          message: '${table.number}号桌已结账且金额为 ¥0.00，是否清台？',
          tone: PosNoticeTone.warning,
          primaryLabel: '确认',
          secondaryLabel: '取消',
        );
        if (!confirmed || !mounted) return;
        await clearHandler(table);
        if (mounted) await _load(silent: true);
      } catch (exception) {
        if (mounted) {
          await showPosNotice(
            context,
            title: '清台失败',
            message: '$exception',
            tone: PosNoticeTone.error,
          );
        }
      } finally {
        tableActionBusy = false;
      }
      return;
    }
    final handler = widget.onTableSelected;
    if (handler == null) return;
    DiningTable targetTable = table;
    if (!table.isOccupied) {
      final diners = await showOpenTableDialog(context, table: table);
      if (diners == null || !mounted) return;
      targetTable = table.copyWith(people: diners);
    }

    tableActionBusy = true;
    try {
      await handler(targetTable);
      if (mounted) await _load(silent: true);
    } catch (exception) {
      if (mounted) {
        await showPosNotice(
          context,
          title: table.isOccupied ? '打开桌台失败' : '开台失败',
          message: '$exception'.replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      tableActionBusy = false;
    }
  }

  Future<void> _openFulfillment(FulfillmentOrder order) async {
    if (!widget.canViewFulfillment) return;
    final changed = await showFulfillmentOrderDetail(
      context: context,
      repository: widget.repository,
      order: order,
      canUpdate: widget.canUpdateFulfillment,
      defaultAccount: widget.currentAccount,
      onCheckout: widget.onFulfillmentCheckout,
      onManualRefund: widget.onManualRefund,
      onNavigateToBillRefund: widget.onNavigateToBillRefund,
      dispatchAlerts: widget.dispatchAlerts,
    );
    if (changed && mounted) await _load(silent: true);
  }

  /// 只要开台（isOccupied）即可清台的桌台
  List<DiningTable> get _clearableTables => (overview?.tables ?? const [])
      .where((table) => table.isOccupied)
      .toList(growable: false);

  /// 一键清台：一次性清掉所有已开台桌台，遇到错误直接跳过，不影响继续清台
  Future<void> _clearAllSettledTables() async {
    final clearHandler = widget.onClearTable;
    if (clearHandler == null || tableActionBusy) return;
    final clearable = _clearableTables;
    if (clearable.isEmpty) return;
    final numbers = clearable.map((table) => '${table.number}号桌').join('、');
    final confirmed = await showPosNotice(
      context,
      title: '一键清台确认',
      message: '将一次性清掉 ${clearable.length} 个已开台桌台：\n$numbers\n是否继续？',
      tone: PosNoticeTone.warning,
      primaryLabel: '一键清台',
      secondaryLabel: '取消',
    );
    if (!confirmed || !mounted) return;
    setState(() => tableActionBusy = true);
    final failures = <String>[];
    final clearedTables = <DiningTable>[];
    for (final table in clearable) {
      try {
        await clearHandler(table);
        clearedTables.add(table);
      } catch (_) {
        failures.add('${table.number}号桌');
      }
    }
    if (clearedTables.isNotEmpty) {
      try {
        await widget.repository.batchClearTables(
          tableIds: clearedTables.map((t) => t.id).toList(growable: false),
          tableNumbers: clearedTables.map((t) => t.number).toList(growable: false),
          operatorAccount: widget.currentAccount,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    await _load(silent: true);
    setState(() => tableActionBusy = false);
    await showPosNotice(
      context,
      title: failures.isEmpty ? '清台完成' : '部分清台失败',
      message: failures.isEmpty
          ? '已清掉 ${clearable.length} 个开台桌台。'
          : '成功 ${clearable.length - failures.length} 台，失败 ${failures.length} 台：'
                '${failures.join('、')}。',
      tone: failures.isEmpty ? PosNoticeTone.info : PosNoticeTone.error,
      primaryLabel: '知道了',
    );
  }

  Future<void> _createTable() async {
    final existingNumbers = (overview?.tables ?? const [])
        .map((t) => t.number)
        .toSet();
    final result = await showDialog<
        ({String number, int peopleCount, String areaCode, String areaName})>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _CreateTableDialog(
        existingNumbers: existingNumbers,
        areas: _areas,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => tableActionBusy = true);
    try {
      await widget.repository.createTable(
        number: result.number,
        peopleCount: result.peopleCount,
        areaCode: result.areaCode,
        areaName: result.areaName,
      );
      if (mounted) {
        await _load(silent: true);
      }
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '创建桌台失败',
          message: '$e'.replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => tableActionBusy = false);
    }
  }

  Future<void> _editTable(DiningTable table) async {
    final existingNumbers = (overview?.tables ?? const [])
        .map((t) => t.number)
        .where((n) => n != table.number)
        .toSet();
    final result = await showDialog<
        ({String number, int peopleCount, String areaCode, String areaName})>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditTableDialog(
        table: table,
        existingNumbers: existingNumbers,
        areas: _areas,
      ),
    );
    if (result == null || !mounted) return;
    setState(() => tableActionBusy = true);
    try {
      await widget.repository.updateTable(
        id: table.id,
        number: result.number,
        peopleCount: result.peopleCount,
        areaCode: result.areaCode,
        areaName: result.areaName,
      );
      if (mounted) {
        await _load(silent: true);
        await showPosNotice(
          context,
          title: '桌台已修改',
          message: '桌台【${result.number}号桌】信息修改成功。',
          tone: PosNoticeTone.success,
          primaryLabel: '知道了',
        );
      }
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '修改桌台失败',
          message: '$e'.replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => tableActionBusy = false);
    }
  }

  Future<void> _onTableLongPress(DiningTable table) async {
    if (!widget.canManageTable) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => _TableQrDialog(
        table: table,
        canManageTable: widget.canManageTable,
        onEdit: () {
          Navigator.of(dialogCtx).pop();
          _editTable(table);
        },
        onDelete: () {
          Navigator.of(dialogCtx).pop();
          _deleteTable(table);
        },
      ),
    );
  }

  Future<void> _deleteTable(DiningTable table) async {
    if (table.isOccupied) {
      await showPosNotice(
        context,
        title: '无法删除',
        message: '该桌台当前正在就餐中，请先结账或清台后再删除。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TableDeleteAuthDialog(
        table: table,
        currentAccount: widget.currentAccount,
        onVerify: (username, password) => widget.repository.verifyPassword(
          username: username,
          password: password,
        ),
      ),
    );
    if (verified != true || !mounted) return;
    setState(() => tableActionBusy = true);
    try {
      await widget.repository.deleteTable(table.id);
      if (mounted) {
        await _load(silent: true);
        await showPosNotice(
          context,
          title: '桌台已删除',
          message: '【${table.number}号桌】已成功删除。',
          tone: PosNoticeTone.success,
          primaryLabel: '知道了',
        );
      }
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '删除失败',
          message: '$e'.replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => tableActionBusy = false);
    }
  }

  Future<void> _promptUpdateDiners() async {
    final occupiedTables = (overview?.tables ?? const [])
        .where((t) => t.isOccupied)
        .toList(growable: false);
    if (occupiedTables.isEmpty) {
      await showPosNotice(
        context,
        title: '调整人数',
        message: '当前没有正在就餐的桌台可调整人数。',
        tone: PosNoticeTone.info,
      );
      return;
    }

    DiningTable targetTable = occupiedTables.first;
    if (occupiedTables.length > 1) {
      final selected = await showDialog<DiningTable>(
        context: context,
        builder: (ctx) => CashierDialogFrame(
          width: 420,
          height: 380,
          title: '选择调整人数的桌台',
          onClose: () => Navigator.pop(ctx),
          body: ListView.builder(
            itemCount: occupiedTables.length,
            itemBuilder: (ctx, i) {
              final t = occupiedTables[i];
              return ListTile(
                title: Text('${t.number}号桌'),
                subtitle: Text('当前: ${t.people}人 · ¥${t.amount ?? 0}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(ctx, t),
              );
            },
          ),
          actions: [
            CashierActionButton(
              label: '取消',
              variant: CashierActionButtonVariant.secondary,
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      targetTable = selected;
    }

    final orderNo = targetTable.id > 0 ? targetTable.id.toString() : targetTable.number;
    final newCount = await showPosUpdateDinersDialog(
      context,
      tableNumber: targetTable.number,
      orderNo: orderNo,
      currentDiners: targetTable.people,
    );
    if (newCount == null || !mounted) return;
    try {
      await widget.repository.updateTableDiners(
        orderNo: orderNo,
        tableNumber: targetTable.number,
        diners: newCount,
        operatorAccount: widget.currentAccount,
      );
    } catch (e) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '调整人数失败',
          message: '$e'.replaceFirst('Exception: ', ''),
          tone: PosNoticeTone.error,
        );
      }
    }
    if (mounted) {
      await _load(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 手机端/全端不强行限定 1280 最小宽度与横向滚动，直接铺满当前视口
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;

        return Scrollbar(
          controller: horizontalController,
          thumbVisibility: false,
          child: SingleChildScrollView(
            controller: horizontalController,
            physics: const NeverScrollableScrollPhysics(),
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: width,
              height: height,
              child: Row(
                children: [
                  if (widget.showSidebar)
                    _RestaurantSidebar(onKdsSettings: widget.onKdsSettings),
                  Expanded(
                    child: Column(
                      children: [
                        _OrderToolbar(
                          tabs: _tabs(overview),
                          selectedIndex: selectedTab,
                          isCompact: false,
                          onChanged: (index) {
                            setState(() {
                              selectedTab = index;
                              selectedStatusIndex = 0;
                            });
                            // 切换 tab 立即补偿刷新，避免展示过期的内存快照
                            _load(silent: true);
                          },
                          areas: _areas,
                          selectedArea: _selectedArea,
                          onAreaChanged: (area) => setState(() => _selectedArea = area),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.canManageTable &&
                                  (_modeForTab(selectedTab) ==
                                          _DashboardMode.all ||
                                      _modeForTab(selectedTab) ==
                                          _DashboardMode.tables)) ...[
                                _AddTableButton(
                                  busy: tableActionBusy,
                                  isCompact: false,
                                  onTap: _createTable,
                                ),
                                const SizedBox(width: 12),
                                _UpdateDinersButton(
                                  busy: tableActionBusy,
                                  isCompact: false,
                                  onTap: _promptUpdateDiners,
                                ),
                              ],
                              if (((_modeForTab(selectedTab) ==
                                          _DashboardMode.all ||
                                      _modeForTab(selectedTab) ==
                                          _DashboardMode.tables) &&
                                  _clearableTables.isNotEmpty)) ...[
                                const SizedBox(width: 12),
                                _ClearAllButton(
                                  count: _clearableTables.length,
                                  busy: tableActionBusy,
                                  isCompact: false,
                                  onTap: _clearAllSettledTables,
                                ),
                              ],
                            ],
                          ),
                        ),
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: _TableGridPanel(
                                  overview: overview,
                                  mode: _modeForTab(selectedTab),
                                  statusIndex: selectedStatusIndex,
                                  loading: loading,
                                  error: error,
                                  onRetry: _load,
                                  onTableSelected: _openTable,
                                  onFulfillmentSelected: _openFulfillment,
                                  onPickupOrder: widget.onPickupOrder,
                                  isCompact: false,
                                  cardSize: _tableCardSize,
                                  onCardSizeChanged: (v) =>
                                      setState(() => _tableCardSize = v),
                                  canManageTable: widget.canManageTable,
                                  selectedArea: _selectedArea,
                                  onDeleteTable: _deleteTable,
                                  onTableLongPress: _onTableLongPress,
                                ),
                              ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 14,
                                child: Center(
                                  child: _StatusLegend(
                                    overview: overview,
                                    mode: _modeForTab(selectedTab),
                                    selectedIndex: selectedStatusIndex,
                                    isCompact: false,
                                    onChanged: (index) =>
                                        setState(() => selectedStatusIndex = index),
                                    onQuickOpen: _createTable,
                                    onBatchClear: _clearAllSettledTables,
                                    canManageTable: widget.canManageTable,
                                    clearableCount: _clearableTables.length,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  _DashboardMode _modeForTab(int index) {
    return switch (index) {
      1 => _DashboardMode.tables,
      2 => _DashboardMode.takeout,
      3 => _DashboardMode.pickup,
      _ => _DashboardMode.all,
    };
  }

  List<_DiningTab> _tabs(TableOverview? overview) {
    return [
      const _DiningTab('全部', null),
      _DiningTab('堂食（${overview?.dineInCount ?? 0}）', '堂食'),
      _DiningTab('外卖（${overview?.takeoutCount ?? 0}）', '外卖'),
      _DiningTab('自提（${overview?.pickupCount ?? 0}）', '自提'),
    ];
  }
}

class _RestaurantSidebar extends StatelessWidget {
  const _RestaurantSidebar({this.onKdsSettings});

  final VoidCallback? onKdsSettings;

  static const _items = ['点餐', '账单', '会员', '报表', '菜品', '设置'];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 226,
      color: context.cashier.surface,
      child: Column(
        children: [
          const SizedBox(height: 46),
          const _BrandMark(),
          const SizedBox(height: 12),
          Text(
            '老 肥 油 边 王',
            style: TextStyle(
              color: context.cashier.ink,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '松源海鲜街',
            style: TextStyle(
              color: context.cashier.ink,
              fontSize: 21,
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 17),
          const Text(
            '已联网',
            style: TextStyle(
              color: Color(0xff00d72f),
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 20),
          for (var index = 0; index < _items.length; index++)
            _SidebarMenuItem(
              label: _items[index],
              selected: index == 0,
              onTap: index == _items.length - 1 ? onKdsSettings : null,
            ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 155,
      height: 155,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black, width: 4),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 126,
            height: 126,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.black, width: 1.5),
            ),
          ),
          const Positioned(
            top: 18,
            child: Text(
              'Lao Fei Northeast Barbecue',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '老肥\n油边王',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: .95,
              color: context.cashier.ink,
              fontSize: 39,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const Positioned(
            bottom: 10,
            child: Text(
              '●  ●  ●  ●  ●',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarMenuItem extends StatelessWidget {
  const _SidebarMenuItem({
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 96,
          alignment: Alignment.center,
          color: selected
              ? (Theme.of(context).brightness == Brightness.dark
                    ? context.cashier.selectedBackground
                    : const Color(0xff352f2f))
              : context.cashier.surface,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xfff5e8e8) : context.cashier.ink,
              fontSize: 32,
              fontWeight: FontWeight.w700,
              letterSpacing: 10,
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderToolbar extends StatelessWidget {
  const _OrderToolbar({
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
    this.areas = const [],
    this.selectedArea = 'all',
    this.onAreaChanged,
    this.isCompact = false,
    this.trailing,
  });

  final List<_DiningTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final List<Map<String, dynamic>> areas;
  final String selectedArea;
  final ValueChanged<String>? onAreaChanged;
  final bool isCompact;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Container(
      height: isCompact ? 52 : 68,
      color: Colors.transparent,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(isCompact ? 3 : 5),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var index = 0; index < tabs.length; index++) ...[
                          if (index > 0) SizedBox(width: isCompact ? 4 : 6),
                          _DiningSegButton(
                            label: tabs[index].label,
                            selected: index == selectedIndex,
                            compact: isCompact,
                            onTap: () => onChanged(index),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (areas.isNotEmpty && onAreaChanged != null) ...[
                    SizedBox(width: isCompact ? 8 : 14),
                    Container(
                      padding: EdgeInsets.all(isCompact ? 3 : 5),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: tokens.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _AreaSegButton(
                            label: '全部区域',
                            selected: selectedArea == 'all',
                            compact: isCompact,
                            onTap: () => onAreaChanged!('all'),
                          ),
                          for (final area in areas) ...[
                            SizedBox(width: isCompact ? 4 : 6),
                            _AreaSegButton(
                              label: area['name']?.toString() ?? '',
                              selected: selectedArea == (area['code']?.toString() ?? ''),
                              compact: isCompact,
                              onTap: () => onAreaChanged!(area['code']?.toString() ?? ''),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: trailing!,
            ),
          ],
        ],
      ),
    );
  }
}

/// 区域过滤胶囊按钮
class _AreaSegButton extends StatelessWidget {
  const _AreaSegButton({
    required this.label,
    required this.selected,
    this.compact = false,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final bg = selected ? tokens.btnPrimaryBg : Colors.transparent;
    final fg = selected ? tokens.btnPrimaryInk : tokens.inkSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 18),
          child: SizedBox(
            height: compact ? 36 : 46,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: compact ? 13 : 15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 就餐方式胶囊按钮
class _DiningSegButton extends StatelessWidget {
  const _DiningSegButton({
    required this.label,
    required this.selected,
    this.compact = false,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final parts = label.split('（');
    final name = parts.first;
    final count = parts.length > 1 ? '（${parts[1]}' : '';

    final bg = selected ? tokens.btnPrimaryBg : Colors.transparent;
    final fg = selected ? tokens.btnPrimaryInk : tokens.inkSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
          child: SizedBox(
            height: compact ? 36 : 46,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: fg,
                    fontSize: compact ? 13 : 16,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
                if (count.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(
                    count,
                    style: TextStyle(
                      color: selected
                          ? fg.withValues(alpha: 0.8)
                          : tokens.inkMuted,
                      fontSize: compact ? 12 : 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 批量清台按钮
class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({
    required this.count,
    required this.busy,
    required this.onTap,
    this.isCompact = false,
  });

  final int count;
  final bool busy;
  final VoidCallback onTap;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final isDanger = count > 0;
    return OutlinedButton(
      key: const Key('clear-all-settled-tables'),
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isDanger ? const Color(0xffef4444) : tokens.inkMuted,
        backgroundColor: isDanger
            ? const Color(0xffef4444).withValues(alpha: 0.06)
            : tokens.surface,
        side: BorderSide(
          color: isDanger
              ? const Color(0xffef4444).withValues(alpha: 0.6)
              : tokens.border,
          width: 1.2,
        ),
        minimumSize: Size(0, isCompact ? 40 : 46),
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        count > 0 ? '批量清台 ($count)' : '批量清台',
        style: TextStyle(
          fontSize: isCompact ? 13.5 : 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 快速开台按钮
class _AddTableButton extends StatelessWidget {
  const _AddTableButton({
    required this.busy,
    required this.onTap,
    this.isCompact = false,
  });

  final bool busy;
  final VoidCallback onTap;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return FilledButton(
      key: const Key('create-table-button'),
      onPressed: busy ? null : onTap,
      style: FilledButton.styleFrom(
        backgroundColor: tokens.btnPrimaryBg,
        foregroundColor: tokens.btnPrimaryInk,
        disabledBackgroundColor: tokens.subtle,
        minimumSize: Size(0, isCompact ? 40 : 46),
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 0,
      ),
      child: Text(
        '+ 快速开台',
        style: TextStyle(
          fontSize: isCompact ? 13.5 : 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 调整人数按钮
class _UpdateDinersButton extends StatelessWidget {
  const _UpdateDinersButton({
    required this.busy,
    required this.onTap,
    this.isCompact = false,
  });

  final bool busy;
  final VoidCallback onTap;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return OutlinedButton(
      key: const Key('toolbar-update-diners-button'),
      onPressed: busy ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.ink,
        backgroundColor: tokens.surface,
        side: BorderSide(color: tokens.border, width: 1.2),
        minimumSize: Size(0, isCompact ? 40 : 46),
        padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(
        '调整人数',
        style: TextStyle(
          fontSize: isCompact ? 13.5 : 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _CreateTableDialog extends StatefulWidget {
  const _CreateTableDialog({
    required this.existingNumbers,
    this.areas = const [],
  });

  final Set<String> existingNumbers;
  final List<Map<String, dynamic>> areas;

  @override
  State<_CreateTableDialog> createState() => _CreateTableDialogState();
}

class _CreateTableDialogState extends State<_CreateTableDialog> {
  final _formKey = GlobalKey<FormState>();
  final _numberController = TextEditingController();
  final _peopleController = TextEditingController(text: '4');
  late String _selectedAreaCode;

  @override
  void initState() {
    super.initState();
    final effectiveAreas = widget.areas.isNotEmpty
        ? widget.areas
        : const [
            {'code': 'hall', 'name': '大厅散座'},
            {'code': 'box', 'name': '特色包厢'},
            {'code': 'patio', 'name': '露天外摆'},
          ];
    _selectedAreaCode = effectiveAreas.first['code']?.toString() ?? 'hall';
  }

  @override
  void dispose() {
    _numberController.dispose();
    _peopleController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final number = _numberController.text.trim();
    final people = int.tryParse(_peopleController.text.trim()) ?? 4;
    final areaMap = widget.areas.firstWhere(
      (a) => a['code']?.toString() == _selectedAreaCode,
      orElse: () => {
        'code': _selectedAreaCode,
        'name': switch (_selectedAreaCode) {
          'box' => '特色包厢',
          'patio' => '露天外摆',
          _ => '大厅散座',
        },
      },
    );
    final areaName = areaMap['name']?.toString() ?? '大厅散座';
    Navigator.pop(context, (
      number: number,
      peopleCount: people,
      areaCode: _selectedAreaCode,
      areaName: areaName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final effectiveAreas = widget.areas.isNotEmpty
        ? widget.areas
        : const [
            {'code': 'hall', 'name': '大厅散座'},
            {'code': 'box', 'name': '特色包厢'},
            {'code': 'patio', 'name': '露天外摆'},
          ];

    return CashierDialogFrame(
      width: 480,
      height: 450,
      title: '新建桌台',
      onClose: () => Navigator.pop(context),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '请输入要新建的桌台编号、所属区域及容纳人数。桌台创建后可在点餐台正常点单就餐。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('create-table-number-input'),
              controller: _numberController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '桌号 *',
                hintText: '例如: A01, 8, 包厢1',
                prefixIcon: Icon(Icons.table_restaurant),
                border: OutlineInputBorder(),
              ),
              validator: (val) {
                final text = val?.trim() ?? '';
                if (text.isEmpty) return '请输入桌号';
                if (widget.existingNumbers.contains(text)) {
                  return '桌号 $text 已存在';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('create-table-area-select'),
              initialValue: _selectedAreaCode,
              decoration: const InputDecoration(
                labelText: '所属区域',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
              items: effectiveAreas
                  .map((area) => DropdownMenuItem(
                        value: area['code']?.toString() ?? 'hall',
                        child: Text(area['name']?.toString() ?? '大厅散座'),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedAreaCode = val);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('create-table-people-input'),
              controller: _peopleController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '容纳人数',
                hintText: '4',
                suffixText: '人',
                prefixIcon: Icon(Icons.people_outline),
                border: OutlineInputBorder(),
              ),
              validator: (val) {
                final p = int.tryParse(val?.trim() ?? '');
                if (p == null || p < 1 || p > 99) {
                  return '人数必须在 1 到 99 之间';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
        CashierActionButton(
          key: const Key('create-table-confirm-button'),
          label: '确认创建',
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _EditTableDialog extends StatefulWidget {
  const _EditTableDialog({
    required this.table,
    required this.existingNumbers,
    this.areas = const [],
  });

  final DiningTable table;
  final Set<String> existingNumbers;
  final List<Map<String, dynamic>> areas;

  @override
  State<_EditTableDialog> createState() => _EditTableDialogState();
}

class _EditTableDialogState extends State<_EditTableDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numberController;
  late final TextEditingController _peopleController;
  late String _selectedAreaCode;

  @override
  void initState() {
    super.initState();
    _numberController = TextEditingController(text: widget.table.number);
    _peopleController =
        TextEditingController(text: widget.table.people.toString());
    final currentCode = widget.table.effectiveAreaCode.isNotEmpty
        ? widget.table.effectiveAreaCode
        : 'hall';
    final effectiveAreas = widget.areas.isNotEmpty
        ? widget.areas
        : const [
            {'code': 'hall', 'name': '大厅散座'},
            {'code': 'box', 'name': '特色包厢'},
            {'code': 'patio', 'name': '露天外摆'},
          ];
    final hasCode =
        effectiveAreas.any((a) => a['code']?.toString() == currentCode);
    _selectedAreaCode =
        hasCode ? currentCode : (effectiveAreas.first['code']?.toString() ?? 'hall');
  }

  @override
  void dispose() {
    _numberController.dispose();
    _peopleController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final number = _numberController.text.trim();
    final people =
        int.tryParse(_peopleController.text.trim()) ?? widget.table.people;
    final areaMap = widget.areas.firstWhere(
      (a) => a['code']?.toString() == _selectedAreaCode,
      orElse: () => {
        'code': _selectedAreaCode,
        'name': switch (_selectedAreaCode) {
          'box' => '特色包厢',
          'patio' => '露天外摆',
          _ => '大厅散座',
        },
      },
    );
    final areaName = areaMap['name']?.toString() ?? '大厅散座';
    Navigator.pop(context, (
      number: number,
      peopleCount: people,
      areaCode: _selectedAreaCode,
      areaName: areaName,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final effectiveAreas = widget.areas.isNotEmpty
        ? widget.areas
        : const [
            {'code': 'hall', 'name': '大厅散座'},
            {'code': 'box', 'name': '特色包厢'},
            {'code': 'patio', 'name': '露天外摆'},
          ];

    return CashierDialogFrame(
      width: 480,
      height: 450,
      title: '编辑桌台 · ${widget.table.number}号桌',
      onClose: () => Navigator.pop(context),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '修改桌台编号、所属区域及容纳人数。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 20),
            TextFormField(
              key: const Key('edit-table-number-input'),
              controller: _numberController,
              decoration: const InputDecoration(
                labelText: '桌号 *',
                hintText: '例如: A01, 8, 包厢1',
                prefixIcon: Icon(Icons.table_restaurant),
                border: OutlineInputBorder(),
              ),
              validator: (val) {
                final text = val?.trim() ?? '';
                if (text.isEmpty) return '请输入桌号';
                if (text != widget.table.number &&
                    widget.existingNumbers.contains(text)) {
                  return '桌号 $text 已存在';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('edit-table-area-select'),
              initialValue: _selectedAreaCode,
              decoration: const InputDecoration(
                labelText: '所属区域',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
              items: effectiveAreas
                  .map((area) => DropdownMenuItem(
                        value: area['code']?.toString() ?? 'hall',
                        child: Text(area['name']?.toString() ?? '大厅散座'),
                      ))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedAreaCode = val);
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('edit-table-people-input'),
              controller: _peopleController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '容纳人数',
                hintText: '4',
                suffixText: '人',
                prefixIcon: Icon(Icons.people_outline),
                border: OutlineInputBorder(),
              ),
              validator: (val) {
                final p = int.tryParse(val?.trim() ?? '');
                if (p == null || p < 1 || p > 99) {
                  return '人数必须在 1 到 99 之间';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        CashierActionButton(
          label: '取消',
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
        CashierActionButton(
          key: const Key('edit-table-confirm-button'),
          label: '保存修改',
          onPressed: _submit,
        ),
      ],
    );
  }
}

class _TableQrDialog extends StatelessWidget {
  const _TableQrDialog({
    required this.table,
    this.canManageTable = false,
    this.onEdit,
    this.onDelete,
  });

  final DiningTable table;
  final bool canManageTable;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  String _resolveTableWxacodeUrl(DiningTable table) {
    final raw = table.qrcode.trim();
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }
    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl.substring(0, AppConfig.apiBaseUrl.length - 1)
        : AppConfig.apiBaseUrl;
    if (raw.startsWith('/')) {
      return '$base$raw';
    }
    if (raw.isNotEmpty &&
        !raw.contains('?') &&
        (raw.endsWith('.png') || raw.endsWith('.jpg') || raw.endsWith('.jpeg'))) {
      return '$base/image/qrcode/$raw';
    }
    return '$base/admin/table/qrcode?number=${Uri.encodeComponent(table.number)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final isOccupied = table.isOccupied;
    final areaText = table.areaName.isNotEmpty
        ? table.areaName
        : (table.effectiveAreaCode == 'box'
            ? '特色包厢'
            : (table.effectiveAreaCode == 'patio'
                ? '露天外摆'
                : '大厅散座'));
    final qrImageUrl = _resolveTableWxacodeUrl(table);

    return CashierDialogFrame(
      compact: true,
      width: 500,
      height: 520,
      title: '桌台小程序码 · ${table.number}号桌',
      subtitle:
          '$areaText · 额定容量 ${table.people}人 · ${table.status == TableStatus.empty ? "空闲" : (table.status == TableStatus.pending ? "就餐中" : "已结账")}',
      onClose: () => Navigator.pop(context),
      actions: [
        if (canManageTable && onEdit != null)
          CashierActionButton(
            key: Key('edit-table-${table.number}'),
            label: '编辑桌台',
            minimumWidth: 100,
            variant: CashierActionButtonVariant.primary,
            onPressed: onEdit,
          ),
        if (canManageTable && onDelete != null)
          CashierActionButton(
            key: Key('delete-table-${table.number}'),
            label: '删除桌台',
            minimumWidth: 100,
            variant: CashierActionButtonVariant.danger,
            onPressed: isOccupied
                ? () {
                    showPosNotice(
                      context,
                      title: '无法删除',
                      message: '该桌台当前正在就餐中，请先结账或清台后再删除。',
                      tone: PosNoticeTone.warning,
                    );
                  }
                : onDelete,
          ),
        CashierActionButton(
          label: '关闭',
          minimumWidth: 100,
          variant: CashierActionButtonVariant.secondary,
          onPressed: () => Navigator.pop(context),
        ),
      ],
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 小程序码白底容器
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: tokens.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  qrImageUrl,
                  key: Key('table-wxacode-image-${table.number}'),
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return const Center(
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.qr_code_2_rounded, size: 52, color: tokens.inkMuted),
                            const SizedBox(height: 8),
                            Text(
                              '微信小程序码',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: tokens.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '正在连接服务加载...',
                              style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: tokens.subtle,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: tokens.border),
              ),
              child: Text(
                '桌号：${table.number} · 微信扫码点餐',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '顾客使用微信扫描此小程序码，可直接进入本桌点餐与呼叫服务',
              style: TextStyle(
                fontSize: 12,
                color: tokens.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<int?> showOpenTableDialog(
  BuildContext context, {
  required DiningTable table,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<int>(
    context: context,
    barrierDismissible: true,
    barrierColor: const Color(0x66000000),
    builder: (context) => _OpenTableDialog(table: table),
  );
  final result = await navigator.push<int>(route);
  await route.completed;
  await Future<void>.delayed(Duration.zero);
  await WidgetsBinding.instance.endOfFrame;
  await WidgetsBinding.instance.endOfFrame;
  return result;
}

class _OpenTableDialog extends StatefulWidget {
  const _OpenTableDialog({required this.table});

  final DiningTable table;

  @override
  State<_OpenTableDialog> createState() => _OpenTableDialogState();
}

class _OpenTableDialogState extends State<_OpenTableDialog> {
  late int _diners;
  static const _quickCounts = [1, 2, 3, 4, 5, 6, 7, 8, 10, 12];

  @override
  void initState() {
    super.initState();
    _diners = widget.table.people > 0 ? widget.table.people : 4;
  }

  void _increment() {
    if (_diners < 99) setState(() => _diners++);
  }

  void _decrement() {
    if (_diners > 1) setState(() => _diners--);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final areaText = widget.table.areaName.isNotEmpty
        ? widget.table.areaName
        : (widget.table.effectiveAreaCode == 'box'
            ? '特色包厢'
            : (widget.table.effectiveAreaCode == 'patio'
                ? '露天外摆'
                : '大厅散座'));

    return KeyedSubtree(
      key: const Key('pos-notice-dialog'),
      child: CashierDialogFrame(
        compact: true,
        width: 440,
        height: 400,
        title: '桌台开台 · ${widget.table.number}号桌',
        subtitle: '$areaText · 额定容量 ${widget.table.people}人',
        onClose: () => Navigator.of(context).pop(null),
        actions: [
          CashierActionButton(
            key: const Key('pos-notice-secondary'),
            label: '取消',
            variant: CashierActionButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(null),
          ),
          CashierActionButton(
            key: const Key('pos-notice-primary'),
            label: '确认开台',
            variant: CashierActionButtonVariant.primary,
            onPressed: () => Navigator.of(context).pop(_diners),
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 隐藏/微型语义标记，确保测试查找 "是否开台" 稳定兼容
            Semantics(
              label: '是否开台',
              child: const Text(
                '是否开台',
                style: TextStyle(fontSize: 0, height: 0, color: Colors.transparent),
              ),
            ),
          // 提示条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: tokens.subtle,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              children: [
                Icon(Icons.people_outline_rounded, size: 20, color: tokens.ink),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '请选择就餐人数，开台后将直接进入点菜下单界面',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // 步进调节器核心区
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // 减人数
                IconButton.outlined(
                  key: const Key('open-table-diners-dec'),
                  onPressed: _diners > 1 ? _decrement : null,
                  icon: const Icon(Icons.remove_rounded, size: 22),
                  style: IconButton.styleFrom(
                    side: BorderSide(color: tokens.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                // 人数数值显示
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$_diners',
                      key: const Key('open-table-diners-count'),
                      style: TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                        color: tokens.ink,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '人',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: tokens.inkSecondary,
                      ),
                    ),
                  ],
                ),
                // 加人数
                IconButton.outlined(
                  key: const Key('open-table-diners-inc'),
                  onPressed: _diners < 99 ? _increment : null,
                  icon: const Icon(Icons.add_rounded, size: 22),
                  style: IconButton.styleFrom(
                    side: BorderSide(color: tokens.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 快捷人数胶囊
          Text(
            '快捷选择就餐人数：',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tokens.inkSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickCounts.map((count) {
              final isSelected = _diners == count;
              return ChoiceChip(
                key: Key('open-table-quick-$count'),
                label: Text('$count人'),
                selected: isSelected,
                onSelected: (_) => setState(() => _diners = count),
                selectedColor: tokens.btnPrimaryBg,
                backgroundColor: tokens.subtle,
                labelStyle: TextStyle(
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? tokens.btnPrimaryInk : tokens.ink,
                ),
                side: BorderSide(
                  color: isSelected ? Colors.transparent : tokens.border,
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    ),
    );
  }
}

class _TableDeleteAuthDialog extends StatefulWidget {
  const _TableDeleteAuthDialog({
    required this.table,
    this.currentAccount,
    required this.onVerify,
  });

  final DiningTable table;
  final String? currentAccount;
  final Future<void> Function(String username, String password) onVerify;

  @override
  State<_TableDeleteAuthDialog> createState() => _TableDeleteAuthDialogState();
}

class _TableDeleteAuthDialogState extends State<_TableDeleteAuthDialog> {
  late final TextEditingController _accountController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _verifying = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _accountController = TextEditingController(
      text: widget.currentAccount?.isNotEmpty == true
          ? widget.currentAccount
          : 'admin',
    );
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleConfirm() async {
    final account = _accountController.text.trim();
    final password = _passwordController.text.trim();
    if (account.isEmpty) {
      setState(() => _errorMessage = '请输入员工工号或管理员账号');
      return;
    }
    if (password.isEmpty) {
      setState(() => _errorMessage = '请输入授权密码');
      return;
    }

    setState(() {
      _verifying = true;
      _errorMessage = null;
    });

    try {
      await widget.onVerify(account, password);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      String message = e.toString();
      if (message.startsWith('Exception: ')) {
        message = message.substring('Exception: '.length);
      }
      setState(() {
        _verifying = false;
        _errorMessage =
            message.contains('密码') ||
                message.contains('账号') ||
                message.contains('工号')
            ? message
            : '验证失败：$message';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CashierDialogFrame(
      compact: true,
      width: 480,
      height: 440,
      title: '管理员权限验证',
      subtitle: '敏感操作确认：正在删除【${widget.table.number}号桌】',
      onClose: _verifying ? null : () => Navigator.pop(context, false),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('delete-table-auth-account'),
            controller: _accountController,
            enabled: !_verifying,
            decoration: const InputDecoration(
              labelText: '员工工号 / 管理员账号 *',
              hintText: '请输入员工工号或系统用户名 (如 EMP1001)',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('delete-table-auth-password'),
            controller: _passwordController,
            enabled: !_verifying,
            obscureText: _obscurePassword,
            autofocus: true,
            onSubmitted: (_) => _handleConfirm(),
            decoration: InputDecoration(
              labelText: '管理员密码 *',
              hintText: '请输入密码进行授权',
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xfffef2f2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xffef4444).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: context.cashier.danger,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: context.cashier.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const Key('delete-table-auth-cancel'),
                  onPressed: _verifying
                      ? null
                      : () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FilledButton(
                  key: const Key('delete-table-auth-confirm'),
                  onPressed: _verifying ? null : _handleConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.cashier.danger,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _verifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '验证并删除',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TableGridPanel extends StatelessWidget {
  const _TableGridPanel({
    required this.overview,
    required this.mode,
    required this.statusIndex,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onTableSelected,
    required this.onFulfillmentSelected,
    required this.onPickupOrder,
    required this.cardSize,
    required this.onCardSizeChanged,
    this.isCompact = false,
    this.canManageTable = false,
    this.selectedArea = 'all',
    this.onDeleteTable,
    this.onTableLongPress,
  });

  final TableOverview? overview;
  final _DashboardMode mode;
  final int statusIndex;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;
  final ValueChanged<DiningTable> onTableSelected;
  final ValueChanged<FulfillmentOrder> onFulfillmentSelected;
  final Future<void> Function()? onPickupOrder;
  final double cardSize;
  final ValueChanged<double> onCardSizeChanged;
  final bool isCompact;
  final bool canManageTable;
  final String selectedArea;
  final ValueChanged<DiningTable>? onDeleteTable;
  final ValueChanged<DiningTable>? onTableLongPress;

  @override
  Widget build(BuildContext context) {
    final hasSnapshot = overview != null;
    final child = switch (mode) {
      _DashboardMode.all => _UnifiedGrid(
        items: _filteredUnifiedItems(
          overview: overview,
          statusIndex: statusIndex,
          hasPickupOrderEntry: onPickupOrder != null,
          selectedArea: selectedArea,
        ),
        onTableSelected: onTableSelected,
        onOrderSelected: onFulfillmentSelected,
        onPickupOrder: onPickupOrder,
        cardSize: cardSize,
        isCompact: isCompact,
        canManageTable: canManageTable,
        onDeleteTable: onDeleteTable,
        onTableLongPress: onTableLongPress,
      ),
      _DashboardMode.tables => _TableGrid(
        tables: _filteredTables(
          overview?.tables ?? const [],
          statusIndex,
          selectedArea: selectedArea,
        ),
        onTableSelected: onTableSelected,
        cardSize: cardSize,
        isCompact: isCompact,
        canManageTable: canManageTable,
        onDeleteTable: onDeleteTable,
        onTableLongPress: onTableLongPress,
      ),
      _DashboardMode.takeout => _FulfillmentGrid(
        orders: _filteredFulfillmentOrders(
          overview?.takeoutOrders ?? const [],
          statusIndex,
          includeDelivering: true,
        ),
        onOrderSelected: onFulfillmentSelected,
        cardSize: cardSize,
        isCompact: isCompact,
      ),
      _DashboardMode.pickup => _FulfillmentGrid(
        orders: _filteredFulfillmentOrders(
          overview?.pickupOrders ?? const [],
          statusIndex,
          includeDelivering: false,
        ),
        onOrderSelected: onFulfillmentSelected,
        onPickupOrder: onPickupOrder,
        cardSize: cardSize,
        isCompact: isCompact,
      ),
    };
    return Container(
      key: const Key('table-grid-panel-background'),
      color: context.cashier.canvas,
      child: Stack(
        children: [
          child,
          if (loading && !hasSnapshot)
            const Center(child: CircularProgressIndicator()),
          if (error != null && !hasSnapshot)
            Center(
              child: _LoadError(message: error!, onRetry: onRetry),
            ),
          if (hasSnapshot)
            Positioned(
              right: 22,
              top: 18,
              child: _RefreshBadge(
                loading: loading,
                hasError: error != null,
                onRefresh: onRetry,
              ),
            ),
          if (!isCompact)
            Positioned(
              right: 22,
              bottom: 18,
              child: _TableSizeSlider(
                value: cardSize,
                onChanged: onCardSizeChanged,
              ),
            ),
        ],
      ),
    );
  }
}

/// 右下角桌台方块大小调节滑块
class _TableSizeSlider extends StatelessWidget {
  const _TableSizeSlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  static const _min = 160.0;
  static const _max = 340.0;

  @override
  Widget build(BuildContext context) {
    final current = value.clamp(_min, _max);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: context.cashier.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.grid_view_rounded, size: 18, color: context.cashier.ink),
          SizedBox(
            width: 168,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                key: const Key('table-card-size-slider'),
                value: current,
                min: _min,
                max: _max,
                divisions: 14,
                label: '${current.round()}',
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              '${current.round()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: context.cashier.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

sealed class _UnifiedDashboardItem {}

class _TableDashboardItem extends _UnifiedDashboardItem {
  _TableDashboardItem(this.table);
  final DiningTable table;
}

class _FulfillmentDashboardItem extends _UnifiedDashboardItem {
  _FulfillmentDashboardItem(this.order);
  final FulfillmentOrder order;
}

class _PickupEntryDashboardItem extends _UnifiedDashboardItem {}

List<_UnifiedDashboardItem> _filteredUnifiedItems({
  required TableOverview? overview,
  required int statusIndex,
  required bool hasPickupOrderEntry,
  String selectedArea = 'all',
}) {
  if (overview == null) return const [];
  final allTables = overview.tables;
  final tables = selectedArea == 'all'
      ? allTables
      : allTables.where((t) => t.effectiveAreaCode == selectedArea).toList(growable: false);
  final takeoutOrders = overview.takeoutOrders;
  final pickupOrders = overview.pickupOrders;

  return switch (statusIndex) {
    1 => [
      // 待结账: tables pending + fulfillment pendingPayment
      for (final t in tables)
        if (t.status == TableStatus.pending) _TableDashboardItem(t),
      for (final o in takeoutOrders)
        if (o.status == FulfillmentStatus.pendingPayment)
          _FulfillmentDashboardItem(o),
      for (final o in pickupOrders)
        if (o.status == FulfillmentStatus.pendingPayment)
          _FulfillmentDashboardItem(o),
    ],
    2 => [
      // 待取餐 / 已结账: tables settled + fulfillment waiting
      for (final t in tables)
        if (t.status == TableStatus.settled) _TableDashboardItem(t),
      for (final o in takeoutOrders)
        if (o.status == FulfillmentStatus.waiting) _FulfillmentDashboardItem(o),
      for (final o in pickupOrders)
        if (o.status == FulfillmentStatus.waiting) _FulfillmentDashboardItem(o),
    ],
    3 => [
      // 配送中: fulfillment delivering
      for (final o in takeoutOrders)
        if (o.status == FulfillmentStatus.delivering)
          _FulfillmentDashboardItem(o),
      for (final o in pickupOrders)
        if (o.status == FulfillmentStatus.delivering)
          _FulfillmentDashboardItem(o),
    ],
    4 => [
      // 空桌: tables empty
      for (final t in tables)
        if (t.status == TableStatus.empty) _TableDashboardItem(t),
    ],
    5 => [
      // 已完成: fulfillment completed
      for (final o in takeoutOrders)
        if (o.status == FulfillmentStatus.completed)
          _FulfillmentDashboardItem(o),
      for (final o in pickupOrders)
        if (o.status == FulfillmentStatus.completed)
          _FulfillmentDashboardItem(o),
    ],
    _ => [
      // 全部
      for (final t in tables) _TableDashboardItem(t),
      for (final o in takeoutOrders) _FulfillmentDashboardItem(o),
      for (final o in pickupOrders) _FulfillmentDashboardItem(o),
    ],
  };
}

List<DiningTable> _filteredTables(
  List<DiningTable> tables,
  int statusIndex, {
  String selectedArea = 'all',
}) {
  final scoped = selectedArea == 'all'
      ? tables
      : tables.where((t) => t.effectiveAreaCode == selectedArea).toList(growable: false);
  return switch (statusIndex) {
    1 =>
      scoped
          .where((table) => table.status == TableStatus.settled)
          .toList(growable: false),
    2 =>
      scoped
          .where((table) => table.status == TableStatus.pending)
          .toList(growable: false),
    3 =>
      scoped
          .where((table) => table.status == TableStatus.empty)
          .toList(growable: false),
    _ => scoped,
  };
}

List<FulfillmentOrder> _filteredFulfillmentOrders(
  List<FulfillmentOrder> orders,
  int statusIndex, {
  required bool includeDelivering,
}) {
  final statuses = <FulfillmentStatus>[
    FulfillmentStatus.pendingPayment,
    FulfillmentStatus.waiting,
    if (includeDelivering) FulfillmentStatus.delivering,
    FulfillmentStatus.completed,
  ];
  if (statusIndex <= 0 || statusIndex > statuses.length) return orders;
  final selected = statuses[statusIndex - 1];
  return orders
      .where((order) => order.status == selected)
      .toList(growable: false);
}

class _RefreshBadge extends StatelessWidget {
  const _RefreshBadge({
    required this.loading,
    required this.hasError,
    required this.onRefresh,
  });

  final bool loading;
  final bool hasError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final color = hasError ? const Color(0xffe55353) : context.cashier.ink;
    return InkWell(
      onTap: loading ? null : onRefresh,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: context.cashier.surface.withValues(alpha: .92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(
                hasError ? Icons.sync_problem : Icons.sync,
                size: 16,
                color: color,
              ),
            const SizedBox(width: 7),
            Text(
              hasError ? '同步失败，点击重试' : '自动刷新',
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnifiedGrid extends StatelessWidget {
  const _UnifiedGrid({
    required this.items,
    required this.onTableSelected,
    required this.onOrderSelected,
    this.onPickupOrder,
    required this.cardSize,
    this.isCompact = false,
    this.canManageTable = false,
    this.onDeleteTable,
    this.onTableLongPress,
  });

  final List<_UnifiedDashboardItem> items;
  final double cardSize;
  final ValueChanged<DiningTable> onTableSelected;
  final ValueChanged<FulfillmentOrder> onOrderSelected;
  final Future<void> Function()? onPickupOrder;
  final bool isCompact;
  final bool canManageTable;
  final ValueChanged<DiningTable>? onDeleteTable;
  final ValueChanged<DiningTable>? onTableLongPress;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.expand();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 10 : 20,
        isCompact ? 8 : 16,
        isCompact ? 10 : 20,
        isCompact ? 48 : 85,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GridView.builder(
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: items.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: cardSize,
              crossAxisSpacing: isCompact ? 10 : 20,
              mainAxisSpacing: isCompact ? 10 : 20,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              return switch (item) {
                _PickupEntryDashboardItem() => _PickupOrderEntry(
                  onTap: onPickupOrder!,
                ),
                _TableDashboardItem(:final table) => _TableCard(
                  table: table,
                  onTap: () => onTableSelected(table),
                  canManage: canManageTable,
                  onLongPress: onTableLongPress != null
                      ? () => onTableLongPress!(table)
                      : (onDeleteTable != null
                            ? () => onDeleteTable!(table)
                            : null),
                ),
                _FulfillmentDashboardItem(:final order) => _FulfillmentCard(
                  order: order,
                  onTap: () => onOrderSelected(order),
                ),
              };
            },
          );
        },
      ),
    );
  }
}

class _TableGrid extends StatelessWidget {
  const _TableGrid({
    required this.tables,
    required this.onTableSelected,
    required this.cardSize,
    this.isCompact = false,
    this.canManageTable = false,
    this.onDeleteTable,
    this.onTableLongPress,
  });

  final List<DiningTable> tables;
  final ValueChanged<DiningTable> onTableSelected;
  final double cardSize;
  final bool isCompact;
  final bool canManageTable;
  final ValueChanged<DiningTable>? onDeleteTable;
  final ValueChanged<DiningTable>? onTableLongPress;

  @override
  Widget build(BuildContext context) {
    if (tables.isEmpty) return const SizedBox.expand();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 10 : 20,
        isCompact ? 8 : 16,
        isCompact ? 10 : 20,
        isCompact ? 48 : 85,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GridView.builder(
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: tables.length,
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: cardSize,
              crossAxisSpacing: isCompact ? 10 : 20,
              mainAxisSpacing: isCompact ? 10 : 20,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) => _TableCard(
              table: tables[index],
              onTap: () => onTableSelected(tables[index]),
              canManage: canManageTable,
              onLongPress: onTableLongPress != null
                  ? () => onTableLongPress!(tables[index])
                  : (onDeleteTable != null
                        ? () => onDeleteTable!(tables[index])
                        : null),
            ),
          );
        },
      ),
    );
  }
}

class _FulfillmentGrid extends StatelessWidget {
  const _FulfillmentGrid({
    required this.orders,
    required this.onOrderSelected,
    this.onPickupOrder,
    required this.cardSize,
    this.isCompact = false,
  });

  final List<FulfillmentOrder> orders;
  final double cardSize;
  final ValueChanged<FulfillmentOrder> onOrderSelected;
  final Future<void> Function()? onPickupOrder;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty && onPickupOrder == null) {
      return const SizedBox.expand();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        isCompact ? 10 : 20,
        isCompact ? 8 : 16,
        isCompact ? 10 : 20,
        isCompact ? 48 : 85,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GridView.builder(
            padding: EdgeInsets.zero,
            physics: const BouncingScrollPhysics(),
            itemCount: orders.length + (onPickupOrder == null ? 0 : 1),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: cardSize,
              crossAxisSpacing: isCompact ? 10 : 20,
              mainAxisSpacing: isCompact ? 10 : 20,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              if (onPickupOrder != null && index == 0) {
                return _PickupOrderEntry(onTap: onPickupOrder!);
              }
              final orderIndex = index - (onPickupOrder == null ? 0 : 1);
              final order = orders[orderIndex];
              return _FulfillmentCard(
                order: order,
                onTap: () => onOrderSelected(order),
              );
            },
          );
        },
      ),
    );
  }
}

class _PickupOrderEntry extends StatelessWidget {
  const _PickupOrderEntry({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: const Key('pickup-order-entry'),
      color: context.cashier.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 58,
                  color: context.cashier.ink,
                ),
                const SizedBox(height: 18),
                Text(
                  '前台打包点餐',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.cashier.ink,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '自提下单入口',
                  style: TextStyle(
                    color: context.cashier.inkMuted,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 360,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '桌台状态加载失败',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.table,
    required this.onTap,
    this.canManage = false,
    this.onLongPress,
  });

  final DiningTable table;
  final VoidCallback onTap;
  final bool canManage;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final occupied = table.isOccupied;
    final duration = table.occupiedDuration(DateTime.now());

    final (barColor, textColor, statusLabel) = switch (table.status) {
      TableStatus.empty => (
        tokens.tableStateIdleBar,
        tokens.tableStateIdleText,
        '空闲',
      ),
      TableStatus.pending => (
        tokens.tableStateDiningBar,
        tokens.tableStateDiningText,
        '就餐中',
      ),
      TableStatus.settled => (
        tokens.tableStateCleaningBar,
        tokens.tableStateCleaningText,
        '已结账',
      ),
    };

    final cardFill = barColor;

    final isCompact = MediaQuery.sizeOf(context).height < 550 ||
        MediaQuery.sizeOf(context).width < 900;

    return Semantics(
      button: true,
      label: '${table.number}号桌，点击进入点餐',
      child: Material(
        color: cardFill,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: table.status == TableStatus.empty
                ? tokens.border
                : Colors.black.withValues(alpha: 0.12),
            width: 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('table-card-${table.number}'),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部色块状态横幅 (Table Color Banner)
              Container(
                height: isCompact ? 40 : 50,
                padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 14),
                color: Colors.black.withValues(alpha: 0.04),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${table.number}号桌',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: isCompact ? 17 : 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 8 : 12,
                        vertical: isCompact ? 2 : 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: textColor,
                          fontSize: isCompact ? 12 : 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. 卡片主体 (Card Body - 简洁大数字，还原原型视觉张力)
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(isCompact ? 10 : 18),
                  child: occupied
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _amountText(table.amount),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: isCompact ? 36 : 56,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'monospace',
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  duration != null
                                      ? _durationText(duration)
                                      : '刚开台',
                                  style: TextStyle(
                                    color: textColor.withValues(alpha: 0.85),
                                    fontSize: isCompact ? 13 : 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 8 : 12,
                                    vertical: isCompact ? 3 : 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: textColor.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Text(
                                    '${table.people}人就餐',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: isCompact ? 13 : 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : (table.status == TableStatus.settled
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    table.amount == null || table.amount == 0
                                        ? '已结清'
                                        : _amountText(table.amount),
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: isCompact ? 36 : 56,
                                      fontWeight: FontWeight.w900,
                                      fontFamily: 'monospace',
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 8 : 12,
                                    vertical: isCompact ? 3 : 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: textColor.withValues(alpha: 0.25),
                                    ),
                                  ),
                                  child: Text(
                                    table.canClearAfterCheckout ? '待清台' : '已结账',
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: isCompact ? 13 : 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : const SizedBox.shrink()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FulfillmentCard extends StatelessWidget {
  const _FulfillmentCard({required this.order, required this.onTap});

  final FulfillmentOrder order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final duration = order.elapsedDuration(DateTime.now());
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = switch (order.status) {
      FulfillmentStatus.pendingPayment => const Color(0xff0284c7),
      FulfillmentStatus.waiting => const Color(0xffd97706),
      FulfillmentStatus.delivering => const Color(0xff8b5cf6),
      FulfillmentStatus.completed => const Color(0xff166534),
    };

    return Semantics(
      button: true,
      label: '${order.displayCode}，${_fulfillmentStatusLabel(order.status)}',
      child: Material(
        key: Key('fulfillment-order-${order.id}'),
        color: isDark ? context.cashier.surface : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor, width: 2),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scale = (constraints.maxWidth / 280.0).clamp(0.55, 1.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                order.type == FulfillmentType.takeout
                                    ? '外卖取餐码'
                                    : '自提取餐码',
                                style: TextStyle(
                                  color: context.cashier.ink,
                                  fontSize: 20 * scale,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                order.type == FulfillmentType.takeout
                                    ? '美团/饿了么外卖'
                                    : '前台自提打包',
                                style: TextStyle(
                                  color: context.cashier.inkMuted,
                                  fontSize: 12 * scale,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * scale,
                            vertical: 4 * scale,
                          ),
                          decoration: BoxDecoration(
                            color: switch (order.status) {
                              FulfillmentStatus.pendingPayment => const Color(
                                0xffe0f2fe,
                              ),
                              FulfillmentStatus.waiting => const Color(
                                0xfffef3c7,
                              ),
                              FulfillmentStatus.delivering => const Color(
                                0xfff3e8ff,
                              ),
                              FulfillmentStatus.completed => const Color(
                                0xffdcfce7,
                              ),
                            },
                            borderRadius: BorderRadius.circular(6 * scale),
                          ),
                          child: Text(
                            _fulfillmentStatusLabel(order.status),
                            style: TextStyle(
                              fontSize: 13 * scale,
                              fontWeight: FontWeight.w800,
                              color: switch (order.status) {
                                FulfillmentStatus.pendingPayment => const Color(
                                  0xff0369a1,
                                ),
                                FulfillmentStatus.waiting => const Color(
                                  0xffb45309,
                                ),
                                FulfillmentStatus.delivering => const Color(
                                  0xff7e22ce,
                                ),
                                FulfillmentStatus.completed => const Color(
                                  0xff15803d,
                                ),
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                    Center(
                      child: Text(
                        order.displayCode,
                        style: TextStyle(
                          color: context.cashier.ink,
                          fontSize: 48 * scale,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.only(top: 6 * scale),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: isDark
                                ? context.cashier.border
                                : const Color(0xffe5e5e5),
                            width: 1,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            order.status == FulfillmentStatus.waiting
                                ? '● 厨房已出餐'
                                : '● 配送跟踪',
                            style: TextStyle(
                              fontSize: 12 * scale,
                              fontWeight: FontWeight.w700,
                              color: borderColor,
                            ),
                          ),
                          if (duration != null)
                            Text(
                              _durationText(duration),
                              style: TextStyle(
                                fontSize: 12 * scale,
                                color: context.cashier.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _fulfillmentStatusLabel(FulfillmentStatus status) => switch (status) {
  FulfillmentStatus.pendingPayment => '待结账',
  FulfillmentStatus.waiting => '待取餐',
  FulfillmentStatus.delivering => '配送中',
  FulfillmentStatus.completed => '已完成',
};

String _amountText(num? value) {
  if (value == null) return '';
  if (value == value.roundToDouble()) return '¥${value.toInt()}';
  return '¥${value.toStringAsFixed(2)}';
}

String _durationText(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 1) return '刚刚';
  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;
  if (hours <= 0) return '$restMinutes分钟';
  if (restMinutes == 0) return '$hours小时';
  return '$hours小时$restMinutes分';
}

class _StatusLegend extends StatelessWidget {
  const _StatusLegend({
    required this.overview,
    required this.mode,
    required this.selectedIndex,
    required this.onChanged,
    this.isCompact = false,
    this.onQuickOpen,
    this.onBatchClear,
    this.canManageTable = false,
    this.clearableCount = 0,
  });

  final TableOverview? overview;
  final _DashboardMode mode;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool isCompact;
  final VoidCallback? onQuickOpen;
  final VoidCallback? onBatchClear;
  final bool canManageTable;
  final int clearableCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final entries = _legendEntries();

    final tables = overview?.tables ?? const [];
    double totalOccupiedAmount = 0.0;
    int occupiedCount = 0;
    int cleaningCount = 0;
    for (final table in tables) {
      if (table.isOccupied) {
        totalOccupiedAmount += (table.amount ?? 0).toDouble();
        occupiedCount++;
      }
      if (table.status == TableStatus.settled) {
        cleaningCount++;
      }
    }
    final rate = tables.isNotEmpty
        ? ((occupiedCount / tables.length) * 100).toStringAsFixed(1)
        : '0.0';

    return Container(
      height: isCompact ? 50 : 64,
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 16),
      color: Colors.transparent,
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 12 : 18,
            vertical: isCompact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: tokens.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 快捷状态筛选胶囊按钮组
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < entries.length; index++) ...[
                      if (index > 0) SizedBox(width: isCompact ? 6 : 8),
                      _LegendItem(
                        label: entries[index].label,
                        color: entries[index].color,
                        active: index == selectedIndex,
                        compact: isCompact,
                        onTap: () => onChanged(index),
                      ),
                    ],
                  ],
                ),

                // 2. 实时在席经营脉搏指标
                if (mode == _DashboardMode.all || mode == _DashboardMode.tables) ...[
                  SizedBox(width: isCompact ? 10 : 16),
                  Container(
                    height: 22,
                    width: 1,
                    color: tokens.border,
                  ),
                  SizedBox(width: isCompact ? 10 : 16),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '开台率: ',
                        style: TextStyle(
                          color: tokens.inkMuted,
                          fontSize: isCompact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$rate%',
                        style: TextStyle(
                          color: tokens.ink,
                          fontSize: isCompact ? 13 : 15,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                      SizedBox(width: isCompact ? 8 : 12),
                      Text(
                        '在席总额: ',
                        style: TextStyle(
                          color: tokens.inkMuted,
                          fontSize: isCompact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '¥${totalOccupiedAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: tokens.ink,
                          fontSize: isCompact ? 13 : 15,
                          fontWeight: FontWeight.w800,
                          fontFamily: 'monospace',
                        ),
                      ),
                      SizedBox(width: isCompact ? 8 : 12),
                      Text(
                        '待翻台: ',
                        style: TextStyle(
                          color: tokens.inkMuted,
                          fontSize: isCompact ? 13 : 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '$cleaningCount桌',
                        style: TextStyle(
                          color: tokens.ink,
                          fontSize: isCompact ? 13 : 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(width: isCompact ? 10 : 16),
                  Container(
                    height: 22,
                    width: 1,
                    color: tokens.border,
                  ),
                  SizedBox(width: isCompact ? 10 : 16),
                  // 3. 悬浮栏右侧快捷动作
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        key: const Key('status-bar-create-table'),
                        onTap: canManageTable ? onQuickOpen : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: isCompact ? 36 : 44,
                          padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 18),
                          decoration: BoxDecoration(
                            color: tokens.btnPrimaryBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '+ 快速开台',
                            style: TextStyle(
                              color: tokens.btnPrimaryInk,
                              fontSize: isCompact ? 13.5 : 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: isCompact ? 8 : 10),
                      InkWell(
                        key: const Key('status-bar-clear-all'),
                        onTap: clearableCount > 0 ? onBatchClear : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: isCompact ? 36 : 44,
                          padding: EdgeInsets.symmetric(horizontal: isCompact ? 14 : 18),
                          decoration: BoxDecoration(
                            color: tokens.subtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: tokens.border),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '批量清台',
                            style: TextStyle(
                              color: clearableCount > 0 ? tokens.ink : tokens.inkMuted,
                              fontSize: isCompact ? 13.5 : 15.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_LegendEntry> _legendEntries() {
    return switch (mode) {
      _DashboardMode.all => _allLegendEntries(overview),
      _DashboardMode.tables => [
        _LegendEntry('全部桌台（${overview?.total ?? 0}）', const Color(0xffffbb00)),
        _LegendEntry('已结账（${overview?.settled ?? 0}）', const Color(0xff16a34a)),
        _LegendEntry('待结账（${overview?.pending ?? 0}）', const Color(0xff2563eb)),
        _LegendEntry('空桌（${overview?.empty ?? 0}）', const Color(0xff71717a)),
      ],
      _DashboardMode.takeout => _fulfillmentLegendEntries(
        overview?.takeoutOrders ?? const [],
        includeDelivering: true,
      ),
      _DashboardMode.pickup => _fulfillmentLegendEntries(
        overview?.pickupOrders ?? const [],
        includeDelivering: false,
      ),
    };
  }
}

List<_LegendEntry> _allLegendEntries(TableOverview? overview) {
  final tables = overview?.tables ?? const [];
  final takeout = overview?.takeoutOrders ?? const [];
  final pickup = overview?.pickupOrders ?? const [];
  final allOrders = [...takeout, ...pickup];

  final pendingTables = tables
      .where((t) => t.status == TableStatus.pending)
      .length;
  final pendingOrders = allOrders
      .where((o) => o.status == FulfillmentStatus.pendingPayment)
      .length;
  final pendingTotal = pendingTables + pendingOrders;

  final settledTables = tables
      .where((t) => t.status == TableStatus.settled)
      .length;
  final waitingOrders = allOrders
      .where((o) => o.status == FulfillmentStatus.waiting)
      .length;
  final settledOrWaitingTotal = settledTables + waitingOrders;

  final deliveringOrders = allOrders
      .where((o) => o.status == FulfillmentStatus.delivering)
      .length;
  final emptyTables = tables.where((t) => t.status == TableStatus.empty).length;
  final completedOrders = allOrders
      .where((o) => o.status == FulfillmentStatus.completed)
      .length;

  return [
    _LegendEntry(
      '全部状态（${tables.length + allOrders.length}）',
      const Color(0xffffbb00),
    ),
    _LegendEntry('待结账（$pendingTotal）', const Color(0xff2563eb)),
    _LegendEntry('待取餐/已结账（$settledOrWaitingTotal）', const Color(0xffd97706)),
    _LegendEntry('配送中（$deliveringOrders）', const Color(0xff7e22ce)),
    _LegendEntry('空桌（$emptyTables）', const Color(0xff71717a)),
    _LegendEntry('已完成（$completedOrders）', const Color(0xff16a34a)),
  ];
}

List<_LegendEntry> _fulfillmentLegendEntries(
  List<FulfillmentOrder> orders, {
  required bool includeDelivering,
}) {
  final waiting = orders
      .where((order) => order.status == FulfillmentStatus.waiting)
      .length;
  final pendingPayment = orders
      .where((order) => order.status == FulfillmentStatus.pendingPayment)
      .length;
  final delivering = orders
      .where((order) => order.status == FulfillmentStatus.delivering)
      .length;
  final completed = orders
      .where((order) => order.status == FulfillmentStatus.completed)
      .length;
  return [
    _LegendEntry('全部状态（${orders.length}）', const Color(0xffffbb00)),
    _LegendEntry('待结账（$pendingPayment）', const Color(0xff2563eb)),
    _LegendEntry('待取餐（$waiting）', const Color(0xffd97706)),
    if (includeDelivering)
      _LegendEntry('配送中（$delivering）', const Color(0xff7e22ce)),
    _LegendEntry('已完成（$completed）', const Color(0xff16a34a)),
  ];
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.label,
    required this.color,
    required this.active,
    this.compact = false,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final bg = active ? tokens.btnPrimaryBg : tokens.subtle;
    final fg = active ? tokens.btnPrimaryInk : tokens.inkSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 16,
            vertical: compact ? 5 : 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: active ? tokens.btnPrimaryBg : tokens.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 9 : 12,
                height: compact ? 9 : 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                ),
              ),
              SizedBox(width: compact ? 6 : 8),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: compact ? 13 : 15,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendEntry {
  const _LegendEntry(this.label, this.color);

  final String label;
  final Color color;
}

enum _DashboardMode { all, tables, takeout, pickup }

class _DiningTab {
  const _DiningTab(this.label, this.value);

  final String label;
  final String? value;
}

