import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/cashier_operation_audit.dart';
import '../../../core/network_status_monitor.dart';
import '../../../core/shop_summary.dart';
import '../../auth/data/access_approval_repository.dart';
import '../../auth/data/cashier_account_storage.dart';
import '../../cashier_bills/data/real_cashier_bill_repository.dart';
import '../../cashier_bills/domain/cashier_bill.dart';
import '../../cashier_bills/presentation/cashier_bill_page.dart';
import '../../cashier_catalog/data/real_cashier_catalog_repository.dart';
import '../../cashier_catalog/presentation/cashier_dish_status_page.dart';
import '../../cashier_member/data/real_cashier_member_repository.dart';
import '../../cashier_member/presentation/cashier_member_page.dart';
import '../../cashier_payment/data/real_cashier_payment_repository.dart';
import '../../cashier_settings/data/real_cashier_settings_repository.dart';
import '../../cashier_settings/domain/cashier_settings.dart';
import '../../cashier_settings/presentation/cashier_management_hub_page.dart';
import '../../cashier_settings/presentation/cashier_settings_page.dart';
import '../../kds_local/runtime/cashier_kds_runtime.dart';
import '../../cashier_shift/data/real_cashier_shift_repository.dart';
import '../../cashier_shift/presentation/cashier_shift_page.dart';
import '../../pos/data/real_pos_repository.dart';
import '../../pos/presentation/pos_notice_dialog.dart';
import '../../pos/presentation/table_order_page.dart';
import '../../pos/presentation/hang_order_pool_dialog.dart';
import '../../pos/domain/hang_order_models.dart';
import '../../tables/data/real_table_repository.dart';
import '../../tables/domain/dining_table.dart';
import '../../tables/domain/takeout_dispatch_alert.dart';
import '../../tables/presentation/fulfillment_order_detail_dialog.dart';
import '../../tables/presentation/table_overview_page.dart';
import 'cashier_account_switch_dialog.dart';
import 'cashier_approval_dialog.dart';
import 'cashier_change_password_dialog.dart';
import 'cashier_shell.dart';
import 'cashier_tokens.dart';
import '../../mobile/responsive/breakpoints.dart';
import '../../version_upgrade/data/app_version_service.dart';
import '../../version_upgrade/presentation/version_upgrade_dialog.dart';

class CashierWorkspace extends StatefulWidget {
  const CashierWorkspace({
    super.key,
    required this.client,
    required this.permissions,
    this.isSuperAdmin = false,
    required this.shops,
    required this.currentShopId,
    required this.storeName,
    required this.onShopChanged,
    required this.onLogout,
    this.accountStorage,
    this.onSwitchAccount,
    required this.onTableSelected,
    required this.onPickupOrder,
    required this.kdsAvailable,
    this.currentAccount,
    this.currentWorkNo,
    this.currentRealName,
    this.currentJobTitle,
    this.currentDisplayName,
    this.themeMode = ThemeMode.light,
    this.onThemeModeChanged,
    this.onOpenKdsDiagnostics,
    this.networkMonitor,
    this.tableRefreshEvents,
    this.takeoutDispatchAlerts,
    this.kdsRuntime,
  });

  final AdminApiClient client;
  final Set<String> permissions;
  final bool isSuperAdmin;
  final List<ShopSummary> shops;
  final int? currentShopId;
  final String? currentAccount;
  final String? currentWorkNo;
  final String? currentRealName;
  final String? currentJobTitle;
  final String? currentDisplayName;
  final String storeName;
  final ValueChanged<int> onShopChanged;
  final VoidCallback onLogout;

  /// 历史账号存储（登录页「记住工号」共用）；为空时内部创建默认实例。
  final CashierAccountStorage? accountStorage;

  /// 切换账号回调：选中目标工号后由宿主退出当前会话并跳转登录页预填；
  /// 为 null 时不展示「切换账号」入口。
  final ValueChanged<String>? onSwitchAccount;
  final Future<void> Function(DiningTable table) onTableSelected;
  final Future<void> Function() onPickupOrder;
  final bool kdsAvailable;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;
  final VoidCallback? onOpenKdsDiagnostics;

  /// 云端连通性监测；为空时不监测（测试环境），保持“已联网”展示。
  final NetworkStatusMonitor? networkMonitor;
  final Stream<void>? tableRefreshEvents;
  final Stream<TakeoutDispatchAlert>? takeoutDispatchAlerts;
  final CashierKdsRuntime? kdsRuntime;

  @override
  State<CashierWorkspace> createState() => _CashierWorkspaceState();
}

class _CashierWorkspaceState extends State<CashierWorkspace> {
  late RealTableRepository _tableRepository;
  late RealCashierBillRepository _billRepository;
  late RealCashierMemberRepository _memberRepository;
  late RealCashierCatalogRepository _catalogRepository;
  late RealCashierShiftRepository _shiftRepository;
  late RealCashierSettingsRepository _settingsRepository;
  late RealPosRepository _posRepository;
  late RealCashierPaymentRepository _paymentRepository;

  /// 切换账号用的历史账号存储；懒加载，避免未启用切换时创建。
  CashierAccountStorage? _switchAccountStorage;
  CashierAccountStorage get _accountStorageForSwitch =>
      _switchAccountStorage ??=
          widget.accountStorage ?? CashierAccountStorage();

  CashierSection currentSection = CashierSection.table;
  final List<CashierSection> _visitedSections = [CashierSection.table];
  final Map<CashierSection, int> _refreshVersions = {};
  Timer? _clockTimer;
  DateTime _now = DateTime.now();
  CashierBill? _memberOrder;
  CashierBusinessSettings? _business;
  bool _businessLoading = false;
  bool _sidebarCollapsed = false;
  bool _online = true;
  DateTime? _lastBackPressTime;
  int _hangOrderCount = 0;
  int _fulfillmentCount = 0;
  String? _billInitialOrderNo;
  bool _billAutoOpenRefund = false;
  StreamSubscription? _tableRefreshSubscription;
  StreamSubscription? _takeoutDispatchSubscription;

  void _onNetworkChanged() {
    final monitor = widget.networkMonitor;
    if (monitor == null || !mounted) return;
    final wasOnline = _online;
    setState(() => _online = monitor.online);
    // 网络恢复后刷新营业状态，避免离线期间的变更滞留
    if (monitor.online && !wasOnline) {
      _loadBusinessStatus(silent: true);
      _loadHangOrderCount();
      _loadFulfillmentCount();
    }
  }

  Set<CashierSection> get _visibleSections => {
    CashierSection.table,
    CashierSection.ordering,
    if (widget.permissions.contains('cashier:operate')) CashierSection.bills,
    if (widget.permissions.contains('user:view')) CashierSection.members,
    if (widget.permissions.contains('dish:manage')) CashierSection.dishStatus,
    if (widget.permissions.contains('cashier:operate')) CashierSection.shift,
    if (widget.permissions.contains('cashier:operate') &&
        widget.permissions.contains('order:view') &&
        widget.permissions.contains('order:operate')) ...[
      CashierSection.manage,
      CashierSection.settings,
    ],
  };

  @override
  void initState() {
    super.initState();
    _online = widget.networkMonitor?.online ?? true;
    widget.networkMonitor?.addListener(_onNetworkChanged);
    _createRepositories();
    _loadBusinessStatus();
    _loadHangOrderCount();
    _loadFulfillmentCount();
    _checkAppVersionSilently();
    _tableRefreshSubscription = widget.tableRefreshEvents?.listen((_) {
      _loadFulfillmentCount();
    });
    _subscribeTakeoutDispatchAlerts();
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
        // 营业状态可能被后台/小程序/其他收银端修改，周期静默刷新保持实时
        _loadBusinessStatus(silent: true);
        _loadHangOrderCount();
        _loadFulfillmentCount();
      }
    });
  }

  Future<void> _checkAppVersionSilently() async {
    try {
      final service = AppVersionService(client: widget.client);
      final info = await service.checkUpdate(shopId: widget.currentShopId);
      if (!mounted) return;
      if (info.hasUpdate && info.isForceUpdate) {
        await showVersionUpgradeDialog(
          context,
          info: info,
          service: service,
        );
      }
    } catch (_) {
      // 静默预检不阻断日常收银流程
    }
  }

  @override
  void didUpdateWidget(covariant CashierWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.networkMonitor != widget.networkMonitor) {
      oldWidget.networkMonitor?.removeListener(_onNetworkChanged);
      widget.networkMonitor?.addListener(_onNetworkChanged);
      _online = widget.networkMonitor?.online ?? true;
    }
    if (oldWidget.tableRefreshEvents != widget.tableRefreshEvents) {
      _tableRefreshSubscription?.cancel();
      _tableRefreshSubscription = widget.tableRefreshEvents?.listen((_) {
        _loadFulfillmentCount();
      });
    }
    if (oldWidget.takeoutDispatchAlerts != widget.takeoutDispatchAlerts) {
      _subscribeTakeoutDispatchAlerts();
    }
    final shopChanged = oldWidget.currentShopId != widget.currentShopId;
    final tokenChanged = oldWidget.client.token != widget.client.token;
    if (!_visibleSections.contains(currentSection)) {
      currentSection = CashierSection.table;
    }
    // 门店切换或快速切换账号（token更换）时，重建 repository 并原地刷新当前页
    if (shopChanged || tokenChanged) {
      _rebindForShopChange();
    }
  }

  bool _isAlertForCurrentShop(TakeoutDispatchAlert alert) {
    final currentShopId = widget.currentShopId;
    if (currentShopId == null || currentShopId <= 0) return true;
    return alert.shopId <= 0 || alert.shopId == currentShopId;
  }

  Stream<TakeoutDispatchAlert>? get _scopedTakeoutDispatchAlerts =>
      widget.takeoutDispatchAlerts?.where(_isAlertForCurrentShop);

  void _subscribeTakeoutDispatchAlerts() {
    _takeoutDispatchSubscription?.cancel();
    _takeoutDispatchSubscription =
        widget.takeoutDispatchAlerts?.listen((alert) {
          if (_isAlertForCurrentShop(alert)) {
            _loadFulfillmentCount();
          }
        });
  }

  /// 门店切换后原地刷新数据，不销毁工作区、不跳回首页：
  /// 重建绑定新门店的 repository，并把当前页面强制以新门店数据重建
  /// （KeyedSubtree 版本号 +1 → 页面 State 重建 → initState 重新拉取）。
  void _rebindForShopChange() {
    _createRepositories();
    _memberOrder = null;
    setState(() {
      _hangOrderCount = 0;
      _fulfillmentCount = 0;
      _visitedSections
        ..clear()
        ..add(currentSection);
      for (final section in CashierSection.values) {
        _refreshVersions[section] = (_refreshVersions[section] ?? 0) + 1;
      }
    });
    _loadBusinessStatus(silent: true);
    _loadHangOrderCount();
    _loadFulfillmentCount();
  }

  @override
  void dispose() {
    widget.networkMonitor?.removeListener(_onNetworkChanged);
    _clockTimer?.cancel();
    _tableRefreshSubscription?.cancel();
    _takeoutDispatchSubscription?.cancel();
    super.dispose();
  }

  void _createRepositories() {
    _tableRepository = RealTableRepository(widget.client);
    _billRepository = RealCashierBillRepository(widget.client);
    _memberRepository = RealCashierMemberRepository(widget.client);
    _catalogRepository = RealCashierCatalogRepository(widget.client);
    _shiftRepository = RealCashierShiftRepository(widget.client);
    _settingsRepository = RealCashierSettingsRepository(widget.client);
    _posRepository = RealPosRepository(widget.client);
    _paymentRepository = RealCashierPaymentRepository(widget.client);
  }

  Future<void> _loadBusinessStatus({bool silent = false}) async {
    if (!widget.permissions.contains('order:view')) return;
    if (!silent) setState(() => _businessLoading = true);
    try {
      final business = await _settingsRepository.loadBusinessSettings();
      if (mounted) setState(() => _business = business);
    } catch (_) {
      // 顶部保留“状态未知”，避免网络波动阻塞收银主流程。
    } finally {
      if (mounted && !silent) setState(() => _businessLoading = false);
    }
  }

  Future<bool> _checkoutFulfillmentOrder(FulfillmentOrderDetail detail) async {
    final orderNo = detail.order.orderNo.trim();
    if (orderNo.isEmpty) {
      await showPosNotice(
        context,
        title: '暂时无法结账',
        message: '该订单没有有效订单编号，请刷新后重试。',
        tone: PosNoticeTone.warning,
      );
      return false;
    }
    try {
      final repository = _posRepository;
      final workspace = await repository.loadFulfillmentCheckoutWorkspace(
        detail,
      );
      if (!mounted) return false;
      final title = detail.order.type == FulfillmentType.takeout
          ? '外卖 ${detail.order.displayCode}'
          : '自提 ${detail.order.displayCode}';
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (routeContext) => _buildShellForPushedRoute(
            routeContext: routeContext,
            section: CashierSection.table,
            body: TableOrderPage(
              table: workspace.table,
              repository: repository,
              approvalRepository: AccessApprovalRepository(widget.client),
              shiftRepository: _shiftRepository,
              initialWorkspace: workspace,
              initiallyOpened: true,
              pickupOrder: true,
              checkoutOnly: true,
              fulfillmentTitle: title,
              currentAccount: widget.currentWorkNo?.isNotEmpty == true
                  ? widget.currentWorkNo
                  : widget.currentAccount,
              onLogout: widget.onLogout,
            ),
          ),
        ),
      );
      return completed == true;
    } catch (error) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '订单结账失败',
          message: _errorMessage(error),
          tone: PosNoticeTone.error,
        );
      }
      return false;
    }
  }

  Future<void> _toggleBusiness() async {
    if (_businessLoading ||
        _business == null ||
        !widget.permissions.contains('order:config')) {
      return;
    }
    final nextOpen = !_business!.isOpen;
    final confirmed = await showPosNotice(
      context,
      title: nextOpen ? '开启营业' : '关闭营业',
      message: nextOpen
          ? '确认开启 ${widget.storeName} 营业并恢复接单吗？'
          : '关闭后门店将暂停接收新订单，确认关闭营业吗？',
      tone: nextOpen ? PosNoticeTone.info : PosNoticeTone.warning,
      primaryLabel: '确认',
      secondaryLabel: '取消',
    );
    if (!confirmed || !mounted) return;
    setState(() => _businessLoading = true);
    try {
      final business = await _settingsRepository.changeBusinessStatus(nextOpen);
      if (mounted) setState(() => _business = business);
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'shop',
          action: nextOpen ? 'business_open' : 'business_close',
          result: 'success',
          detail: {'forced': false},
        ),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'shop',
          action: nextOpen ? 'business_open' : 'business_close',
          result: 'failed',
          errorCode: '${error.code}',
          errorMsg: error.message,
        ),
      );
      // v1.2.219 强制班次/日结流程：4000 关门拦截 / 4001 开门拦截 → 引导 + 老板逃生
      if (error.code == 4000 || error.code == 4001) {
        // 先复位 loading：拦截弹窗等待期间按钮不可处于转圈态（否则动画悬挂）
        setState(() => _businessLoading = false);
        await _handleBusinessBlocked(nextOpen, error);
      } else {
        await showPosNotice(
          context,
          title: '营业状态修改失败',
          message: _errorMessage(error),
          tone: PosNoticeTone.error,
        );
      }
    } catch (error) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '营业状态修改失败',
        message: _errorMessage(error),
        tone: PosNoticeTone.error,
      );
    } finally {
      if (mounted) setState(() => _businessLoading = false);
    }
  }

  /// v1.2.219 强制流程拦截：提示先开班 / 交班 / 日结；
  /// 当前账号具备 admin:manage 时提供 force=1 逃生入口（服务端写安全审计）。
  Future<void> _handleBusinessBlocked(bool nextOpen, ApiException error) async {
    final canForce = widget.permissions.contains('admin:manage');
    final open = nextOpen;
    final title = open ? '无法营业' : '无法打烊';
    final detail = _errorMessage(error);

    if (error.code == 4001) {
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.calendar_month_outlined, color: Color(0xFFF59E0B), size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '无法开启营业：前一营业日尚未日结',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            '系统检测到前一营业日仍有未完成的日结封账，为保障财务账目连贯，请先完成前日日结。'
            '${detail.isNotEmpty ? '\n\n$detail' : ''}',
            style: const TextStyle(fontSize: 15, height: 1.5),
          ),
          actions: [
            OutlinedButton(
              key: const Key('daily-block-force-open-button'),
              onPressed: () => Navigator.of(ctx).pop('force'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD97706),
                side: const BorderSide(color: Color(0xFFD97706)),
              ),
              child: const Text('紧急强制开门 (需主管权限)'),
            ),
            FilledButton(
              key: const Key('daily-block-go-settle-button'),
              onPressed: () => Navigator.of(ctx).pop('settle'),
              child: const Text('立即前往日结'),
            ),
          ],
        ),
      );
      if (choice == 'settle') {
        _selectSection(CashierSection.shift);
        return;
      }
      if (choice == 'force') {
        bool authPassed = canForce;
        if (!authPassed) {
          final grant = await showCashierApprovalDialog(
            context,
            request: const CashierApprovalRequest(
              title: '紧急强制开门',
              permission: 'order:config',
              permissionLabel: '强制开启营业',
              requiredRoles: '需店长或主管现场授权',
              hint: '前一营业日未日结，紧急强制跳过日结校验开门营业',
            ),
            repository: AccessApprovalRepository(widget.client),
            currentAccount: widget.currentAccount,
          );
          authPassed = grant != null;
        }
        if (!authPassed || !mounted) return;
        setState(() => _businessLoading = true);
        try {
          final business = await _settingsRepository.changeBusinessStatus(
            true,
            force: true,
          );
          if (mounted) setState(() => _business = business);
          CashierOperationAuditStore.instance.record(
            const CashierOperationAuditDraft(
              module: 'shop',
              action: 'business_open',
              result: 'success',
              detail: {'forced': true, 'reason': '4001_daily_settlement_bypass'},
            ),
          );
        } catch (e) {
          if (mounted) {
            await showPosNotice(
              context,
              title: '营业状态修改失败',
              message: _errorMessage(e),
              tone: PosNoticeTone.error,
            );
          }
        } finally {
          if (mounted) setState(() => _businessLoading = false);
        }
      }
      return;
    }

    if (!canForce) {
      await showPosNotice(
        context,
        title: title,
        message: open ? '$detail\n请先完成开班后再开启营业。' : '$detail\n请先完成交班 / 日结后再打烊。',
        tone: PosNoticeTone.warning,
      );
      return;
    }
    final forced = await showPosNotice(
      context,
      title: title,
      message: '$detail\n\n可强制${open ? '营业' : '打烊'}跳过校验（将写入安全审计日志），是否继续？',
      tone: PosNoticeTone.warning,
      primaryLabel: open ? '强制营业' : '强制打烊',
      secondaryLabel: '取消',
    );
    if (!forced || !mounted) return;
    setState(() => _businessLoading = true);
    try {
      final business = await _settingsRepository.changeBusinessStatus(
        nextOpen,
        force: true,
      );
      if (mounted) setState(() => _business = business);
      CashierOperationAuditStore.instance.record(
        CashierOperationAuditDraft(
          module: 'shop',
          action: nextOpen ? 'business_open' : 'business_close',
          result: 'success',
          detail: {'forced': true},
        ),
      );
    } catch (error) {
      if (mounted) {
        await showPosNotice(
          context,
          title: '营业状态修改失败',
          message: _errorMessage(error),
          tone: PosNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _businessLoading = false);
    }
  }

  void _selectSection(CashierSection section) {
    if (!_visibleSections.contains(section)) return;
    final refreshCurrent = currentSection == section;
    setState(() {
      currentSection = section;
      if (!_visitedSections.contains(section)) _visitedSections.add(section);
      if (refreshCurrent) {
        _refreshVersions[section] = (_refreshVersions[section] ?? 0) + 1;
      }
    });
    if (refreshCurrent) {
      _loadBusinessStatus(silent: true);
    }
  }

  Future<void> _resumeBill(CashierBill bill) async {
    final overview = await _tableRepository.loadTableOverview();
    DiningTable? target;
    for (final table in overview.tables) {
      if (table.number == bill.tableNumber) {
        target = table;
        break;
      }
    }
    if (target == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未找到 ${bill.tableNumber}号桌，请到点餐页重新刷新')),
        );
      }
      return;
    }
    await widget.onTableSelected(target);
  }

  Future<bool> _showStoreClosedOrderGuard() async {
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 28),
            SizedBox(width: 10),
            Text(
              '门店暂未营业',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          '当前门店处于打烊状态，请先开启营业再进行点餐开台。',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        actions: [
          OutlinedButton(
            key: const Key('closed-guard-force-button'),
            onPressed: () => Navigator.of(ctx).pop('force'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFD97706),
              side: const BorderSide(color: Color(0xFFD97706)),
            ),
            child: const Text('店长特权开单 (Force)'),
          ),
          FilledButton(
            key: const Key('closed-guard-open-business-button'),
            onPressed: () => Navigator.of(ctx).pop('open'),
            child: const Text('前往开启营业'),
          ),
        ],
      ),
    );
    if (choice == 'open') {
      unawaited(_toggleBusiness());
      return false;
    }
    if (choice == 'force') {
      final canDirectForce = widget.permissions.contains('admin:manage') ||
          widget.permissions.contains('order:manage');
      if (canDirectForce) return true;
      final grant = await showCashierApprovalDialog(
        context,
        request: const CashierApprovalRequest(
          title: '店长特权开单',
          permission: 'order:operate',
          permissionLabel: '未营业开单特权',
          requiredRoles: '需店长或主管现场授权',
        ),
        repository: AccessApprovalRepository(widget.client),
        currentAccount: widget.currentAccount,
      );
      return grant != null;
    }
    return false;
  }

  Future<void> _handleTableSelected(DiningTable table) async {
    if (_business?.isOpen == false) {
      final allowed = await _showStoreClosedOrderGuard();
      if (!allowed || !mounted) return;
    }
    await widget.onTableSelected(table);
  }

  Future<void> _handlePickupOrder() async {
    if (_business?.isOpen == false) {
      final allowed = await _showStoreClosedOrderGuard();
      if (!allowed || !mounted) return;
    }
    await widget.onPickupOrder();
  }

  Future<void> _loadHangOrderCount() async {
    if (!widget.permissions.contains('cashier:operate')) return;
    final requestShopId = widget.currentShopId;
    final repo = _posRepository;
    try {
      final list = await repo.getHangList();
      if (!mounted ||
          widget.currentShopId != requestShopId ||
          !identical(_posRepository, repo)) {
        return;
      }
      setState(() => _hangOrderCount = list.length);
    } catch (_) {
      // 轮询异常静默忽略
    }
  }

  Future<void> _loadFulfillmentCount() async {
    final requestShopId = widget.currentShopId;
    final repo = _tableRepository;
    try {
      final overview = await repo.loadFulfillmentOverview();
      if (!mounted ||
          widget.currentShopId != requestShopId ||
          !identical(_tableRepository, repo)) {
        return;
      }
      bool belongsToShop(FulfillmentOrder o) =>
          requestShopId == null ||
          requestShopId <= 0 ||
          o.shopId == null ||
          o.shopId == requestShopId;
      final uncompletedCount = overview.takeoutOrders
              .where((o) => o.status.isActive && belongsToShop(o))
              .length +
          overview.pickupOrders
              .where((o) => o.status.isActive && belongsToShop(o))
              .length;
      setState(() => _fulfillmentCount = uncompletedCount);
    } catch (_) {
      // 轮询异常静默忽略
    }
  }

  Future<void> _openHangOrderPool() async {
    await showHangOrderPoolDialog(
      context,
      repository: _posRepository,
      onUnhangOrder: (item) async {
        unawaited(_loadHangOrderCount());
        await _handleUnhangNavigation(item);
      },
    );
    unawaited(_loadHangOrderCount());
  }

  void _navigateToBillRefund(String orderNo) {
    setState(() {
      _billInitialOrderNo = orderNo;
      _billAutoOpenRefund = true;
      _selectSection(CashierSection.bills);
    });
  }

  Future<void> _openFulfillmentDispatchDrawer() async {
    await showFulfillmentDispatchDialog(
      context: context,
      repository: _tableRepository,
      canUpdate: widget.permissions.contains('order:operate'),
      defaultAccount: widget.currentWorkNo?.isNotEmpty == true
          ? widget.currentWorkNo
          : widget.currentAccount,
      onCheckout: _checkoutFulfillmentOrder,
      onManualRefund: (order, {amount, reason, account, password}) =>
          _posRepository.manualRefund(
            orderNo: order.orderNo,
            refundAmount: amount,
            reason: reason,
            account: account,
            password: password,
          ),
      onNavigateToBillRefund: _navigateToBillRefund,
      dispatchAlerts: _scopedTakeoutDispatchAlerts,
    );
    unawaited(_loadFulfillmentCount());
  }

  Future<void> _handleUnhangNavigation(HangOrderSummary item) async {
    final table = DiningTable(
      id: item.orderId,
      number: item.tableNumber.isNotEmpty ? item.tableNumber : '外带单',
      status: TableStatus.pending,
      people: item.numberOfDiners,
      amount: item.settAmount,
    );
    if (mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (routeContext) => _buildShellForPushedRoute(
            routeContext: routeContext,
            section: CashierSection.table,
            body: TableOrderPage(
              table: table,
              initiallyOpened: true,
              checkoutOnly: true,
              repository: _posRepository,
              approvalRepository: AccessApprovalRepository(widget.client),
              shiftRepository: _shiftRepository,
              memberRepository: _memberRepository,
              currentAccount: widget.currentWorkNo?.isNotEmpty == true
                  ? widget.currentWorkNo
                  : widget.currentAccount,
              onLogout: widget.onLogout,
            ),
          ),
        ),
      );
      unawaited(_loadHangOrderCount());
    }
  }

  Widget _buildShellForPushedRoute({
    required BuildContext routeContext,
    required CashierSection section,
    required Widget body,
    bool showSidebar = false,
  }) {
    return CashierShell(
      currentSection: section,
      showSidebar: showSidebar,
      bodyPadding: EdgeInsets.zero,
      onSectionChanged: (s) {
        if (Navigator.of(routeContext).canPop()) {
          Navigator.of(routeContext).pop();
        }
        _selectSection(s);
      },
      visibleSections: _visibleSections,
      connectionText: _online ? '云端在线 (12ms)' : '云端离线',
      connected: _online,
      kdsAvailable: widget.kdsAvailable,
      collapsed: _sidebarCollapsed,
      onToggleCollapse: () =>
          setState(() => _sidebarCollapsed = !_sidebarCollapsed),
      storeText: widget.storeName,
      storeTitle: widget.shops.length > 1
          ? _ShopPicker(
              shops: widget.shops,
              currentShopId: widget.currentShopId,
              onChanged: widget.onShopChanged,
            )
          : null,
      cashierName: widget.currentRealName?.isNotEmpty == true
          ? widget.currentRealName
          : (widget.currentDisplayName?.isNotEmpty == true
              ? widget.currentDisplayName
              : (widget.currentAccount ?? '张晓峰')),
      cashierWorkNo: widget.currentWorkNo?.isNotEmpty == true
          ? widget.currentWorkNo
          : '0801',
      hangOrderCount: _hangOrderCount,
      fulfillmentCount: _fulfillmentCount,
      isDarkMode: Theme.of(context).brightness == Brightness.dark,
      onToggleTheme: () {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        widget.onThemeModeChanged?.call(
          isDark ? ThemeMode.light : ThemeMode.dark,
        );
      },
      onOpenHangPool: _openHangOrderPool,
      onOpenFulfillment: _openFulfillmentDispatchDrawer,
      onSwitchAccount: _handleSwitchAccount,
      onOpenProfile: _showIdentityDialog,
      onLogout: widget.onLogout,
      leadingActions: [
        _BusinessSwitchButton(
          isOpen: _business?.isOpen,
          loading: _businessLoading,
          canChange: widget.permissions.contains('order:config'),
          onPressed: _toggleBusiness,
        ),
      ],
      timeText: _formatClock(_now),
      dateText: _formatDate(_now),
      body: body,
    );
  }

  Widget _buildPage(CashierSection section) => switch (section) {
    CashierSection.table => _buildTableOverviewPage(),
    CashierSection.ordering => _buildDirectOrderingPage(),
    CashierSection.bills => _buildBillsPage(),
    CashierSection.members => _buildMembersPage(),
    CashierSection.dishStatus => _buildDishStatusPage(),
    CashierSection.shift => _buildShiftPage(),
    CashierSection.manage => _buildManagementHubPage(),
    CashierSection.settings => _buildSettingsPage(),
  };

  Widget _buildTableOverviewPage() => TableOverviewPage(
    repository: _tableRepository,
    initialTab: 1,
    currentAccount: widget.currentWorkNo?.isNotEmpty == true
        ? widget.currentWorkNo
        : widget.currentAccount,
    showSidebar: false,
    onTableSelected: _handleTableSelected,
    onClearTable: (table) => _posRepository.clearTable(table.number),
    onPickupOrder: _handlePickupOrder,
    onFulfillmentCheckout: _checkoutFulfillmentOrder,
    onManualRefund: (order, {amount, reason, account, password}) =>
        _posRepository.manualRefund(
          orderNo: order.orderNo,
          refundAmount: amount,
          reason: reason,
          account: account,
          password: password,
        ),
    onNavigateToBillRefund: _navigateToBillRefund,
    canViewFulfillment: widget.permissions.contains('order:view'),
    canUpdateFulfillment: widget.permissions.contains('order:operate'),
    canManageTable: widget.permissions.contains('table:manage'),
    refreshEvents: widget.tableRefreshEvents,
    dispatchAlerts: _scopedTakeoutDispatchAlerts,
    onOpenHangPool: _openHangOrderPool,
    hangOrderCount: _hangOrderCount,
  );

  Widget _buildDirectOrderingPage() => TableOrderPage(
    key: const ValueKey('cashier_direct_ordering'),
    table: const DiningTable(
      number: '',
      status: TableStatus.empty,
      people: 0,
    ),
    initiallyOpened: true,
    repository: _posRepository,
    tableRepository: _tableRepository,
    approvalRepository: AccessApprovalRepository(widget.client),
    shiftRepository: _shiftRepository,
    memberRepository: _memberRepository,
    currentAccount: widget.currentWorkNo?.isNotEmpty == true
        ? widget.currentWorkNo
        : widget.currentAccount,
    onLogout: widget.onLogout,
    onBack: () => _selectSection(CashierSection.table),
  );

  Widget _buildBillsPage() => CashierBillPage(
    key: ValueKey('bills_${_billInitialOrderNo ?? ""}_${_refreshVersions[CashierSection.bills] ?? 0}'),
    repository: _billRepository,
    approvalRepository: AccessApprovalRepository(widget.client),
    memberRepository: _memberRepository,
    onResumeTable: _resumeBill,
    canBindMember:
        widget.permissions.contains('user:view') &&
        widget.permissions.contains('order:operate'),
    canViewDetails: widget.permissions.contains('order:view'),
    permissions: widget.permissions,
    isSuperAdmin: widget.isSuperAdmin,
    initialOrderNo: _billInitialOrderNo,
    autoOpenRefund: _billAutoOpenRefund,
    onRefundHandled: () {
      _billAutoOpenRefund = false;
    },
    currentAccount: widget.currentWorkNo?.isNotEmpty == true
        ? widget.currentWorkNo
        : widget.currentAccount,
  );

  Widget _buildMembersPage() => CashierMemberPage(
    key: ValueKey(_memberOrder?.id),
    repository: _memberRepository,
    approvalRepository: AccessApprovalRepository(widget.client),
    permissions: widget.permissions,
    isSuperAdmin: widget.isSuperAdmin,
    currentAccount: widget.currentWorkNo?.isNotEmpty == true
        ? widget.currentWorkNo
        : widget.currentAccount,
    canRecharge: widget.permissions.contains('user:points'),
    canBindOrder:
        _memberOrder != null && widget.permissions.contains('order:operate'),
    currentOrderId: _memberOrder?.id,
    currentOrderNo: _memberOrder?.orderNo,
    currentTableNumber: _memberOrder?.tableNumber,
    currentOrderStatus: _memberOrder?.status.apiValue,
  );

  Widget _buildDishStatusPage() => CashierDishStatusPage(
    repository: _catalogRepository,
    canManage: widget.permissions.contains('dish:manage'),
  );

  Widget _buildShiftPage() => CashierShiftPage(
    repository: _shiftRepository,
    canViewReport: widget.permissions.contains('report:view'),
    canSettleDaily: widget.permissions.contains('daily:settle'),
    shopId: widget.currentShopId,
    currentAccount: widget.currentWorkNo?.isNotEmpty == true
        ? widget.currentWorkNo
        : widget.currentAccount,
  );

  Widget _buildManagementHubPage() => CashierManagementHubPage(
    repository: _settingsRepository,
    paymentRepository: _paymentRepository,
    storeName: widget.storeName,
    kdsAvailable: widget.kdsAvailable,
    client: widget.client,
    permissions: widget.permissions,
    currentShopId: widget.currentShopId,
    onPasswordChanged: widget.onLogout,
    onOpenKdsDiagnostics: widget.onOpenKdsDiagnostics,
    kdsRuntime: widget.kdsRuntime,
  );

  Widget _buildSettingsPage() => CashierSettingsPage(
    repository: _settingsRepository,
    paymentRepository: _paymentRepository,
    storeName: widget.storeName,
    kdsAvailable: widget.kdsAvailable,
    client: widget.client,
    permissions: widget.permissions,
    currentShopId: widget.currentShopId,
    onPasswordChanged: widget.onLogout,
    onOpenKdsDiagnostics: widget.onOpenKdsDiagnostics,
    kdsRuntime: widget.kdsRuntime,
  );

  Widget _body() => Stack(
    children: [
      for (final section in _visitedSections)
        Positioned.fill(
          child: Offstage(
            offstage: section != currentSection,
            child: TickerMode(
              enabled: section == currentSection,
              child: KeyedSubtree(
                key: ValueKey((section, _refreshVersions[section] ?? 0)),
                child: _buildPage(section),
              ),
            ),
          ),
        ),
    ],
  );

  Future<void> _handleSwitchAccount() async {
    if (widget.onSwitchAccount == null) {
      widget.onLogout();
      return;
    }
    final savedAccounts = await _accountStorageForSwitch.getSavedAccounts();
    if (!mounted) return;
    final target = await showCashierAccountSwitchDialog(
      context,
      savedAccounts: savedAccounts,
      currentWorkNo: widget.currentWorkNo ?? '',
    );
    if (target == null || target.isEmpty || !mounted) return;
    widget.onSwitchAccount!(target);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (currentSection != CashierSection.table) {
          _selectSection(CashierSection.table);
          return;
        }
        final now = DateTime.now();
        if (_lastBackPressTime == null ||
            now.difference(_lastBackPressTime!) > const Duration(seconds: 2)) {
          _lastBackPressTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('再按一次退出收银系统'),
              duration: Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
          return;
        }
        unawaited(SystemNavigator.pop());
      },
      child: CashierShell(
        currentSection: currentSection,
        onSectionChanged: _selectSection,
        visibleSections: _visibleSections,
        connectionText: _online ? '云端在线 (12ms)' : '云端离线',
        connected: _online,
        kdsAvailable: widget.kdsAvailable,
        collapsed: _sidebarCollapsed,
        onToggleCollapse: () =>
            setState(() => _sidebarCollapsed = !_sidebarCollapsed),
        storeText: widget.storeName,
        storeTitle: widget.shops.length > 1
            ? _ShopPicker(
                shops: widget.shops,
                currentShopId: widget.currentShopId,
                onChanged: widget.onShopChanged,
              )
            : null,
        cashierName: widget.currentRealName?.isNotEmpty == true
            ? widget.currentRealName
            : (widget.currentDisplayName?.isNotEmpty == true
                ? widget.currentDisplayName
                : (widget.currentAccount ?? '张晓峰')),
        cashierWorkNo: widget.currentWorkNo?.isNotEmpty == true
            ? widget.currentWorkNo
            : '0801',
        hangOrderCount: _hangOrderCount,
        fulfillmentCount: _fulfillmentCount,
        isDarkMode: Theme.of(context).brightness == Brightness.dark,
        onToggleTheme: () {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          widget.onThemeModeChanged?.call(
            isDark ? ThemeMode.light : ThemeMode.dark,
          );
        },
        onOpenHangPool: _openHangOrderPool,
        onOpenFulfillment: _openFulfillmentDispatchDrawer,
        onSwitchAccount: _handleSwitchAccount,
        onOpenProfile: _showIdentityDialog,
        onLogout: widget.onLogout,
        leadingActions: [
          _BusinessSwitchButton(
            isOpen: _business?.isOpen,
            loading: _businessLoading,
            canChange: widget.permissions.contains('order:config'),
            onPressed: _toggleBusiness,
          ),
        ],
        topActions: const [],
        timeText: _formatClock(_now),
        dateText: _formatDate(_now),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() => _online
      ? _body()
      : Column(
          children: [
            _OfflineBanner(onRetry: () => widget.networkMonitor?.probeNow()),
            Expanded(child: _body()),
          ],
        );

  Future<void> _handleModifyPassword() async {
    final account = widget.currentDisplayName?.isNotEmpty == true
        ? widget.currentDisplayName
        : (widget.currentRealName?.isNotEmpty == true
            ? widget.currentRealName
            : (widget.currentAccount?.isNotEmpty == true
                ? widget.currentAccount
                : '操作员'));
    final changed = await showCashierChangePasswordDialog(
      context: context,
      client: widget.client,
      currentShopId: widget.currentShopId,
      accountName: account,
    );
    if (changed != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('密码修改成功，请使用新密码重新登录'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
    widget.onLogout();
  }

  Future<void> _showIdentityDialog() async {
    List<String> savedAccounts = const [];
    try {
      if (widget.onSwitchAccount != null) {
        savedAccounts = await _accountStorageForSwitch.getSavedAccounts();
      }
    } catch (_) {}
    if (!mounted) return;

    final displayName = widget.currentDisplayName?.isNotEmpty == true
        ? widget.currentDisplayName!
        : (widget.currentRealName?.isNotEmpty == true
            ? widget.currentRealName!
            : (widget.currentAccount?.isNotEmpty == true
                ? widget.currentAccount!
                : '操作员'));
    final realName = widget.currentRealName ?? '';
    final workNo = widget.currentWorkNo ?? '';
    final jobTitle = widget.currentJobTitle ?? '';

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        title: const Row(
          children: [
            CircleAvatar(
              backgroundColor: Color(0xfffff1ed),
              child: Icon(Icons.person, color: Color(0xffed3d08)),
            ),
            SizedBox(width: 12),
            Text('员工个人档案', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 20),
            _infoRow('员工姓名', realName.isNotEmpty ? realName : displayName),
            const SizedBox(height: 8),
            _infoRow('员工工号', workNo.isNotEmpty ? workNo : '未分配工号'),
            const SizedBox(height: 8),
            _infoRow('当前岗位', jobTitle.isNotEmpty ? jobTitle : '员工'),
            const SizedBox(height: 8),
            _infoRow('所属门店', widget.storeName),
            const Divider(height: 24),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('关 闭'),
          ),
          OutlinedButton.icon(
            key: const Key('cashier-profile-modify-password'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xffed3d08),
              side: const BorderSide(color: Color(0xffffd0c2)),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              _handleModifyPassword();
            },
            icon: const Icon(Icons.lock_reset_rounded, size: 18),
            label: const Text('修改密码'),
          ),
          if (widget.onSwitchAccount != null)
            OutlinedButton.icon(
              key: const Key('cashier-profile-switch-account'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xffed3d08),
                side: const BorderSide(color: Color(0xffffd0c2)),
              ),
              onPressed: () async {
                Navigator.of(dialogCtx).pop();
                if (!mounted) return;
                final target = await showCashierAccountSwitchDialog(
                  context,
                  savedAccounts: savedAccounts,
                  currentWorkNo: workNo,
                );
                if (target == null || target.isEmpty || !mounted) return;
                widget.onSwitchAccount!(target);
              },
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('切换账号'),
            ),
          FilledButton.icon(
            key: const Key('cashier-profile-logout'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xffef4444),
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              widget.onLogout();
            },
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('退出当前账号'),
          ),
        ],
      ),
    );
  }

  static Widget _infoRow(String label, String value) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xff848484), fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: Color(0xff2d2d2f),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShopPicker extends StatelessWidget {
  const _ShopPicker({
    required this.shops,
    required this.currentShopId,
    required this.onChanged,
  });

  final List<ShopSummary> shops;
  final int? currentShopId;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final uniqueShops = <int, ShopSummary>{};
    for (final s in shops) {
      if (s.id > 0) uniqueShops.putIfAbsent(s.id, () => s);
    }
    if (uniqueShops.isEmpty) return const SizedBox.shrink();

    final selectedId = uniqueShops.containsKey(currentShopId)
        ? currentShopId
        : uniqueShops.keys.first;

    final tokens = context.cashier;
    final isPhoneLandscape = context.isPhoneLandscape;
    final targetHeight = isPhoneLandscape ? 36.0 : 44.0;

    return Container(
      height: targetHeight,
      padding: EdgeInsets.symmetric(horizontal: isPhoneLandscape ? 10 : 12),
      decoration: BoxDecoration(
        color: tokens.subtle,
        border: Border.all(color: tokens.border, width: 1.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          key: const Key('cashier-shop-picker'),
          value: selectedId,
          icon: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              size: isPhoneLandscape ? 20 : 22,
              color: tokens.ink,
            ),
          ),
          borderRadius: BorderRadius.circular(8),
          dropdownColor: tokens.surface,
          selectedItemBuilder: (BuildContext context) {
            return uniqueShops.values.map<Widget>((shop) {
              final isSelected = shop.id == selectedId;
              return Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  shop.name,
                  key: isSelected ? const Key('cashier-brand-store-name') : null,
                  style: TextStyle(
                    color: tokens.ink,
                    fontSize: isPhoneLandscape ? 15 : 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList();
          },
          items: [
            for (final shop in uniqueShops.values)
              DropdownMenuItem(
                value: shop.id,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      size: isPhoneLandscape ? 16 : 18,
                      color: shop.id == selectedId ? tokens.ink : tokens.inkSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      shop.name,
                      style: TextStyle(
                        color: tokens.ink,
                        fontSize: isPhoneLandscape ? 13 : 15,
                        fontWeight: shop.id == selectedId ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                    if (shop.id == selectedId) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: tokens.ink,
                      ),
                    ],
                  ],
                ),
              ),
          ],
          onChanged: (value) {
            if (value != null && value != currentShopId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                onChanged(value);
              });
            }
          },
        ),
      ),
    );
  }
}

String _formatClock(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.hour)}:${two(value.minute)}';
}

String _formatDate(DateTime value) {
  const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${weekdays[value.weekday - 1]}';
}

String _errorMessage(Object error) {
  if (error is ApiException) return error.message;
  return '$error'.replaceFirst('Exception: ', '');
}

class _BusinessSwitchButton extends StatelessWidget {
  const _BusinessSwitchButton({
    required this.isOpen,
    required this.loading,
    required this.canChange,
    required this.onPressed,
  });

  final bool? isOpen;
  final bool loading;
  final bool canChange;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isPhoneLandscape = context.isPhoneLandscape;
    final targetHeight = isPhoneLandscape ? 36.0 : 44.0;

    final open = isOpen == true;
    final unknown = isOpen == null;
    final label = unknown
        ? '状态未知'
        : open
            ? '营业中'
            : '已关闭营业';

    final Color statusColor;
    final Color bgColor;
    final Color borderColor;

    if (unknown) {
      statusColor = tokens.inkMuted;
      bgColor = tokens.subtle;
      borderColor = tokens.border;
    } else if (open) {
      statusColor = isDark ? const Color(0xff34d399) : const Color(0xff059669);
      bgColor = const Color(0xff10b981).withValues(alpha: isDark ? 0.2 : 0.12);
      borderColor = const Color(0xff10b981).withValues(alpha: 0.8);
    } else {
      statusColor = isDark ? const Color(0xfff87171) : const Color(0xffdc2626);
      bgColor = const Color(0xffef4444).withValues(alpha: isDark ? 0.2 : 0.12);
      borderColor = const Color(0xffef4444).withValues(alpha: 0.8);
    }

    return Tooltip(
      message: canChange ? (open ? '点击关闭营业' : '点击开启营业') : '无营业设置权限',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('cashier-business-switch'),
          onTap: loading || !canChange || isOpen == null ? null : onPressed,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            height: targetHeight,
            padding: EdgeInsets.symmetric(horizontal: isPhoneLandscape ? 10 : 16),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: isPhoneLandscape ? 12 : 14,
                    height: isPhoneLandscape ? 12 : 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: tokens.ink,
                    ),
                  )
                else
                  Container(
                    width: isPhoneLandscape ? 8 : 10,
                    height: isPhoneLandscape ? 8 : 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: unknown
                          ? tokens.inkMuted
                          : open
                              ? const Color(0xff10b981)
                              : const Color(0xffef4444),
                      boxShadow: unknown
                          ? null
                          : [
                              BoxShadow(
                                color: (open
                                        ? const Color(0xff10b981)
                                        : const Color(0xffef4444))
                                    .withValues(alpha: 0.45),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                    ),
                  ),
                SizedBox(width: isPhoneLandscape ? 6 : 8),
                Text(
                  label,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: isPhoneLandscape ? 12 : 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
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

/// 断网持久横幅：网络恢复前常驻；提示云端功能暂不可用，
/// 本地收银与局域网 KDS 不受影响。点击立即重试。
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFB3261E),
      child: InkWell(
        key: const Key('cashier-offline-banner'),
        onTap: onRetry,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '网络连接已断开，正在自动重试… 云端下单/结账暂不可用，'
                  '本地收银与厨房 KDS 不受影响。点击立即重试。',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Icon(Icons.refresh_rounded, color: Colors.white, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

