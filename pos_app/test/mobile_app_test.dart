import 'package:admin_panel_flutter/src/features/mobile/data/auth_state.dart';
import 'package:admin_panel_flutter/src/features/mobile/presentation/login_page.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthStorage extends SecureAuthStorage {
  @override
  Future<LoginSession?> readSession() async => null;

  @override
  Future<String?> readToken() async => null;

  @override
  Future<void> saveSession(session) async {}

  @override
  Future<void> clear() async {}
}

class _FailingAuthStorage extends _FakeAuthStorage {
  @override
  Future<void> saveSession(session) async {
    throw StateError('secure storage unavailable');
  }
}

void main() {
  test(
    'failed secure storage write does not expose an authenticated state',
    () async {
      final container = ProviderContainer(
        overrides: [
          authStorageProvider.overrideWithValue(_FailingAuthStorage()),
        ],
      );
      addTearDown(container.dispose);
      final notifier = container.read(authProvider.notifier);

      await expectLater(
        notifier.applySession(
          const LoginSession(
            token: 'jwt',
            scope: 'SHOP',
            permissions: {},
            shops: [],
          ),
        ),
        throwsStateError,
      );

      expect(container.read(authProvider).isAuthenticated, isFalse);
    },
  );

  testWidgets('mobile login page renders', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStorageProvider.overrideWithValue(_FakeAuthStorage())],
        child: const MaterialApp(home: MobileLoginPage()),
      ),
    );
    await tester.pump();
    expect(find.text('老肥家门店助手'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.byTooltip('显示密码'), findsOneWidget);

    await tester.tap(find.text('登录'));
    await tester.pump();
    expect(find.text('请输入账号'), findsOneWidget);
    expect(find.text('请输入密码'), findsOneWidget);

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();
    expect(find.byTooltip('隐藏密码'), findsOneWidget);
  });

  testWidgets('mobile login form stays readable on a wide viewport', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authStorageProvider.overrideWithValue(_FakeAuthStorage())],
        child: const MaterialApp(home: MobileLoginPage()),
      ),
    );
    await tester.pump();

    expect(tester.getSize(find.byType(TextFormField).first).width, 480);
  });
}
