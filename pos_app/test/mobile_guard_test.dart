import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/features/mobile/app/mobile_router.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/api_providers.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/auth_state.dart';
import 'package:admin_panel_flutter/src/features/mobile/presentation/about_page.dart';
import 'package:admin_panel_flutter/src/features/mobile/presentation/boss_reports_page.dart';
import 'package:admin_panel_flutter/src/features/mobile/presentation/forbidden_page.dart';
import 'package:admin_panel_flutter/src/features/mobile/presentation/member_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 路由守卫验收（T-17）：老板/员工权限矩阵。
class _FakeHttpTransport implements HttpTransport {
  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,  }) async {
    return HttpResponseData(statusCode: 200, body: '{}');
  }
}

class _FixedAuthNotifier extends AuthNotifier {
  _FixedAuthNotifier(this._state);

  final AuthState _state;

  @override
  AuthState build() => _state;
}

AuthState _auth({
  String scope = 'SHOP',
  Set<String> permissions = const {},
}) {
  return AuthState(
    token: 'test-token',
    scope: scope,
    permissions: permissions,
    shops: const [],
    restoring: false,
  );
}

void main() {
  Future<void> pumpWith(
    WidgetTester tester, {
    required AuthState state,
    required String location,
  }) async {
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(() => _FixedAuthNotifier(state)),
        httpTransportProvider.overrideWithValue(_FakeHttpTransport()),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.go(location);
    await tester.pumpAndSettle();
  }

  testWidgets('员工访问 /boss-reports 被守卫到 /forbidden', (tester) async {
    await pumpWith(
      tester,
      state: _auth(permissions: const {'order:view', 'order:operate'}),
      location: '/boss-reports',
    );
    expect(find.byType(ForbiddenPage), findsOneWidget);
  });

  testWidgets('员工访问 /member 无 user:view 被守卫', (tester) async {
    await pumpWith(
      tester,
      state: _auth(permissions: const {'order:view'}),
      location: '/member',
    );
    expect(find.byType(ForbiddenPage), findsOneWidget);
  });

  testWidgets('员工访问 /boss-staff 无 admin:manage 被守卫', (tester) async {
    await pumpWith(
      tester,
      state: _auth(permissions: const {'order:view'}),
      location: '/boss-staff',
    );
    expect(find.byType(ForbiddenPage), findsOneWidget);
  });

  testWidgets('员工访问 /daily-settle 无 order:config 被守卫', (tester) async {
    await pumpWith(
      tester,
      state: _auth(permissions: const {'order:view'}),
      location: '/daily-settle',
    );
    expect(find.byType(ForbiddenPage), findsOneWidget);
  });

  testWidgets('老板(HQ)可进入 /boss-reports', (tester) async {
    await pumpWith(
      tester,
      state: _auth(scope: 'HQ'),
      location: '/boss-reports',
    );
    expect(find.byType(BossReportsPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('有 user:view 可进入 /member', (tester) async {
    await pumpWith(
      tester,
      state: _auth(permissions: const {'user:view', 'order:view'}),
      location: '/member',
    );
    expect(find.byType(MemberPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('关于与帮助页可正常渲染', (tester) async {
    await pumpWith(
      tester,
      state: _auth(permissions: const {'order:view'}),
      location: '/about',
    );
    expect(find.byType(AboutPage), findsOneWidget);
    expect(find.text('关于与帮助'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
