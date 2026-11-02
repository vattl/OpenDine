import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_providers.dart';
import '../data/auth_state.dart';
import '../data/pending_order_worker.dart';
import 'mobile_router.dart';
import 'mobile_theme.dart';

class MobileApp extends ConsumerStatefulWidget {
  const MobileApp({super.key});

  @override
  ConsumerState<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends ConsumerState<MobileApp> {
  bool _workerStarted = false;
  String? _registeredPushIdentity;
  bool _pushRegistrationScheduled = false;

  /// 深链（bbq://approval）监听：店长手机扫码唤起审批页。
  StreamSubscription<Uri>? _deepLinkSub;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    super.dispose();
  }

  void _initDeepLinks() {
    final appLinks = AppLinks();
    // 冷启动：App 尚未运行时扫码唤起。
    unawaited(
      appLinks.getInitialLink().then((uri) {
        if (uri != null) _handleDeepLink(uri);
      }).catchError((Object error) {
        debugPrint('读取初始深链失败: $error');
      }),
    );
    // 运行中：从后台/外部唤起。
    _deepLinkSub = appLinks.uriLinkStream.listen(
      _handleDeepLink,
      onError: (Object error) => debugPrint('深链监听失败: $error'),
    );
  }

  /// 处理扫码审批深链：`bbq://approval?code=QAP_...`（兼容 laofei://）。
  void _handleDeepLink(Uri uri) {
    if (uri.scheme != 'bbq' && uri.scheme != 'laofei') return;
    final isApproval =
        uri.host == 'approval' ||
        uri.path == '/approval' ||
        uri.path.startsWith('/approval');
    if (!isApproval) return;
    final code = uri.queryParameters['code'] ?? '';
    if (code.isEmpty) return;
    if (!ref.read(authProvider).isAuthenticated) {
      // 未登录：暂存审批码，登录成功后由登录页跳转。
      pendingApprovalCode = code;
      return;
    }
    ref.read(routerProvider).push('/approval?code=$code');
  }

  void _syncPushRegistration(AuthState auth) {
    if (!auth.isAuthenticated || auth.currentShopId == null) {
      _registeredPushIdentity = null;
      return;
    }
    final identity = '${auth.token}|${auth.currentShopId}';
    if (_registeredPushIdentity == identity || _pushRegistrationScheduled) {
      return;
    }
    _pushRegistrationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref.read(pushServiceProvider).register();
        if (mounted) _registeredPushIdentity = identity;
      } catch (error) {
        debugPrint('push registration failed: $error');
      } finally {
        _pushRegistrationScheduled = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    _syncPushRegistration(auth);
    // 登录后启动弱网补单 worker，登出停止。
    if (auth.isAuthenticated && !_workerStarted) {
      _workerStarted = true;
      final repo = ref.read(posRepositoryProvider);
      final replayer = PendingOrderReplayer(repo);
      ref.read(pendingOrderWorkerProvider).start(submitter: replayer.call);
    } else if (!auth.isAuthenticated && _workerStarted) {
      _workerStarted = false;
      ref.read(pendingOrderWorkerProvider).stop();
    }
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: '老肥家门店助手',
      debugShowCheckedModeBanner: false,
      theme: MobileTheme.light(),
      darkTheme: MobileTheme.dark(),
      // 跟随系统深色模式：门店夜间灯光环境自动切暗色（原型文档 §2.2）。
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}
