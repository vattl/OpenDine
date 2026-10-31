import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/presentation/cashier_bill_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeBillRepository implements CashierBillRepository {
  _FakeBillRepository(this.bills);

  final List<CashierBill> bills;

  @override
  Future<CashierBillResult> loadBills(CashierBillQuery query) async {
    return CashierBillResult(bills: bills, total: bills.length);
  }

  @override
  Future<CashierBillSummary> loadSummary() async {
    return const CashierBillSummary();
  }

  @override
  Future<CashierBill> loadBillDetail(CashierBill bill) async => bill;

  @override
  Future<void> printKitchen({
    required String orderNo,
    List<String> categoryIds = const [],
    bool isReprint = true,
  }) async {}

  @override
  Future<void> printReceipt({
    required String orderNo,
    int? orderId,
    String scenario = 'checkout',
  }) async {}

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'CHECKOUT',
    int? orderId,
    String? orderNo,
    String paperSize = '58mm',
  }) async {
    return PrintPreviewResult(
      scenario: scenario,
      scenarioName: '收银结账单',
      paperSize: paperSize,
      paperWidthMm: 58,
      paperWidthChars: 32,
      shopName: '测试烧烤店',
      totalTickets: 1,
      tickets: const [],
    );
  }

  @override
  Future<void> deleteBill(
    CashierBill bill, {
    String? account,
    String? password,
    String? approvalToken,
  }) async {}

  @override
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
    String? approvalToken,
  }) async {}

  @override
  Future<void> refundOrder({
    required String orderNo,
    String? transactionId,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {}

  @override
  Future<void> manualRefund({
    required String orderNo,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {}

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {}

  @override
  Future<CashierInvoiceResult> createInvoiceQrcode({
    required String orderNo,
    String? tableNumber,
    double? invoiceAmount,
    double? taxRate,
  }) async => CashierInvoiceResult(
        orderNo: orderNo,
        invoiceStatus: 'PENDING_SCAN',
        invoiceQrUrl: 'https://invoice.example.com/$orderNo',
        invoiceAmount: invoiceAmount ?? 0.0,
      );


  @override
  Future<CashierInvoiceDetails> loadInvoiceStatus(String orderNo) async {
    return CashierInvoiceDetails(
      orderNo: orderNo,
      hasInvoice: false,
      invoiceStatus: 'NONE',
      invoiceAmount: 0.0,
    );
  }

  @override
  Future<CashierAuditTimeline> loadAuditTimeline(String orderNo) async =>
      CashierAuditTimeline(orderNo: orderNo, events: const []);
}

class _MockApprovalRepo implements AccessApprovalRepository {
  _MockApprovalRepo({this.grantSuccess = true});

  final bool grantSuccess;
  String? lastPermission;
  String? lastBizType;

  @override
  final AdminApiClient client = AdminApiClient(
    baseUrl: 'http://fake',
    transport: FakeHttpTransport(const {}),
    token: 'fake',
  );

  @override
  Future<CashierApprovalGrant> authorize({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    required String authorizerAccount,
    required String credential,
    String authMethod = 'PASSWORD',
    String? requestId,
    String? terminalId,
  }) async {
    lastPermission = permission;
    lastBizType = bizType;
    if (!grantSuccess) {
      throw Exception('密码错误');
    }
    return CashierApprovalGrant(
      approvalNo: 'APP-PRIVACY-001',
      approvalToken: 'token-priv-123',
      permission: permission,
      operatorId: 2,
      authorizerId: 1,
      authorizerName: authorizerAccount,
      shopId: 1,
    );
  }

  @override
  Future<CashierQrApprovalRequest> createQrApproval({
    required String permission,
    String? bizType,
    String? bizId,
    double? amount,
    String? reason,
    String? requestId,
    String? terminalId,
  }) async => throw UnimplementedError();

  @override
  Future<CashierQrApprovalStatus> pollQrApprovalStatus(String approvalCode) async =>
      throw UnimplementedError();

  @override
  Future<CashierQrApprovalDetails> loadQrApprovalDetails(String approvalCode) async =>
      throw UnimplementedError();

  @override
  Future<CashierQrApprovalConfirmResult> confirmQrApproval({
    required String approvalCode,
    required String action,
    String? rejectReason,
  }) async => throw UnimplementedError();

  @override
  Future<AccessApprovalPage> listApprovals({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? bizType,
    int? shopId,
  }) async => const AccessApprovalPage();

  @override
  Future<AccessApprovalRecord?> loadApprovalDetail(int id) async => null;

  @override
  Future<List<RecentAuthor>> loadRecentAuthors({int limit = 10}) async => const [];

  @override
  Future<CashierAccessEvaluation> evaluate({
    required int userId,
    int? shopId,
    required String permission,
    Map<String, Object?>? context,
  }) async => const CashierAccessEvaluation(
    allow: true,
    approvalRequired: false,
    outcome: AuthorizationOutcome.allow,
  );
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  Widget buildTestApp({
    required CashierBillRepository repository,
    required AccessApprovalRepository approvalRepo,
    Set<String> permissions = const {},
    bool isSuperAdmin = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: CashierBillPage(
          repository: repository,
          approvalRepository: approvalRepo,
          permissions: permissions,
          isSuperAdmin: isSuperAdmin,
          currentAccount: 'cashier01',
        ),
      ),
    );
  }

  final testBill = CashierBill.fromJson({
    'id': 101,
    'order_no': '202610160001',
    'table_number': '06',
    'order_time': '2026-10-16 12:00:00',
    'pay_time': '2026-10-16 12:30:00',
    'transac_status': 'success',
    'sett_amount': '188.00',
    'member_name': '张三VIP',
    'member_phone': '13812345678',
    'member_balance': '500.00',
    'payment_method': '现金',
    'list': [
      {
        'id': 1,
        'name': '招牌牛肉',
        'quantity': 1,
        'unitprice': '188.00',
        'total_price': 188.00,
      }
    ],
  });

  testWidgets('默认展示脱敏手机号并渲染闭眼图标；具有 user:view 权限时直接切换明文与脱敏', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeBillRepository([testBill]);
    final approvalRepo = _MockApprovalRepo();

    await tester.pumpWidget(
      buildTestApp(
        repository: repo,
        approvalRepo: approvalRepo,
        permissions: {'user:view'},
      ),
    );
    await tester.pumpAndSettle();

    // 点击进入详情
    final detailBtn = find.text('详情');
    expect(detailBtn, findsOneWidget);
    await tester.tap(detailBtn);
    await tester.pumpAndSettle();

    // 默认展示脱敏手机号 138****5678
    expect(find.text('138****5678'), findsOneWidget);
    expect(find.text('13812345678'), findsNothing);

    // 闭眼图标
    final toggleBtn = find.byKey(const Key('bill-detail-toggle-phone-mask-btn'));
    expect(toggleBtn, findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);

    // 点击小眼睛：因拥有 user:view 权限，直接解密为明文
    await tester.tap(toggleBtn);
    await tester.pumpAndSettle();

    expect(find.text('13812345678'), findsOneWidget);
    expect(find.text('138****5678'), findsNothing);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);

    // 再次点击切回脱敏
    await tester.tap(toggleBtn);
    await tester.pumpAndSettle();

    expect(find.text('138****5678'), findsOneWidget);
    expect(find.text('13812345678'), findsNothing);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('无权限操作员点击小眼睛弹出店长现场审批弹窗，店长密码授权通过后放行解密', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeBillRepository([testBill]);
    final approvalRepo = _MockApprovalRepo(grantSuccess: true);

    // 不包含 user:view 权限
    await tester.pumpWidget(
      buildTestApp(
        repository: repo,
        approvalRepo: approvalRepo,
        permissions: {'order:view'},
      ),
    );
    await tester.pumpAndSettle();

    // 点击进入详情
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();

    expect(find.text('138****5678'), findsOneWidget);

    // 点击小眼睛
    final toggleBtn = find.byKey(const Key('bill-detail-toggle-phone-mask-btn'));
    await tester.tap(toggleBtn);
    await tester.pumpAndSettle();

    // 应该弹出审批弹窗：查看会员隐私信息审批
    expect(find.text('查看会员隐私信息审批'), findsOneWidget);
    expect(find.text('查看会员完整手机号'), findsOneWidget);

    // 输入店长账号与密码
    final accountFinder = find.byKey(const Key('approval-account'));
    final passwordFinder = find.byKey(const Key('approval-credential'));
    expect(accountFinder, findsOneWidget);
    expect(passwordFinder, findsOneWidget);

    await tester.enterText(accountFinder, 'manager');
    await tester.enterText(passwordFinder, '123456');
    await tester.pumpAndSettle();

    // 点击确认授权
    final confirmBtn = find.byKey(const Key('approval-submit'));
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    // 授权成功后弹窗关闭，手机号解密展示为明文
    expect(find.text('查看会员隐私信息审批'), findsNothing);
    expect(find.text('13812345678'), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('无权限操作员取消店长授权时保持脱敏隐藏并弹出提示', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repo = _FakeBillRepository([testBill]);
    final approvalRepo = _MockApprovalRepo();

    await tester.pumpWidget(
      buildTestApp(
        repository: repo,
        approvalRepo: approvalRepo,
        permissions: {'order:view'},
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();

    final toggleBtn = find.byKey(const Key('bill-detail-toggle-phone-mask-btn'));
    await tester.tap(toggleBtn);
    await tester.pumpAndSettle();

    expect(find.text('查看会员隐私信息审批'), findsOneWidget);

    // 点击取消
    final cancelBtn = find.byKey(const Key('approval-cancel'));
    expect(cancelBtn, findsOneWidget);
    await tester.tap(cancelBtn);
    await tester.pumpAndSettle();

    // 弹窗关闭，手机号保持脱敏
    expect(find.text('查看会员隐私信息审批'), findsNothing);
    expect(find.text('138****5678'), findsOneWidget);
    expect(find.text('13812345678'), findsNothing);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

    // 弹出 PosNotice 提示
    expect(find.text('未获得查看权限，已保持脱敏隐藏'), findsOneWidget);
  });
}
