import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/presentation/cashier_bill_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/occupied_table_view.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_notice_dialog.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'fake_http_transport.dart';

class _FakeAccessApprovalRepository implements AccessApprovalRepository {
  @override
  final AdminApiClient client = AdminApiClient(
    baseUrl: 'http://fake',
    transport: FakeHttpTransport(const {}),
    token: 'fake-token',
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
    return CashierApprovalGrant(
      approvalNo: 'APP-2026-TEST',
      approvalToken: 'fake-approval-token',
      permission: permission,
      operatorId: 1,
      authorizerId: 9,
      authorizerName: authorizerAccount,
      shopId: 1,
      expireSeconds: 120,
    );
  }

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

class _FakeBillRepo implements CashierBillRepository {
  _FakeBillRepo(this.bills);
  final List<CashierBill> bills;
  final List<String> unCheckedOrders = [];

  @override
  Future<CashierBillResult> loadBills(CashierBillQuery query) async {
    return CashierBillResult(bills: bills, total: bills.length);
  }

  @override
  Future<CashierBillSummary> loadSummary() async => const CashierBillSummary();

  @override
  Future<CashierBill> loadBillDetail(CashierBill bill) async => bill;

  @override
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
    String? approvalToken,
  }) async {
    unCheckedOrders.add(orderNo);
  }

  @override
  Future<void> deleteBill(
    CashierBill bill, {
    String? account,
    String? password,
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
  Future<void> verifyPassword({required String username, required String password}) async {}

  @override
  Future<void> printKitchen({required String orderNo, List<String> categoryIds = const []}) async {}

  @override
  Future<void> printReceipt({required String orderNo, int? orderId, String scenario = 'checkout'}) async {}

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'CHECKOUT',
    int? orderId,
    String? orderNo,
    String paperSize = '58mm',
  }) async {
    return const PrintPreviewResult(
      scenario: 'CHECKOUT',
      scenarioName: '结账单',
      paperSize: '58mm',
      paperWidthMm: 58,
      paperWidthChars: 32,
      shopName: '测试烧烤店',
      totalTickets: 0,
      tickets: [],
    );
  }

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
  group('Cashier Lifecycle Safeguards Tests', () {
    test('CashierBill.fromJson parses isDailySettled from various fields', () {
      final b1 = CashierBill.fromJson({
        'id': 1,
        'order_no': 'ORD001',
        'transac_status': 'success',
        'is_daily_settled': true,
      });
      expect(b1.isDailySettled, isTrue);

      final b2 = CashierBill.fromJson({
        'id': 2,
        'order_no': 'ORD002',
        'transac_status': 'success',
        'daily_settled': true,
      });
      expect(b2.isDailySettled, isTrue);

      final b3 = CashierBill.fromJson({
        'id': 3,
        'order_no': 'ORD003',
        'transac_status': 'success',
        'daily_stat_id': 888,
      });
      expect(b3.isDailySettled, isTrue);

      final b4 = CashierBill.fromJson({
        'id': 4,
        'order_no': 'ORD004',
        'transac_status': 'success',
        'is_daily_settled': false,
      });
      expect(b4.isDailySettled, isFalse);
    });

    testWidgets('Scenario 4: isDailySettled bill disables uncheckout with tooltip', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final settledBill = CashierBill.fromJson({
        'id': 1,
        'order_no': 'ORD-SETTLED-001',
        'table_number': 'A01',
        'transac_status': 'success',
        'sett_amount': 88.0,
        'is_daily_settled': true,
      });
      final repo = _FakeBillRepo([settledBill]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierBillPage(
              repository: repo,
              approvalRepository: _FakeAccessApprovalRepository(),
              permissions: const {'order:operate:reopen', 'order:operate', 'cashier:operate'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ORD-SETTLED-001'), findsOneWidget);
      await tester.tap(find.text('ORD-SETTLED-001'));
      await tester.pumpAndSettle();

      final uncheckoutFinder = find.widgetWithText(OutlinedButton, '反结账');
      expect(uncheckoutFinder, findsOneWidget);
      final button = tester.widget<OutlinedButton>(uncheckoutFinder);
      expect(button.onPressed, isNull);

      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == '该账单所属营业日已完成日结封账，根据财务合规要求禁止反结账',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Scenario 4: non-daily settled bill enables uncheckout', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final normalBill = CashierBill.fromJson({
        'id': 2,
        'order_no': 'ORD-ACTIVE-002',
        'table_number': 'A02',
        'transac_status': 'success',
        'sett_amount': 66.0,
        'is_daily_settled': false,
      });
      final repo = _FakeBillRepo([normalBill]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierBillPage(
              repository: repo,
              approvalRepository: _FakeAccessApprovalRepository(),
              permissions: const {'order:operate:reopen', 'order:operate', 'cashier:operate'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ORD-ACTIVE-002'), findsOneWidget);
      await tester.tap(find.text('ORD-ACTIVE-002'));
      await tester.pumpAndSettle();

      final uncheckoutFinder = find.widgetWithText(OutlinedButton, '反结账');
      expect(uncheckoutFinder, findsOneWidget);
      final button = tester.widget<OutlinedButton>(uncheckoutFinder);
      expect(button.onPressed, isNotNull);
    });

    testWidgets('Scenario 2: Cash button displays 未开班 badge when drawer is closed', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const order = PosOrder(
        id: 1,
        orderNo: 'ORD-001',
        tableNumber: 'A01',
        diners: 2,
        total: 100.0,
        grossAmount: 100.0,
        createdAt: null,
        lines: [],
      );
      const workspace = PosWorkspace(
        table: DiningTable(number: 'A01', status: TableStatus.pending, people: 2),
        currentOrder: order,
        categories: [],
        dishes: [],
        paymentMethods: [
          PosPaymentMethod(id: 1, code: 'cash', name: '现金', sortOrder: 1, enabled: true),
          PosPaymentMethod(id: 2, code: 'wechat', name: '微信', sortOrder: 2, enabled: true),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OccupiedTableView(
              workspace: workspace,
              busy: false,
              isDrawerOpen: false,
              paymentMethods: workspace.paymentMethods,
              onBack: () {},
              onAddDishes: ([_]) {},
              onMerge: () {},
              onTransfer: ([_]) {},
              onClear: () {},
              onRefund: (_) {},
              onGift: (_) {},
              onDiscount: ([_]) {},
              onPrintReceipt: (_, [_]) {},
              onCheckout: (_) {},
              onBalanceCheckout: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未开班'), findsOneWidget);
    });

    testWidgets('Scenario 2: Cash button hides 未开班 badge when drawer is open', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const order = PosOrder(
        id: 1,
        orderNo: 'ORD-001',
        tableNumber: 'A01',
        diners: 2,
        total: 100.0,
        grossAmount: 100.0,
        createdAt: null,
        lines: [],
      );
      const workspace = PosWorkspace(
        table: DiningTable(number: 'A01', status: TableStatus.pending, people: 2),
        currentOrder: order,
        categories: [],
        dishes: [],
        paymentMethods: [
          PosPaymentMethod(id: 1, code: 'cash', name: '现金', sortOrder: 1, enabled: true),
          PosPaymentMethod(id: 2, code: 'wechat', name: '微信', sortOrder: 2, enabled: true),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OccupiedTableView(
              workspace: workspace,
              busy: false,
              isDrawerOpen: true,
              paymentMethods: workspace.paymentMethods,
              onBack: () {},
              onAddDishes: ([_]) {},
              onMerge: () {},
              onTransfer: ([_]) {},
              onClear: () {},
              onRefund: (_) {},
              onGift: (_) {},
              onDiscount: ([_]) {},
              onPrintReceipt: (_, [_]) {},
              onCheckout: (_) {},
              onBalanceCheckout: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未开班'), findsNothing);
    });

    testWidgets('Scenario 3: 40935 WeChat Native friendly notice renders correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showPosNotice(
                    context,
                    title: '微信支付进行中',
                    message: '顾客正处于微信扫码界面，请先点击【取消微信支付】并确认顾客未付款，再进行手工结账。',
                    tone: PosNoticeTone.warning,
                  );
                },
                child: const Text('Trigger 40935 Notice'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Trigger 40935 Notice'));
      await tester.pumpAndSettle();

      expect(find.text('微信支付进行中'), findsOneWidget);
      expect(
        find.text('顾客正处于微信扫码界面，请先点击【取消微信支付】并确认顾客未付款，再进行手工结账。'),
        findsOneWidget,
      );
    });

    testWidgets('Scenario 1: Closed store guard dialog renders correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      title: const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 28),
                          SizedBox(width: 10),
                          Text('门店暂未营业', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      content: const Text(
                        '当前门店处于打烊状态，请先开启营业再进行点餐开台。',
                        style: TextStyle(fontSize: 15, height: 1.5),
                      ),
                      actions: [
                        OutlinedButton(
                          key: const Key('closed-guard-force-button'),
                          onPressed: () => Navigator.of(ctx).pop('force'),
                          child: const Text('店长特权开单 (Force)'),
                        ),
                        FilledButton(
                          key: const Key('closed-guard-open-button'),
                          onPressed: () => Navigator.of(ctx).pop('open'),
                          child: const Text('前往开启营业'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show Guard'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show Guard'));
      await tester.pumpAndSettle();

      expect(find.text('门店暂未营业'), findsOneWidget);
      expect(find.text('当前门店处于打烊状态，请先开启营业再进行点餐开台。'), findsOneWidget);
      expect(find.text('店长特权开单 (Force)'), findsOneWidget);
      expect(find.text('前往开启营业'), findsOneWidget);
    });

    testWidgets('Scenario 5: 4001 Daily settlement intercept dialog renders correctly', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      title: const Row(
                        children: [
                          Icon(Icons.calendar_month_outlined, color: Color(0xFFF59E0B), size: 28),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '无法开启营业：前一营业日尚未日结',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      content: const Text(
                        '系统检测到前一营业日仍有未完成的日结封账，为保障财务账目连贯，请先完成前日日结。',
                        style: TextStyle(fontSize: 15, height: 1.5),
                      ),
                      actions: [
                        OutlinedButton(
                          key: const Key('daily-block-force-open-button'),
                          onPressed: () => Navigator.of(ctx).pop('force'),
                          child: const Text('紧急强制开门 (需主管权限)'),
                        ),
                        FilledButton(
                          key: const Key('daily-block-go-settle-button'),
                          onPressed: () => Navigator.of(ctx).pop('settle'),
                          child: const Text('立即前往日结'),
                        ),
                      ],
                    ),
                  );
                },
                child: const Text('Show 4001 Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Show 4001 Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('无法开启营业：前一营业日尚未日结'), findsOneWidget);
      expect(find.textContaining('前一营业日仍有未完成的日结封账'), findsOneWidget);
      expect(find.text('紧急强制开门 (需主管权限)'), findsOneWidget);
      expect(find.text('立即前往日结'), findsOneWidget);
    });
  });
}
