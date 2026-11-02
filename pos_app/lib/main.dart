import 'dart:async';

import 'package:flutter/material.dart';

import 'src/core/admin_api_client.dart';
import 'src/core/app_state.dart';
import 'src/core/cashier_operation_audit.dart';
import 'src/core/crash_log.dart';
import 'src/core/display_mode.dart';
import 'src/core/http_transport.dart';
import 'src/core/network_status_monitor.dart';
import 'src/core/responsive_design_viewport.dart';
import 'src/core/terminal_device_service.dart';
import 'src/features/auth/data/access_approval_repository.dart';
import 'src/features/auth/data/auth_repository.dart';
import 'src/features/auth/data/cashier_account_storage.dart';
import 'src/features/auth/data/cashier_session_storage.dart';
import 'src/features/auth/domain/auth_models.dart';
import 'src/features/auth/presentation/cashier_login_page.dart';
import 'src/features/cashier_member/data/real_cashier_member_repository.dart';
import 'src/features/cashier_shell/presentation/cashier_account_password_dialog.dart';
import 'src/features/cashier_shell/presentation/cashier_app_theme.dart';
import 'src/features/cashier_shell/presentation/cashier_shell.dart';
import 'src/features/cashier_shell/presentation/cashier_workspace.dart';
import 'src/features/kds_local/runtime/cashier_kds_runtime.dart';
import 'src/features/kds_local/presentation/cashier_kds_diagnostics_page.dart';
import 'src/features/kds_local/sync/admin_api_cashier_kds_proxy_client.dart';
import 'src/features/mobile/app/mobile_app.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'src/features/cashier_shift/data/real_cashier_shift_repository.dart';
import 'src/features/pos/data/pos_repository.dart';
import 'src/features/pos/data/real_pos_repository.dart';
import 'src/features/pos/presentation/table_order_page.dart';
import 'src/features/tables/domain/dining_table.dart';
import 'src/features/tables/data/takeout_dispatch_alert_source.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      try {
        await CrashLog.instance.init();
      } catch (_) {
        // File logging is diagnostic only; KDS storage keeps its own fatal gate.
      }
      installGlobalErrorHandlers();
      await configurePreferredDisplay();
      if (kIsMobileApp) {
        runApp(const ProviderScope(child: MobileApp()));
        return;
      }
      CashierKdsRuntime? kdsRuntime;
      try {
        kdsRuntime = await CashierKdsRuntime.start();
        await CashierOperationAuditStore.instance.init();
      } catch (error, stackTrace) {
        CrashLog.instance.write(
          'WARN',
          'KDS 本地收银数据库启动异常，自动降级为纯内存安全模式: $error',
          stackTrace,
        );
        debugPrint(
          'KDS local db start failed, falling back to in-memory: $error',
        );
        try {
          kdsRuntime = await CashierKdsRuntime.start(inMemory: true);
          await CashierOperationAuditStore.instance.init();
        } catch (fallbackError, fallbackStack) {
          CrashLog.instance.write(
            'WARN',
            'KDS 内存模式降级亦未成功，进入无本地代理模式: $fallbackError',
            fallbackStack,
          );
          kdsRuntime = null;
        }
      }
      CrashLog.instance.write('INFO', '收银就绪，进入主界面');
      // 预热与初始化收银机全局终端标识，并与 KDS 设备编号对齐
      try {
        final terminalId =
            await TerminalDeviceService.instance.getOrInitializeTerminalId();
        if (kdsRuntime != null &&
            kdsRuntime.cashierDeviceCode.trim().isNotEmpty) {
          final deviceCode = kdsRuntime.cashierDeviceCode.trim();
          if (terminalId != deviceCode) {
            await TerminalDeviceService.instance.registerTerminalId(deviceCode);
          }
        }
      } catch (e) {
        CrashLog.instance.write('WARN', '收银终端设备标识初始化失败: $e');
      }
      if (kdsRuntime != null) {
        final runtime = kdsRuntime;
        CrashLog.instance.registerStateProvider(
          'kds',
          () => {
            'available': runtime.isAvailable,
            'device_code': runtime.cashierDeviceCode,
            'lan_port': runtime.lanPort,
            'lan_status': runtime.lanStatus,
            'lan_error': runtime.lanError,
          },
        );
      }
      runApp(RestaurantTableApp(kdsRuntime: kdsRuntime));
    },
    (error, stack) {
      CrashLog.instance.write('ERROR', '未捕获异步异常: $error', stack);
    },
  );
}

class RestaurantTableApp extends StatefulWidget {
  const RestaurantTableApp({
    super.key,
    this.kdsRuntime,
    this.transport,
    this.takeoutDispatchAlertSource,
    this.sessionStorage,
  });

  final CashierKdsRuntime? kdsRuntime;
  final HttpTransport? transport;
  final TakeoutDispatchAlertSource? takeoutDispatchAlertSource;
  final CashierSessionStorage? sessionStorage;

  @override
  State<RestaurantTableApp> createState() => _RestaurantTableAppState();
}

class _RestaurantTableAppState extends State<RestaurantTableApp> {
  final AppState appState = AppState();
  late final CashierSessionStorage _sessionStorage =
      widget.sessionStorage ?? CashierSessionStorage();
  late final HttpTransport transport =
      widget.transport ?? createHttpTransport();
  late final NetworkStatusMonitor _networkMonitor = NetworkStatusMonitor(
    baseUrl: appState.baseUrl,
    transport: transport,
  );
  late final TakeoutDispatchAlertSource _takeoutDispatchAlertSource =
      widget.takeoutDispatchAlertSource ??
      (widget.transport == null
          ? createTakeoutDispatchAlertSource(appState.baseUrl)
          : const NoopTakeoutDispatchAlertSource());
  ThemeMode _themeMode = ThemeMode.light;
  bool _restoringSession = true;

  /// 用于在收银台界面之上弹「切换账号密码验证」等对话框。
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    appState.addListener(_configureCloudSync);
    _networkMonitor.start();
    _takeoutDispatchAlertSource.start();
    unawaited(_restoreSession());
  }

  Future<void> _restoreSession() async {
    try {
      final persisted = await _sessionStorage.read();
      if (persisted == null || !mounted) return;
      final session = await AuthRepository(
        _client(),
      ).restoreSession(persisted.token, actorName: persisted.actorName);
      if (!mounted) return;
      appState.applySession(session, preferredShopId: persisted.selectedShopId);
      await _sessionStorage.save(
        session,
        selectedShopId: appState.currentShopId,
      );
    } on ApiException catch (error) {
      if (_isAuthenticationRejection(error)) {
        await _sessionStorage.clear();
      }
      CrashLog.instance.recordBreadcrumb(
        category: 'auth',
        message: '收银登录状态恢复失败',
        level: 'warn',
        data: {
          'status': error.statusCode,
          'code': error.code,
          'credential_cleared': _isAuthenticationRejection(error),
        },
      );
    } catch (error, stackTrace) {
      CrashLog.instance.write('WARN', '收银登录状态恢复异常: $error', stackTrace);
    } finally {
      if (mounted) setState(() => _restoringSession = false);
    }
  }

  bool _isAuthenticationRejection(ApiException error) =>
      error.statusCode == 401 || error.code == 4010;

  Future<void> _onLoggedIn(
    LoginSession session, {
    int? preferredShopId,
  }) async {
    appState.applySession(session, preferredShopId: preferredShopId);
    await _sessionStorage.save(session, selectedShopId: appState.currentShopId);
  }

  Future<void> _logout() async {
    try {
      await _sessionStorage.clear();
    } catch (error, stackTrace) {
      CrashLog.instance.write('ERROR', '安全凭据清除失败: $error', stackTrace);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('退出登录警告：本地安全凭据未能完全清除，请手动关闭应用'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) appState.logout();
    }
  }

  /// 快速切换账号（原地切换，不退出界面）：在收银台当前界面之上弹出
  /// 密码验证框，验证通过后用目标工号登录，原地更新账号信息、权限与门店，
  /// 不经过登录页、不中断当前操作界面。
  Future<void> _switchAccount(String workNo) async {
    final target = workNo.trim();
    if (target.isEmpty || target == appState.currentWorkNo) return;
    final navigatorState = _navigatorKey.currentState;
    if (navigatorState == null || !mounted) return;

    try {
      final password = await showCashierAccountPasswordDialog(
        navigatorState.context,
        workNo: target,
        navigator: navigatorState,
      );
      if (password == null || !mounted) return;

      final previousShopId = appState.currentShopId;
      // 登录请求不带旧账号 token；成功后替换会话并保留原门店（新账号无权限则回落其默认门店）。
      final session = await AuthRepository(_client().copyWith(token: null))
          .login(username: target, password: password);
      await _onLoggedIn(session, preferredShopId: previousShopId);
      await CashierAccountStorage().saveAccount(target, remember: true);
      if (!mounted) return;
      _showSwitchNotice('已切换到 ${session.displayName}（工号 ${target}）');
    } on ApiException catch (error) {
      _showSwitchNotice('切换失败：${error.message}');
    } catch (error, stackTrace) {
      CrashLog.instance.write('WARN', '快速切换账号异常: $error', stackTrace);
      _showSwitchNotice('切换失败：$error');
    }
  }

  /// 提示通道优先走根 ScaffoldMessenger（通过 GlobalKey 直连，位于 MaterialApp 之内），
  /// 避免在 MaterialApp 之上的 context 调 [ScaffoldMessenger.of] 抛「无祖先异常」，
  /// 同时兼容旧版导航 context 回退与静默保护。
  void _showSwitchNotice(String message) {
    if (!mounted) return;
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    final nav = _navigatorKey.currentState;
    if (nav != null) {
      try {
        ScaffoldMessenger.of(nav.context).showSnackBar(
          SnackBar(
            content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      } catch (_) {}
    }
  }

  /// 权限版本不一致（ACCESS_PERMISSION_CHANGED）时刷新权限：
  /// 重新拉取 /admin/me/permissions 并原地更新会话（保留当前门店与页面）。
  /// 刷新失败时静默保留旧权限，等待下一次请求再次触发。
  Future<void> _refreshPermissions() async {
    final token = appState.token;
    if (token == null || token.isEmpty || !appState.isAuthenticated) return;
    try {
      final session = await AuthRepository(_client()).restoreSession(
        token,
        actorName: appState.currentActorName ?? '',
      );
      if (mounted) appState.refreshFromSession(session);
      if (mounted) {
        final messenger = _scaffoldMessengerKey.currentState;
        if (messenger != null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('权限已更新，界面已按最新权限刷新')),
          );
        } else {
          final nav = _navigatorKey.currentState;
          if (nav != null) {
            try {
              ScaffoldMessenger.of(nav.context).showSnackBar(
                const SnackBar(content: Text('权限已更新，界面已按最新权限刷新')),
              );
            } catch (_) {}
          }
        }
      }
    } catch (error) {
      CrashLog.instance.recordBreadcrumb(
        category: 'auth',
        message: '权限刷新失败: $error',
        level: 'warning',
      );
    }
  }

  /// 会话终止（账号停用/离职/锁定/强制下线/登录过期）时退出登录并提示。
  Future<void> _handleSessionTerminated() async {
    if (!appState.isAuthenticated) return;
    await _logout();
    if (!mounted) return;
    final messenger = _scaffoldMessengerKey.currentState;
    if (messenger != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('登录状态已失效，请重新登录')),
      );
    } else {
      final nav = _navigatorKey.currentState;
      if (nav != null) {
        try {
          ScaffoldMessenger.of(nav.context).showSnackBar(
            const SnackBar(content: Text('登录状态已失效，请重新登录')),
          );
        } catch (_) {}
      }
    }
  }

  void _selectShop(int shopId) {
    appState.selectShop(shopId);
    unawaited(_sessionStorage.updateSelectedShop(shopId));
  }

  void _configureCloudSync() {
    final runtime = widget.kdsRuntime;
    if (runtime == null) return;
    runtime.setActiveShop(appState.currentShopId);
    runtime.configureCloudProxy(
      appState.isAuthenticated
          ? AdminApiCashierKdsProxyClient(
              _client(),
              cashierDeviceCode: runtime.cashierDeviceCode,
            )
          : null,
    );
  }

  AdminApiClient _client() {
    return AdminApiClient(
      baseUrl: appState.baseUrl,
      transport: transport,
      token: appState.token,
      shopId: appState.currentShopId,
      terminalId: TerminalDeviceService.instance.currentTerminalId,
      onPermissionChanged: () => unawaited(_refreshPermissions()),
      onSessionTerminated: () => unawaited(_handleSessionTerminated()),
    );
  }

  void _setThemeMode(ThemeMode value) {
    if (_themeMode == value) return;
    setState(() => _themeMode = value);
  }

  Widget _buildCashierShellForRoute({
    required BuildContext context,
    required CashierSection currentSection,
    required Widget body,
    bool showSidebar = false,
  }) {
    final now = DateTime.now();
    final effectiveCashierName = appState.currentRealName.isNotEmpty
        ? appState.currentRealName
        : (appState.currentDisplayName.isNotEmpty
            ? appState.currentDisplayName
            : (appState.currentActorName?.isNotEmpty == true
                ? appState.currentActorName!
                : '张晓峰'));
    final effectiveWorkNo = appState.currentWorkNo.isNotEmpty
        ? appState.currentWorkNo
        : '0801';

    return CashierShell(
      currentSection: currentSection,
      showSidebar: showSidebar,
      bodyPadding: EdgeInsets.zero,
      onSectionChanged: (_) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      connectionText: _networkMonitor.online ? '云端在线 (12ms)' : '云端离线',
      connected: _networkMonitor.online,
      kdsAvailable: widget.kdsRuntime?.isAvailable ?? false,
      kdsText: (widget.kdsRuntime?.isAvailable ?? false)
          ? '后厨 KDS: 正常已连'
          : '后厨 KDS: 未接入',
      storeText: appState.currentShop?.name ?? '当前门店',
      cashierName: effectiveCashierName,
      cashierWorkNo: effectiveWorkNo,
      isDarkMode: _themeMode == ThemeMode.dark,
      onToggleTheme: () => _setThemeMode(
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      ),
      onLogout: () {
        Navigator.of(context).popUntil((route) => route.isFirst);
        unawaited(_logout());
      },
      timeText: CashierShell.formatClock(now),
      dateText: CashierShell.formatDate(now),
      body: body,
    );
  }

  @override
  void dispose() {
    appState.removeListener(_configureCloudSync);
    _networkMonitor.dispose();
    unawaited(_takeoutDispatchAlertSource.close());
    final runtime = widget.kdsRuntime;
    if (runtime != null) unawaited(runtime.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '老肥家收银系统',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: CashierAppTheme.light(),
      darkTheme: CashierAppTheme.dark(),
      themeMode: _themeMode,
      themeAnimationDuration: const Duration(milliseconds: 220),
      builder: (context, child) =>
          CashierResponsiveViewport(child: child ?? const SizedBox.shrink()),
      home: AnimatedBuilder(
        animation: appState,
        builder: (context, _) {
          if (_restoringSession) {
            return const Scaffold(
              body: Center(
                child: SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            );
          }
          if (!appState.isAuthenticated) {
            return CashierLoginPage(
              repository: AuthRepository(_client()),
              onLoggedIn: _onLoggedIn,
              themeMode: _themeMode,
              onThemeModeChanged: _setThemeMode,
            );
          }
          return CashierWorkspace(
            client: _client(),
            permissions: appState.permissions,
            isSuperAdmin: appState.isSuperAdmin,
            shops: appState.shops,
            currentShopId: appState.currentShopId,
            currentAccount: appState.currentActorName,
            currentWorkNo: appState.currentWorkNo,
            currentRealName: appState.currentRealName,
            currentJobTitle: appState.currentJobTitle,
            currentDisplayName: appState.currentDisplayName,
            storeName: appState.currentShop?.name ?? '当前门店',
            networkMonitor: _networkMonitor,
            onShopChanged: _selectShop,
            onLogout: () => unawaited(_logout()),
            onSwitchAccount: (workNo) => unawaited(_switchAccount(workNo)),
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
            kdsAvailable: widget.kdsRuntime?.isAvailable ?? false,
            kdsRuntime: widget.kdsRuntime,
            takeoutDispatchAlerts: _takeoutDispatchAlertSource.alerts,
            onOpenKdsDiagnostics: widget.kdsRuntime == null
                ? null
                : () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (routeContext) => _buildCashierShellForRoute(
                          context: routeContext,
                          currentSection: CashierSection.manage,
                          body: CashierKdsDiagnosticsPage(
                            runtime: widget.kdsRuntime!,
                            canManage:
                                appState.permissions.contains('kds:config') ||
                                appState.permissions.contains('admin:manage'),
                          ),
                        ),
                      ),
                    );
                  },
            onTableSelected: (table) async {
              CrashLog.instance.recordBreadcrumb(
                category: 'order',
                message: '选择桌台: ${table.number} (占用: ${table.isOccupied})',
                data: {
                  'table': table.number,
                  'occupied': table.isOccupied,
                  'people': table.people,
                },
              );
              final client = _client();
              final PosRepository repository = RealPosRepository(client);
              var openedBeforeNavigation = false;
              if (!table.isOccupied) {
                await repository.openTable(table.number);
                openedBeforeNavigation = true;
                CrashLog.instance.recordBreadcrumb(
                  category: 'order',
                  message: '开台完成: ${table.number}',
                  data: {'table': table.number},
                );
              }
              if (!context.mounted) return;
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (routeContext) => _buildCashierShellForRoute(
                    context: routeContext,
                    currentSection: CashierSection.table,
                    body: TableOrderPage(
                      table: table,
                      initiallyOpened: openedBeforeNavigation,
                      memberRepository: RealCashierMemberRepository(client),
                      shiftRepository: RealCashierShiftRepository(client),
                      repository: repository,
                      approvalRepository: AccessApprovalRepository(client),
                      currentAccount: appState.currentWorkNo.isNotEmpty
                          ? appState.currentWorkNo
                          : appState.currentActorName,
                      onLogout: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                        unawaited(_logout());
                      },
                    ),
                  ),
                ),
              );
            },
            onPickupOrder: () {
              CrashLog.instance.recordBreadcrumb(
                category: 'order',
                message: '进入打包外卖点单',
              );
              return Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (routeContext) => _buildCashierShellForRoute(
                    context: routeContext,
                    currentSection: CashierSection.table,
                    body: TableOrderPage(
                      table: const DiningTable(
                        number: '打包',
                        status: TableStatus.empty,
                        people: 1,
                      ),
                      pickupOrder: true,
                      repository: RealPosRepository(_client()),
                      approvalRepository: AccessApprovalRepository(_client()),
                      shiftRepository: RealCashierShiftRepository(_client()),
                      currentAccount: appState.currentWorkNo.isNotEmpty
                          ? appState.currentWorkNo
                          : appState.currentActorName,
                      onLogout: () {
                        Navigator.of(context).popUntil((route) => route.isFirst);
                        unawaited(_logout());
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
