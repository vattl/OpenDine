import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/presentation/cashier_bill_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/data/cashier_member_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/domain/cashier_member.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/presentation/cashier_member_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_member/presentation/member_consumption_dialog.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeMemberRepository implements CashierMemberRepository {
  _FakeMemberRepository();

  final CashierMemberProfile profile = const CashierMemberProfile(
    member: CashierMember(
      id: 88,
      name: '王小二',
      phone: '13888888888',
      level: 2,
      balance: 666.0,
      points: 1200,
    ),
    orderCount: 15,
    totalAmount: 3200.0,
    avgOrderValue: 213.33,
    tags: ['偏好微辣', '常点招牌牛肉'],
  );

  @override
  Future<void> bindOrder({required int orderId, required String phone}) async {}

  @override
  Future<List<MemberConsumptionRecord>> loadConsumption(String phone) async => const [
        MemberConsumptionRecord(
          id: 1,
          orderNo: 'ORD20261016001',
          amount: 168.0,
          paidAt: '2026-10-16 12:00',
          tableNumber: 'A08',
          paymentMethod: '现金',
          orderType: '堂食',
        ),
      ];

  @override
  Future<MemberConsumptionDetail> loadConsumptionDetail(
    MemberConsumptionRecord record,
  ) async {
    return MemberConsumptionDetail(record: record, lines: const []);
  }

  @override
  Future<CashierMemberProfile> loadProfile(String phone) async => profile;

  @override
  Future<List<MemberRechargeRecord>> loadRecharges(String phone) async => const [];

  @override
  Future<MemberRechargeResult> recharge({
    required String phone,
    required double amount,
    required double giftAmount,
  }) async =>
      const MemberRechargeResult(newBalance: 888.0);

  @override
  Future<PagedCashierMembers> loadMembers({
    required int page,
    int pageSize = 20,
    String query = '',
    String phone = '',
  }) async {
    return const PagedCashierMembers(
      rows: [
        CashierMemberRow(
          id: 88,
          name: '王小二',
          phone: '13888888888',
          level: 2,
          points: 1200,
          balance: 666.0,
          consumeAmount: 3200.0,
          lastConsumeTime: '2026-10-15 19:30:00',
        ),
      ],
      total: 1,
    );
  }

  @override
  Future<CashierMemberStats> loadStats() async => const CashierMemberStats();

  @override
  Future<PagedRechargeLogs> loadRechargeLogs({
    int page = 1,
    int pageSize = 20,
    String phone = '',
    String startTime = '',
    String endTime = '',
  }) async =>
      const PagedRechargeLogs(rows: [], total: 0);

  @override
  Future<List<CashierCoupon>> loadCoupons() async => const [];

  @override
  Future<int> batchSendCoupon({required int couponId}) async => 0;

  @override
  Future<List<CashierPersonaTag>> loadPersonaTags({
    String? phone,
    int? memberId,
  }) async =>
      const [];
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
      approvalNo: 'APP-PRIVACY-002',
      approvalToken: 'token-priv-456',
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
  }) async =>
      throw UnimplementedError();

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
  }) async =>
      throw UnimplementedError();

  @override
  Future<AccessApprovalPage> listApprovals({
    int page = 1,
    int pageSize = 20,
    String? status,
    String? bizType,
    int? shopId,
  }) async =>
      const AccessApprovalPage();

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

class _FakeBillRepository implements CashierBillRepository {
  _FakeBillRepository(this.bills);

  final List<CashierBill> bills;

  @override
  Future<CashierBillResult> loadBills(CashierBillQuery query) async {
    return CashierBillResult(bills: bills, total: bills.length);
  }

  @override
  Future<CashierBillSummary> loadSummary() async => const CashierBillSummary();

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

void main() {
  String? mockClipboardText;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    mockClipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        mockClipboardText = (call.arguments as Map?)?['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        return <String, Object?>{'text': mockClipboardText};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  final testBill = CashierBill.fromJson({
    'id': 202,
    'order_no': '202610160002',
    'table_number': '08',
    'order_time': '2026-10-16 12:00:00',
    'pay_time': '2026-10-16 12:30:00',
    'transac_status': 'success',
    'sett_amount': '256.00',
    'member_name': '王小二',
    'member_phone': '13888888888',
    'member_balance': '666.00',
    'payment_method': '微信支付',
    'list': [
      {
        'id': 1,
        'name': '烤羊肉串',
        'quantity': 10,
        'unitprice': '5.00',
        'total_price': 50.00,
      }
    ],
  });

  group('CashierMemberPage 会员隐私显隐与复制测试', () {
    testWidgets('默认展示脱敏手机号 138****8888，有权限时点击小眼睛切换明文与脱敏', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeMemberRepository();
      final approvalRepo = _MockApprovalRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierMemberPage(
              repository: repo,
              approvalRepository: approvalRepo,
              permissions: const {'user:view'},
              currentAccount: 'cashier01',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击列表中会员进入详情
      final memberCard = find.text('王小二');
      expect(memberCard, findsWidgets);
      await tester.tap(memberCard.first);
      await tester.pumpAndSettle();

      // 验证会员详情顶部手机号脱敏
      expect(find.byKey(const Key('member-detail-phone-text')), findsOneWidget);
      expect(find.text('138****8888'), findsOneWidget);
      expect(find.text('13888888888'), findsNothing);

      // 验证小眼睛和复制按钮均存在
      final eyeBtn = find.byKey(const Key('member-detail-toggle-phone-mask-btn'));
      final copyBtn = find.byKey(const Key('member-detail-copy-phone-btn'));
      expect(eyeBtn, findsOneWidget);
      expect(copyBtn, findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);

      // 点击小眼睛：直接明文展示
      await tester.tap(eyeBtn);
      await tester.pumpAndSettle();

      expect(find.text('13888888888'), findsOneWidget);
      expect(find.text('138****8888'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);

      // 再次点击小眼睛：切回脱敏
      await tester.tap(eyeBtn);
      await tester.pumpAndSettle();

      expect(find.text('138****8888'), findsOneWidget);
      expect(find.text('13888888888'), findsNothing);
    });

    testWidgets('无权限操作员点击小眼睛弹出店长现场审批弹窗，授权通过后放行解密', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeMemberRepository();
      final approvalRepo = _MockApprovalRepo(grantSuccess: true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierMemberPage(
              repository: repo,
              approvalRepository: approvalRepo,
              permissions: const {}, // 无 user:view
              currentAccount: 'cashier01',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('王小二').first);
      await tester.pumpAndSettle();

      expect(find.text('138****8888'), findsOneWidget);

      // 点击小眼睛
      final eyeBtn = find.byKey(const Key('member-detail-toggle-phone-mask-btn'));
      await tester.tap(eyeBtn);
      await tester.pumpAndSettle();

      // 弹出审批弹窗
      expect(find.text('查看会员隐私信息审批'), findsOneWidget);
      expect(find.text('查看会员完整手机号'), findsOneWidget);

      // 输入店长账号与密码
      final accountField = find.byKey(const Key('approval-account'));
      final pwdField = find.byKey(const Key('approval-credential'));
      expect(accountField, findsOneWidget);
      expect(pwdField, findsOneWidget);
      await tester.enterText(accountField, 'manager');
      await tester.enterText(pwdField, '123456');
      await tester.pumpAndSettle();

      // 点击确认授权
      final confirmBtn = find.byKey(const Key('approval-submit'));
      expect(confirmBtn, findsOneWidget);
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // 授权成功后解密为明文
      expect(find.text('13888888888'), findsOneWidget);
      expect(find.text('138****8888'), findsNothing);
    });

    testWidgets('点击复制按钮：有权限直接复制到剪贴板并提示', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeMemberRepository();
      final approvalRepo = _MockApprovalRepo(grantSuccess: true);

      // 先测试有权限直接复制
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierMemberPage(
              repository: repo,
              approvalRepository: approvalRepo,
              permissions: const {'user:view'},
              currentAccount: 'cashier01',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('王小二').first);
      await tester.pumpAndSettle();

      final copyBtn = find.byKey(const Key('member-detail-copy-phone-btn'));
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      // 验证提示与剪贴板内容
      expect(find.text('手机号已复制到剪贴板'), findsOneWidget);
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData?.text, '13888888888');
    });
  });

  group('CashierBillPage 账单详情复制按钮测试', () {
    testWidgets('账单详情展示复制按钮，有权限直接复制完整手机号', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final billRepo = _FakeBillRepository([testBill]);
      final approvalRepo = _MockApprovalRepo();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierBillPage(
              repository: billRepo,
              approvalRepository: approvalRepo,
              permissions: const {'user:view'},
              currentAccount: 'cashier01',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击进入详情
      await tester.tap(find.text('详情'));
      await tester.pumpAndSettle();

      // 验证复制按钮渲染
      final billCopyBtn = find.byKey(const Key('bill-detail-copy-phone-btn'));
      expect(billCopyBtn, findsOneWidget);

      await tester.tap(billCopyBtn);
      await tester.pumpAndSettle();

      expect(find.text('手机号已复制到剪贴板'), findsOneWidget);
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData?.text, '13888888888');
    });
  });

  group('MemberConsumptionDialog 消费记录手机号脱敏与复制测试', () {
    testWidgets('弹窗中展示脱敏手机号、小眼睛与复制按钮', (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _FakeMemberRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MemberConsumptionDialog(
              phone: '13888888888',
              repository: repo,
              permissions: const {'user:view'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证脱敏展示
      expect(find.text('138****8888'), findsOneWidget);

      final toggleEye = find.byKey(const Key('consumption-toggle-phone-mask-btn'));
      final copyBtn = find.byKey(const Key('consumption-copy-phone-btn'));
      expect(toggleEye, findsOneWidget);
      expect(copyBtn, findsOneWidget);

      // 点击小眼睛
      await tester.tap(toggleEye);
      await tester.pumpAndSettle();

      expect(find.text('13888888888'), findsOneWidget);

      // 点击复制
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      expect(clipboardData?.text, '13888888888');
    });
  });
}
