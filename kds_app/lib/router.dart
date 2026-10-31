part of 'app.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // 仅登录态变化时重建路由，避免看板刷新 workflows 时整树重绘
  final loggedIn = ref.watch(sessionProvider.select((s) => s.isLoggedIn));

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    redirect: (context, state) {
      final onLogin = state.matchedLocation == '/login';

      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const KdsV2SettingsPage(),
      ),
      GoRoute(
        path: '/logs',
        builder: (context, state) => const KdsLiveLogPage(),
      ),
      GoRoute(
        path: '/inspector',
        builder: (context, state) => const Scaffold(
          backgroundColor: Color(0xFF141414),
          body: SafeArea(child: KdsInspectorWindow()),
        ),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const HomeGate(),
      ),
    ],
  );
});

class HomeGate extends ConsumerWidget {
  const HomeGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final device = ref.watch(sessionProvider).device;
    if (device == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return const KdsV2BoardPage();
  }
}
