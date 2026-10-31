import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/cashier_payment_repository.dart';
import 'package:admin_panel_flutter/src/features/receivable_management/data/receivable_management_repository.dart';
import 'package:admin_panel_flutter/src/features/receivable_management/domain/receivable_account_model.dart';
import 'package:admin_panel_flutter/src/features/receivable_management/presentation/receivable_management_page.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';

class MockCashierSettingsRepository implements CashierSettingsRepository {
  @override
  Future<CashierSettingsOverview> loadSettingsOverview() async {
    return const CashierSettingsOverview(
      shopId: 1,
      modules: [
        CashierSettingsModule(
          module: 'store',
          permission: 'settings:view',
          permitted: true,
          source: 'SHOP',
          summary: '测试店铺',
          alerts: 0,
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MockCashierPaymentRepository implements CashierPaymentRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeReceivableManagementRepository implements ReceivableManagementRepository {
  FakeReceivableManagementRepository({
    this.accounts = const [],
    this.aging = const ReceivableAgingSummary(),
    this.statements = const [],
    this.claims = const [],
  });

  List<ReceivableAccountModel> accounts;
  ReceivableAgingSummary aging;
  List<ReceivableStatementItem> statements;
  List<ReceivableClaimModel> claims;

  bool deleteCalled = false;
  int? deletedId;

  bool collectCalled = false;
  int? collectedClaimId;
  int? collectedAmountFen;
  String? collectedChannel;

  bool writeOffCalled = false;
  int? writtenOffClaimId;
  String? writeOffReason;

  bool reverseCalled = false;
  int? reversedClaimId;
  String? reverseReason;

  bool verifyPasswordCalled = false;

  @override
  AdminApiClient get client => throw UnimplementedError();

  @override
  Future<List<ReceivableAccountModel>> fetchAccounts({
    String? status,
    String? keyword,
    int page = 1,
    int pageSize = 50,
  }) async {
    return accounts;
  }

  @override
  Future<ReceivableAgingSummary> fetchAging() async {
    return aging;
  }

  @override
  Future<List<ReceivableClaimModel>> fetchClaims({
    int? accountId,
    String? status,
    int page = 1,
    int pageSize = 50,
  }) async {
    return claims.where((c) {
      if (accountId != null && accountId > 0 && c.accountId != accountId) {
        return false;
      }
      if (status != null && status != 'ALL' && c.status != status) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  Future<Map<String, Object?>> collectClaim({
    required int claimId,
    required int amountFen,
    required String channel,
    required String requestId,
    String? note,
    String? drawerSessionId,
  }) async {
    collectCalled = true;
    collectedClaimId = claimId;
    collectedAmountFen = amountFen;
    collectedChannel = channel;
    return {'collected': true, 'amountFen': amountFen};
  }

  @override
  Future<Map<String, Object?>> writeOffClaim({
    required int claimId,
    required String reason,
    required String requestId,
  }) async {
    writeOffCalled = true;
    writtenOffClaimId = claimId;
    writeOffReason = reason;
    return {'writtenOff': true};
  }

  @override
  Future<Map<String, Object?>> reverseClaim({
    required int claimId,
    required String reason,
    required String requestId,
  }) async {
    reverseCalled = true;
    reversedClaimId = claimId;
    reverseReason = reason;
    return {'reversed': true};
  }

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    verifyPasswordCalled = true;
  }

  @override
  Future<Map<String, Object?>> deleteAccount(int id) async {
    deleteCalled = true;
    deletedId = id;
    return {'deleted': true, 'closed': false};
  }

  @override
  Future<List<ReceivableStatementItem>> fetchStatement(int id, {int limit = 100}) async {
    return statements;
  }

  @override
  Future<ReceivableAccountModel> createAccount(ReceivableAccountFormData form) async {
    final acc = ReceivableAccountModel(
      id: 99,
      accountNo: 'ARA099',
      scopeType: form.scopeType,
      customerType: form.customerType,
      customerName: form.customerName,
      creditLimitFen: form.creditLimitFen,
      outstandingFen: 0,
      paymentTermsDays: form.paymentTermsDays,
      status: 'ACTIVE',
    );
    accounts.add(acc);
    return acc;
  }

  @override
  Future<ReceivableAccountModel> updateAccount(int id, ReceivableAccountFormData form) async {
    return accounts.firstWhere((a) => a.id == id);
  }

  @override
  Future<ReceivableAccountModel> updateAccountStatus(int id, String status) async {
    return accounts.firstWhere((a) => a.id == id);
  }

  @override
  Future<ReceivableAccountModel> closeAccount(int id) async {
    return accounts.firstWhere((a) => a.id == id);
  }
}

void main() {
  final testAccounts = [
    const ReceivableAccountModel(
      id: 1,
      accountNo: 'ARA001',
      scopeType: 'MERCHANT',
      customerType: 'COMPANY',
      customerName: '万达商管餐饮部',
      contactName: '王经理',
      contactPhone: '13800138000',
      taxNo: '91110105MA00ABCD12',
      creditLimitFen: 5000000, // 50,000.00
      outstandingFen: 1420000, // 14,200.00 (has balance)
      paymentTermsDays: 30,
      status: 'ACTIVE',
    ),
    const ReceivableAccountModel(
      id: 2,
      accountNo: 'ARA002',
      scopeType: 'SHOP',
      customerType: 'PERSONAL',
      customerName: '老费烧烤VIP李总',
      contactName: '李建国',
      contactPhone: '13911223344',
      creditLimitFen: 500000, // 5,000.00
      outstandingFen: 0, // 0.00 (zero balance)
      paymentTermsDays: 15,
      status: 'ACTIVE',
    ),
  ];

  final testClaims = [
    const ReceivableClaimModel(
      id: 201,
      claimNo: 'CLM20261019001',
      orderNo: 'ORDER20261019001',
      accountId: 1,
      customerName: '万达商管餐饮部',
      originalAmountFen: 80000,
      outstandingFen: 80000,
      status: 'OPEN',
      dueDate: '2026-11-19',
      overdueDays: 0,
    ),
    const ReceivableClaimModel(
      id: 202,
      claimNo: 'CLM20261019002',
      orderNo: 'ORDER20261019002',
      accountId: 1,
      customerName: '万达商管餐饮部',
      originalAmountFen: 100000,
      outstandingFen: 62000,
      status: 'PARTIAL',
      dueDate: '2026-10-15',
      overdueDays: 7,
    ),
  ];

  group('WI-050 Receivable Management Tests', () {
    testWidgets('S01: 普通用户不显示挂账管理入口', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeSettings = MockCashierSettingsRepository();
      final fakePayment = MockCashierPaymentRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsPage(
              repository: fakeSettings,
              paymentRepository: fakePayment,
              storeName: '测试分店',
              kdsAvailable: false,
              permissions: const {'order:view'}, // 无 receivable:view 权限
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-tile-挂账管理')), findsNothing);
    });

    testWidgets('S02: 拥有 receivable:view 权限时渲染挂账管理入口', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeSettings = MockCashierSettingsRepository();
      final fakePayment = MockCashierPaymentRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierSettingsPage(
              repository: fakeSettings,
              paymentRepository: fakePayment,
              storeName: '测试分店',
              kdsAvailable: false,
              permissions: const {'receivable:view'}, // 拥有权限
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings-tile-挂账管理')), findsOneWidget);
    });

    testWidgets('S03: 无权限访问 ReceivableManagementPage 弹出 403 屏障', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(accounts: testAccounts);
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'order:view'}, // 无权限
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-forbidden-barrier')), findsOneWidget);
      expect(find.text('403 无权访问挂账管理'), findsOneWidget);
    });

    testWidgets('S04: 授权访问 ReceivableManagementPage 完整渲染看板与账户列表', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(accounts: testAccounts);
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-forbidden-barrier')), findsNothing);
      expect(find.text('挂账系统管理'), findsOneWidget);
      expect(find.text('万达商管餐饮部'), findsOneWidget);
      expect(find.text('老费烧烤VIP李总'), findsOneWidget);
      expect(find.text('授信客户总数'), findsOneWidget);
      expect(find.text('当前未清应收总额'), findsOneWidget);
    });

    testWidgets('S05: 有未清余额账户点击删除被阻断拦截', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(accounts: testAccounts);
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击第 1 个账户（万达商管，有未清 14,200.00）的删除按钮
      final deleteBtn = find.byKey(const Key('receivable-account-delete-button-1'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // 验证阻断弹窗
      expect(find.text('无法删除挂账账户'), findsOneWidget);
      expect(find.textContaining('当前仍有未清挂账欠款 ¥14200.00'), findsOneWidget);
      expect(find.text('我知道了'), findsOneWidget);

      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
      expect(fakeRepo.deleteCalled, isFalse);
    });

    testWidgets('S06: 零未清余额账户确认后成功调用删除', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(accounts: testAccounts);
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击第 2 个账户（李总，零欠款）的删除按钮
      final deleteBtn = find.byKey(const Key('receivable-account-delete-button-2'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      // 验证二次确认弹窗
      expect(find.text('确认删除或注销账户？'), findsOneWidget);
      expect(find.text('确认删除/注销'), findsOneWidget);

      await tester.tap(find.text('确认删除/注销'));
      await tester.pumpAndSettle();

      expect(fakeRepo.deleteCalled, isTrue);
      expect(fakeRepo.deletedId, equals(2));
    });

    testWidgets('S07: 点击对账单展示对账流水弹窗', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        statements: [
          const ReceivableStatementItem(
            id: 101,
            entryType: 'CHARGE',
            amountFen: 80000,
            orderNo: 'ORDER20261019001',
            createdAt: '2026-10-19 12:00:00',
            note: '午市招待挂账',
          ),
          const ReceivableStatementItem(
            id: 102,
            entryType: 'COLLECTION',
            amountFen: 50000,
            orderNo: 'ORDER20261019001',
            createdAt: '2026-10-19 14:00:00',
            note: '对公转账还款',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final statementBtn = find.byKey(const Key('receivable-account-statement-button-1'));
      expect(statementBtn, findsOneWidget);
      await tester.tap(statementBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-statement-dialog')), findsOneWidget);
      expect(find.textContaining('客户对账单流水 · 万达商管餐饮部'), findsOneWidget);
      expect(find.text('挂账增加'), findsOneWidget);
      expect(find.text('回款冲减'), findsOneWidget);
      expect(find.text('+¥800.00'), findsOneWidget);
      expect(find.text('-¥500.00'), findsOneWidget);
    });

    testWidgets('S08: 点击逾期应收指标卡弹出5级账龄深度分析弹窗', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        aging: const ReceivableAgingSummary(
          currentFen: 50000,
          days1To30Fen: 30000,
          days31To60Fen: 20000,
          days61To90Fen: 10000,
          days90PlusFen: 5000,
          totalOutstandingFen: 115000,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final agingCard = find.byKey(const Key('receivable-aging-metric-card'));
      expect(agingCard, findsOneWidget);
      await tester.tap(agingCard);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-aging-breakdown-dialog')), findsOneWidget);
      expect(find.text('5级应收账龄深度分析'), findsOneWidget);
      expect(find.text('正常未到期 (Current)'), findsOneWidget);
      expect(find.text('逾期 1~30 天'), findsOneWidget);
      expect(find.text('逾期 31~60 天'), findsOneWidget);
      expect(find.text('逾期 61~90 天'), findsOneWidget);
      expect(find.text('逾期 90+ 天 (严重呆账)'), findsOneWidget);
    });

    testWidgets('S09: 切换到借据Tab展示应收借据列表与操作入口', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        claims: testClaims,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final claimsTab = find.byKey(const Key('receivable-tab-claims'));
      expect(claimsTab, findsOneWidget);
      await tester.tap(claimsTab);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-claim-row-201')), findsOneWidget);
      expect(find.byKey(const Key('receivable-claim-row-202')), findsOneWidget);
      expect(find.text('CLM20261019001'), findsOneWidget);
      expect(find.text('CLM20261019002'), findsOneWidget);
    });

    testWidgets('S10: 登记收款弹窗并成功提交回款', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        claims: testClaims,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receivable-tab-claims')));
      await tester.pumpAndSettle();

      final collectBtn = find.byKey(const Key('receivable-claim-collect-button-201'));
      expect(collectBtn, findsOneWidget);
      await tester.tap(collectBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-collect-dialog')), findsOneWidget);
      expect(find.text('登记挂账回款'), findsOneWidget);

      await tester.tap(find.byKey(const Key('receivable-collect-submit-btn')));
      await tester.pumpAndSettle();

      expect(fakeRepo.collectCalled, isTrue);
      expect(fakeRepo.collectedClaimId, equals(201));
      expect(fakeRepo.collectedAmountFen, equals(80000));
    });

    testWidgets('S11: 超管权限直接提交坏账核销', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        claims: testClaims,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage', 'admin:super'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receivable-tab-claims')));
      await tester.pumpAndSettle();

      final writeoffBtn = find.byKey(const Key('receivable-claim-writeoff-button-201'));
      expect(writeoffBtn, findsOneWidget);
      await tester.tap(writeoffBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-writeoff-dialog')), findsOneWidget);
      expect(find.text('呆账坏账核销'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('receivable-writeoff-reason-input')), '企业破产诉讼终结');
      await tester.tap(find.byKey(const Key('receivable-writeoff-submit-btn')));
      await tester.pumpAndSettle();

      expect(fakeRepo.writeOffCalled, isTrue);
      expect(fakeRepo.writtenOffClaimId, equals(201));
      expect(fakeRepo.writeOffReason, equals('企业破产诉讼终结'));
    });

    testWidgets('S12: 借据冲正撤销流程', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        claims: testClaims,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage', 'admin:super'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receivable-tab-claims')));
      await tester.pumpAndSettle();

      final reverseBtn = find.byKey(const Key('receivable-claim-reverse-button-201'));
      expect(reverseBtn, findsOneWidget);
      await tester.tap(reverseBtn);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('receivable-reverse-dialog')), findsOneWidget);
      expect(find.text('挂账借据冲正撤销'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('receivable-reverse-reason-input')), '收银员误操作');
      await tester.tap(find.byKey(const Key('receivable-reverse-submit-btn')));
      await tester.pumpAndSettle();

      expect(fakeRepo.reverseCalled, isTrue);
      expect(fakeRepo.reversedClaimId, equals(201));
      expect(fakeRepo.reverseReason, equals('收银员误操作'));
    });

    testWidgets('S13: 对账单弹窗支持导出CSV', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        statements: [
          const ReceivableStatementItem(
            id: 101,
            entryType: 'CHARGE',
            amountFen: 80000,
            orderNo: 'ORDER20261019001',
            createdAt: '2026-10-19 12:00:00',
            note: '午市招待挂账',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('receivable-account-statement-button-1')));
      await tester.pumpAndSettle();

      final exportBtn = find.byKey(const Key('receivable-statement-export-csv-btn'));
      expect(exportBtn, findsOneWidget);
      await tester.tap(exportBtn);
      await tester.pump();

      expect(find.textContaining('对账单已成功导出'), findsOneWidget);
    });

    testWidgets('S14: 账户列表点击查看借据快捷联动并自动过滤', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fakeRepo = FakeReceivableManagementRepository(
        accounts: testAccounts,
        claims: testClaims,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ReceivableManagementPage(
            repository: fakeRepo,
            permissions: const {'receivable:view', 'receivable:manage'},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewClaimsBtn = find.byKey(const Key('receivable-account-claims-button-1'));
      expect(viewClaimsBtn, findsOneWidget);
      await tester.tap(viewClaimsBtn);
      await tester.pumpAndSettle();

      expect(find.textContaining('筛选客户: 万达商管餐饮部'), findsOneWidget);
      expect(find.byKey(const Key('receivable-claim-row-201')), findsOneWidget);
    });
  });
}
