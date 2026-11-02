import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/auth_state.dart';
import '../presentation/forbidden_page.dart';
import '../presentation/boss_reports_page.dart';
import '../presentation/boss_staff_page.dart';
import '../presentation/daily_settle_page.dart';
import '../presentation/member_page.dart';
import '../presentation/about_page.dart';
import '../presentation/notification_preferences_page.dart';
import '../presentation/home_page.dart';
import '../presentation/inventory_count_page.dart';
import '../presentation/login_page.dart';
import '../presentation/notifications_page.dart';
import '../presentation/order_kds_page.dart';
import '../presentation/orders_page.dart';
import '../presentation/payment_reconcile_page.dart';
import '../presentation/profile_page.dart';
import '../presentation/qr_approval_page.dart';
import '../presentation/shift_handover_page.dart';
import '../presentation/shop_settings_page.dart';
import '../presentation/staff_schedule_page.dart';
import '../presentation/tables_page.dart';

/// 深链挂起的审批码：店长未登录时收到 `bbq://approval?code=...`，
/// 先暂存于此，登录成功后由登录页跳转至审批页。
String? pendingApprovalCode;

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authProvider);
  return GoRouter(
    initialLocation: '/home',
    redirect: (context, state) {
      if (auth.restoring) return null;
      final loggedIn = auth.isAuthenticated;
      final onLogin = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn && onLogin) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const MobileLoginPage()),
      GoRoute(
        path: '/forbidden',
        builder: (_, __) => const ForbiddenPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MobileShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/home', builder: (_, __) => const HomePage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/orders', builder: (_, __) => const OrdersPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/tables', builder: (_, __) => const TablesPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (_, __) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => const NotificationsPage(),
      ),
      // 方案A·店长扫码审批页：收银端出码后店长手机扫码（深链 bbq://approval）唤起。
      GoRoute(
        path: '/approval',
        builder: (context, state) {
          final code = state.uri.queryParameters['code'] ?? '';
          return QrApprovalPage(approvalCode: code);
        },
      ),
      // 新场景原型页（design-system/laofei-mobile/prototype-prompts.md §四）。
      GoRoute(
        path: '/kds',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!(auth.hasPermission('order:view'))) return '/forbidden';
          return null;
        },
        builder: (_, __) => const OrderKdsPage(),
      ),
      GoRoute(
        path: '/shift-handover',
        builder: (_, __) => const ShiftHandoverPage(),
      ),
      GoRoute(
        path: '/inventory-count',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!(auth.hasPermission('order:config'))) return '/forbidden';
          return null;
        },
        builder: (_, __) => const InventoryCountPage(),
      ),
      GoRoute(
        path: '/staff-schedule',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!(auth.hasPermission('shop:manage'))) return '/forbidden';
          return null;
        },
        builder: (_, __) => const StaffSchedulePage(),
      ),
      GoRoute(
        path: '/payment-reconcile',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!(auth.hasPermission('order:config'))) return '/forbidden';
          return null;
        },
        builder: (_, __) => const PaymentReconcilePage(),
      ),
      GoRoute(
        path: '/shop-settings',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!(auth.hasPermission('order:config'))) return '/forbidden';
          return null;
        },
        builder: (_, __) => const ShopSettingsPage(),
      ),
      GoRoute(
        path: '/boss-reports',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!auth.isBoss) return '/forbidden';
          return null;
        },
        builder: (_, __) => const BossReportsPage(),
      ),
      GoRoute(
        path: '/boss-staff',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!auth.canManageStaff) return '/forbidden';
          return null;
        },
        builder: (_, __) => const BossStaffPage(),
      ),
      GoRoute(
        path: '/daily-settle',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!(auth.hasPermission('daily:settle') || auth.hasPermission('order:config'))) {
            return '/forbidden';
          }
          return null;
        },
        builder: (_, __) => const DailySettlePage(),
      ),
      GoRoute(
        path: '/member',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!auth.hasPermission('user:view')) return '/forbidden';
          return null;
        },
        builder: (_, __) => const MemberPage(),
      ),
      GoRoute(
        path: '/notification-preferences',
        builder: (_, __) => const NotificationPreferencesPage(),
      ),
      GoRoute(
        path: '/about',
        builder: (_, __) => const AboutPage(),
      ),
      GoRoute(
        path: '/order/:id',
        redirect: (context, state) {
          final auth = ref.read(authProvider);
          if (!auth.hasPermission('order:view')) return '/forbidden';
          return null;
        },
        builder: (_, state) =>
            OrdersPage(focusOrderId: state.pathParameters['id']),
      ),
    ],
  );
});

class MobileShell extends StatelessWidget {
  const MobileShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          initialLocation: index == shell.currentIndex,
        ),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: '首页'),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: '订单',
          ),
          NavigationDestination(
            icon: Icon(Icons.table_restaurant_outlined),
            label: '桌台',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
