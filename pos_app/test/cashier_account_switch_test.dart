import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/auth_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/data/cashier_account_storage.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:admin_panel_flutter/src/features/auth/presentation/cashier_login_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_account_password_dialog.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_account_switch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  @override
  AdminApiClient get client => throw UnimplementedError();

  @override
  Future<LoginSession> login({
    required String username,
    required String password,
  }) async {
    return const LoginSession(
      token: 'mock-token',
      scope: 'SHOP',
      permissions: {'cashier:operate'},
      shops: [],
    );
  }

  @override
  Future<LoginSession> restoreSession(String token, {String actorName = ''}) =>
      throw UnimplementedError();
}

void main() {
  group('CashierAccountSwitchDialog', () {
    testWidgets('lists saved accounts, marks current as disabled', (
      tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showCashierAccountSwitchDialog(
                  context,
                  savedAccounts: const ['CW001', 'CW099'],
                  currentWorkNo: 'CW001',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('切换账号'), findsOneWidget);
      expect(find.text('CW001'), findsOneWidget);
      expect(find.text('CW099'), findsOneWidget);
      // 当前账号带「当前」标记
      expect(find.text('当前'), findsOneWidget);

      // 选择非当前账号 CW099
      await tester.tap(find.byKey(const Key('switch-account-CW099')));
      await tester.pumpAndSettle();
      expect(picked, 'CW099');
    });

    testWidgets('current account row is not tappable', (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showCashierAccountSwitchDialog(
                  context,
                  savedAccounts: const ['CW001', 'CW099'],
                  currentWorkNo: 'CW001',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 点当前账号行不产生结果，弹窗保持打开
      await tester.tap(find.byKey(const Key('switch-account-CW001')));
      await tester.pumpAndSettle();
      expect(picked, isNull);
      expect(find.text('切换账号'), findsOneWidget);

      await tester.tap(find.byKey(const Key('switch-account-cancel')));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });

    testWidgets('confirms manually entered work number', (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showCashierAccountSwitchDialog(
                  context,
                  savedAccounts: const ['CW001'],
                  currentWorkNo: 'CW001',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('switch-other-workno')),
        'CW777',
      );
      await tester.tap(find.byKey(const Key('switch-account-confirm')));
      await tester.pumpAndSettle();
      expect(picked, 'CW777');
    });

    testWidgets('empty manual input shows error and cancel returns null', (
      tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showCashierAccountSwitchDialog(
                  context,
                  savedAccounts: const ['CW001'],
                  currentWorkNo: 'CW001',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('switch-account-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('请输入要切换的员工工号'), findsOneWidget);
      expect(picked, isNull);

      await tester.tap(find.byKey(const Key('switch-account-cancel')));
      await tester.pumpAndSettle();
      expect(picked, isNull);
      expect(find.text('切换账号'), findsNothing);
    });
  });

  group('CashierAccountPasswordDialog', () {
    testWidgets('enters password and confirms returns it', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showCashierAccountPasswordDialog(
                  context,
                  workNo: 'CW099',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('切换到工号 CW099'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('switch-password-input')),
        'secret-1',
      );
      await tester.tap(find.byKey(const Key('switch-password-confirm')));
      await tester.pumpAndSettle();
      expect(result, 'secret-1');
    });

    testWidgets('empty password confirm keeps dialog open and cancel returns null', (
      tester,
    ) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showCashierAccountPasswordDialog(
                  context,
                  workNo: 'CW099',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // 空密码确认不关闭弹窗
      await tester.tap(find.byKey(const Key('switch-password-confirm')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('切换到工号 CW099'), findsOneWidget);

      await tester.tap(find.byKey(const Key('switch-password-cancel')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.text('切换到工号 CW099'), findsNothing);
    });
  });

  group('CashierLoginPage initialUsername', () {
    testWidgets('prefills username and focuses password field', (tester) async {
      final memoryStore = MemoryAccountKeyValueStorage();
      await memoryStore.write(
        'saved_cashier_accounts',
        '[ "CW001", "CW099" ]',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CashierLoginPage(
            repository: _FakeAuthRepository(),
            accountStorage: CashierAccountStorage(memoryStore),
            initialUsername: 'CW099',
            onLoggedIn: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 工号已预填为切换目标
      final usernameField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      expect(usernameField.controller?.text, 'CW099');

      // 密码框已自动聚焦，无需再点一下
      final passwordField = tester.widget<TextField>(
        find.byType(TextField).at(1),
      );
      expect(passwordField.focusNode?.hasFocus, isTrue);
    });

    testWidgets('without initialUsername keeps default first saved account', (
      tester,
    ) async {
      final memoryStore = MemoryAccountKeyValueStorage();
      await memoryStore.write(
        'saved_cashier_accounts',
        '[ "CW001", "CW099" ]',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: CashierLoginPage(
            repository: _FakeAuthRepository(),
            accountStorage: CashierAccountStorage(memoryStore),
            onLoggedIn: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final usernameField = tester.widget<TextField>(
        find.byType(TextField).first,
      );
      // 未传入 initialUsername 时仍回落到历史首个工号
      expect(usernameField.controller?.text, 'CW001');
    });
  });
}
