import 'dart:convert';

import 'package:admin_panel_flutter/main.dart';
import 'package:admin_panel_flutter/src/features/auth/data/cashier_account_storage.dart';
import 'package:admin_panel_flutter/src/features/auth/data/cashier_session_storage.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_workspace.dart';
import 'package:admin_panel_flutter/src/features/auth/presentation/cashier_login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  testWidgets(
    'restores a valid secure cashier session without password entry',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sessionStorage = CashierSessionStorage(
        MemoryAccountKeyValueStorage(),
      );
      await sessionStorage.save(
        const LoginSession(
          token: 'saved-jwt',
          scope: 'SHOP',
          permissions: {},
          shops: [],
          actorName: 'cashier',
        ),
        selectedShopId: 3,
      );
      final transport = FakeHttpTransport({
        'GET /admin/me/permissions': jsonEncode({
          'code': 200,
          'data': {
            'scope': 'SHOP',
            'permissions': ['cashier:operate', 'order:view'],
          },
        }),
        'GET /admin/me/shops': jsonEncode({
          'code': 200,
          'data': {
            'shops': [
              {'id': 2, 'code': 'LF001', 'name': '南湖店'},
              {'id': 3, 'code': 'LF002', 'name': '红旗街店'},
            ],
          },
        }),
        'GET /cashier/shift/current': jsonEncode({
          'code': 200,
          'data': {'shift': null},
        }),
        'GET /admin/table/status': jsonEncode({
          'code': 200,
          'data': {'tableList': []},
        }),
        'POST /admin/order/list': jsonEncode({
          'code': 200,
          'data': {'records': [], 'total': 0},
        }),
      });

      await tester.pumpWidget(
        RestaurantTableApp(
          transport: transport,
          sessionStorage: sessionStorage,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CashierWorkspace), findsOneWidget);
      expect(find.byType(CashierLoginPage), findsNothing);
      expect(find.text('红旗街店'), findsWidgets);
      expect(
        transport.requests
            .firstWhere(
              (request) => request.uri.path == '/admin/me/permissions',
            )
            .headers['Authorization'],
        'Bearer saved-jwt',
      );

      await tester.tap(find.byIcon(Icons.logout_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(CashierLoginPage), findsOneWidget);
      expect(await sessionStorage.read(), isNull);
    },
  );

  testWidgets('rejects and clears an invalid persisted cashier token', (
    tester,
  ) async {
    final sessionStorage = CashierSessionStorage(
      MemoryAccountKeyValueStorage(),
    );
    await sessionStorage.save(
      const LoginSession(
        token: 'expired-jwt',
        scope: 'SHOP',
        permissions: {},
        shops: [],
      ),
    );
    final transport = FakeHttpTransport({
      'GET /admin/me/permissions': jsonEncode({
        'code': 4010,
        'msg': 'token invalid',
      }),
    });

    await tester.pumpWidget(
      RestaurantTableApp(transport: transport, sessionStorage: sessionStorage),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CashierLoginPage), findsOneWidget);
    expect(await sessionStorage.read(), isNull);
  });

  testWidgets('keeps persisted token after a transient restore failure', (
    tester,
  ) async {
    final sessionStorage = CashierSessionStorage(
      MemoryAccountKeyValueStorage(),
    );
    await sessionStorage.save(
      const LoginSession(
        token: 'retry-later-jwt',
        scope: 'SHOP',
        permissions: {},
        shops: [],
      ),
    );
    final transport = FakeHttpTransport({
      'GET /admin/me/permissions': jsonEncode({
        'code': 5000,
        'msg': 'temporary unavailable',
      }),
    });

    await tester.pumpWidget(
      RestaurantTableApp(transport: transport, sessionStorage: sessionStorage),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CashierLoginPage), findsOneWidget);
    expect((await sessionStorage.read())?.token, 'retry-later-jwt');
  });

  testWidgets('production app completes login workspace and logout flow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final transport = FakeHttpTransport({
      'POST /adminLogin': jsonEncode({
        'code': 200,
        'data': {'token': 'jwt-token', 'scope': 'SHOP'},
      }),
      'GET /admin/me/permissions': jsonEncode({
        'code': 200,
        'data': {
          'scope': 'SHOP',
          'permissions': ['cashier:operate', 'order:view', 'order:operate'],
        },
      }),
      'GET /admin/me/shops': jsonEncode({
        'code': 200,
        'data': {
          'shops': [
            {'id': 2, 'code': 'LF001', 'name': '南湖店'},
            {'id': 3, 'code': 'LF002', 'name': '红旗街店'},
          ],
        },
      }),
      'GET /cashier/shift/current': jsonEncode({
        'code': 200,
        'data': {'shift': null},
      }),
      'GET /admin/table/status': jsonEncode({
        'code': 200,
        'data': {'tableList': []},
      }),
      'POST /admin/order/list': jsonEncode({
        'code': 200,
        'data': {'records': [], 'total': 0},
      }),
    });

    await tester.pumpWidget(RestaurantTableApp(transport: transport));
    await tester.pumpAndSettle();
    expect(find.byType(CashierLoginPage), findsOneWidget);
    expect(find.byKey(const Key('cashier-theme-toggle')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cashier-theme-toggle')));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(CashierLoginPage))).brightness,
      Brightness.dark,
    );

    await tester.enterText(find.byType(TextField).at(0), 'cashier');
    await tester.enterText(find.byType(TextField).at(1), 'secret');
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.byType(CashierWorkspace), findsOneWidget);
    expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const Key('cashier-brand-store-name')))
          .data,
      '南湖店',
    );
    expect(
      transport.requests
          .firstWhere((request) => request.uri.path == '/admin/table/status')
          .headers['X-Shop-Id'],
      '2',
    );

    await tester.tap(find.byKey(const Key('cashier-shop-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('红旗街店').last);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const Key('cashier-brand-store-name')))
          .data,
      '红旗街店',
    );
    expect(
      transport.requests
          .where((request) => request.uri.path == '/admin/table/status')
          .last
          .headers['X-Shop-Id'],
      '3',
    );

    await tester.tap(find.byIcon(Icons.logout_rounded));
    await tester.pumpAndSettle();

    expect(find.byType(CashierLoginPage), findsOneWidget);
    expect(find.byType(CashierWorkspace), findsNothing);
  });

  testWidgets('switching account updates identity and shows notice without throwing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sessionStorage = CashierSessionStorage(
      MemoryAccountKeyValueStorage(),
    );
    await sessionStorage.save(
      const LoginSession(
        token: 'old-jwt',
        scope: 'SHOP',
        permissions: {'cashier:operate'},
        shops: [],
        actorName: 'cashier-1',
      ),
      selectedShopId: 3,
    );
    final transport = FakeHttpTransport({
      'GET /admin/me/permissions': jsonEncode({
        'code': 200,
        'data': {
          'scope': 'SHOP',
          'permissions': ['cashier:operate', 'order:view'],
        },
      }),
      'GET /admin/me/shops': jsonEncode({
        'code': 200,
        'data': {
          'shops': [
            {'id': 2, 'code': 'LF001', 'name': '南湖店'},
            {'id': 3, 'code': 'LF002', 'name': '红旗街店'},
          ],
        },
      }),
      'GET /cashier/shift/current': jsonEncode({
        'code': 200,
        'data': {'shift': null},
      }),
      'GET /admin/table/status': jsonEncode({
        'code': 200,
        'data': {'tableList': []},
      }),
      'POST /admin/order/list': jsonEncode({
        'code': 200,
        'data': {'records': [], 'total': 0},
      }),
      'POST /adminLogin': jsonEncode({
        'code': 200,
        'data': {
          'token': 'new-jwt',
          'workNo': 'CW099',
          'userName': 'cashier-2',
          'displayName': '二号收银',
          'scope': 'SHOP',
          'permissions': ['cashier:operate', 'order:view'],
          'shops': [
            {'id': 3, 'code': 'LF002', 'name': '红旗街店'},
          ],
        },
      }),
    });

    await tester.pumpWidget(
      RestaurantTableApp(
        transport: transport,
        sessionStorage: sessionStorage,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CashierWorkspace), findsOneWidget);

    // 档案弹窗 → 切换账号 → 输入其他工号 → 密码验证 → 原地切换。
    await tester.tap(find.byKey(const Key('cashier-identity-capsule')));
    await tester.pumpAndSettle();
    expect(find.text('员工个人档案'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cashier-profile-switch-account')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('switch-other-workno')),
      'CW099',
    );
    await tester.tap(find.byKey(const Key('switch-account-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('切换到工号 CW099'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('switch-password-input')),
      'secret-2',
    );
    await tester.tap(find.byKey(const Key('switch-password-confirm')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));

    // 切换成功提示正常显示（修复前 ScaffoldMessenger.of 在 MaterialApp 之上
    // 抛「无 ScaffoldMessenger 祖先」，提示被拦截、界面无反应）。
    expect(
      transport.requests.any(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/adminLogin' &&
            request.body != null &&
            request.body!.contains('CW099'),
      ),
      isTrue,
    );
    expect(find.textContaining('已切换到'), findsOneWidget);
  });
}
