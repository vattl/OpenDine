import 'dart:convert';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/auth_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/data/cashier_account_storage.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:admin_panel_flutter/src/features/auth/presentation/cashier_login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository();

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
  testWidgets('CashierLoginPage remembers account and selects from dropdown', (
    tester,
  ) async {
    final memoryStore = MemoryAccountKeyValueStorage();
    // 初始存储两个账号
    await memoryStore.write(
      'saved_cashier_accounts',
      jsonEncode(['admin001', 'store_admin']),
    );
    await memoryStore.write('remember_cashier_account_flag', 'true');

    final accountStorage = CashierAccountStorage(memoryStore);
    final repository = _FakeAuthRepository();
    LoginSession? loggedInSession;

    await tester.pumpWidget(
      MaterialApp(
        home: CashierLoginPage(
          repository: repository,
          accountStorage: accountStorage,
          onLoggedIn: (session) => loggedInSession = session,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 默认自动填入第一个记住的账号
    expect(find.text('admin001'), findsWidgets);

    // 点击下拉箭头展开下拉面板
    final dropdownButton = find.byTooltip('已记住的历史账号');
    expect(dropdownButton, findsOneWidget);
    await tester.tap(dropdownButton);
    await tester.pumpAndSettle();

    // 出现下拉选项 store_admin
    expect(find.text('store_admin'), findsOneWidget);

    // 点击选择 store_admin
    await tester.tap(find.text('store_admin'));
    await tester.pumpAndSettle();

    // 输入框已被填入 store_admin
    final usernameField = find.byType(TextField).first;
    expect(
      (tester.widget(usernameField) as TextField).controller?.text,
      'store_admin',
    );

    // 输入密码并登录
    final passwordField = find.byType(TextField).at(1);
    await tester.enterText(passwordField, '123456');
    await tester.tap(find.text('登 录'));
    await tester.pumpAndSettle();

    expect(loggedInSession, isNotNull);

    // 验证 store_admin 已被提升为最新记录
    final savedAfterLogin = await accountStorage.getSavedAccounts();
    expect(savedAfterLogin.first, 'store_admin');
  });

  testWidgets('CashierLoginPage can remove saved account from dropdown', (
    tester,
  ) async {
    final memoryStore = MemoryAccountKeyValueStorage();
    await memoryStore.write(
      'saved_cashier_accounts',
      jsonEncode(['admin001', 'test_user']),
    );

    final accountStorage = CashierAccountStorage(memoryStore);
    final repository = _FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierLoginPage(
          repository: repository,
          accountStorage: accountStorage,
          onLoggedIn: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 展开下拉面板
    await tester.tap(find.byTooltip('已记住的历史账号'));
    await tester.pumpAndSettle();

    // 点击删除 test_user
    final deleteButtons = find.byTooltip('删除此账号记录');
    expect(deleteButtons, findsNWidgets(2));
    await tester.tap(deleteButtons.at(1));
    await tester.pumpAndSettle();

    final remaining = await accountStorage.getSavedAccounts();
    expect(remaining, ['admin001']);
  });
}
