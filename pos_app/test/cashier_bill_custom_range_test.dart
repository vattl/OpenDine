import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/auth/data/access_approval_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/access_approval_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/data/real_cashier_bill_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/domain/cashier_bill.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/presentation/cashier_bill_date_range_dialog.dart';
import 'package:admin_panel_flutter/src/features/cashier_bills/presentation/cashier_bill_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _StubAccessApprovalRepository implements AccessApprovalRepository {
  @override
  final AdminApiClient client = AdminApiClient(
    baseUrl: 'http://fake',
    transport: FakeHttpTransport(const {}),
    token: 'token',
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
    throw UnimplementedError();
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
  Future<List<RecentAuthor>> loadRecentAuthors({int limit = 10}) async =>
      const [];

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

  Future<void> cancelQrApproval(String approvalCode) async =>
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

class _TestBillRepository implements CashierBillRepository {
  _TestBillRepository(this.bills);

  final List<CashierBill> bills;
  CashierBillQuery? lastQuery;

  @override
  Future<CashierBillResult> loadBills(CashierBillQuery query) async {
    lastQuery = query;
    return CashierBillResult(
      bills: bills,
      total: bills.length,
      summary: const CashierBillSummary(),
    );
  }

  @override
  Future<CashierBillSummary> loadSummary() async =>
      const CashierBillSummary();

  @override
  Future<CashierBill> loadBillDetail(CashierBill bill) async => bill;

  @override
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
    String? approvalToken,
  }) async {}

  @override
  Future<void> printReceipt({
    required String orderNo,
    int? orderId,
    String scenario = 'checkout',
  }) async {}

  @override
  Future<void> printKitchen({
    required String orderNo,
    List<String> categoryIds = const [],
  }) async {}

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
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {}

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'CHECKOUT',
    int? orderId,
    String? orderNo,
    String paperSize = '58mm',
  }) async => PrintPreviewResult(
        scenario: scenario,
        scenarioName: '收银结账单',
        paperSize: paperSize,
        paperWidthMm: 58,
        paperWidthChars: 32,
        shopName: '测试店',
        totalTickets: 1,
        tickets: const [],
      );

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

Widget _wrap(Widget child, {ThemeData? theme}) {
  return MaterialApp(
    theme: (theme ?? ThemeData.light()).copyWith(
      extensions: [CashierTokens.light],
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  group('CashierBillQuery & Time Range Domain', () {
    test('hasCustomTimeRange and timeRangeLabel reflect presets and custom ranges', () {
      final defaultQuery = const CashierBillQuery();
      expect(defaultQuery.hasCustomTimeRange, isFalse);
      expect(defaultQuery.timeRangeLabel, '默认时间 (最近3小时/未结)');

      final todayQuery = CashierBillQuery(
        startTime: DateTime(2026, 10, 15, 0, 0, 0),
        endTime: DateTime(2026, 10, 15, 23, 59, 59),
        datePreset: CashierDatePreset.today,
      );
      expect(todayQuery.hasCustomTimeRange, isTrue);
      expect(todayQuery.timeRangeLabel, '今日全天');

      final yesterdayQuery = CashierBillQuery(
        startTime: DateTime(2026, 10, 14, 0, 0, 0),
        endTime: DateTime(2026, 10, 14, 23, 59, 59),
        datePreset: CashierDatePreset.yesterday,
      );
      expect(yesterdayQuery.timeRangeLabel, '昨日全天');

      final weekQuery = CashierBillQuery(
        startTime: DateTime(2026, 10, 8, 0, 0, 0),
        endTime: DateTime(2026, 10, 15, 23, 59, 59),
        datePreset: CashierDatePreset.last7Days,
      );
      expect(weekQuery.timeRangeLabel, '近 7 天');

      final customQuery = CashierBillQuery(
        startTime: DateTime(2026, 10, 10, 9, 30),
        endTime: DateTime(2026, 10, 12, 18, 0),
        datePreset: CashierDatePreset.custom,
      );
      expect(customQuery.timeRangeLabel, '2026/10/10 至 2026/10/12');
    });

    test('copyWith unsets startTime and endTime correctly', () {
      final query = CashierBillQuery(
        startTime: DateTime(2026, 10, 15),
        endTime: DateTime(2026, 10, 15, 23),
      );
      expect(query.hasCustomTimeRange, isTrue);

      final cleared = query.copyWith(startTime: null, endTime: null);
      expect(cleared.startTime, isNull);
      expect(cleared.endTime, isNull);
      expect(cleared.hasCustomTimeRange, isFalse);
    });
  });

  group('RealCashierBillRepository Custom Time Range', () {
    test('sends formatted startTime & endTime to /cashier/order/today in yyyy/MM/dd', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/order/today': jsonEncode({
          'code': 200,
          'list': [
            {'id': 1001, 'transac_status': 'success', 'order_time': '2026-10-15 10:00:00'},
          ],
        }),
      });
      final repo = RealCashierBillRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          shopId: 8,
        ),
      );

      final result = await repo.loadBills(
        CashierBillQuery(
          startTime: DateTime(2026, 10, 15, 9, 0, 0),
          endTime: DateTime(2026, 10, 15, 21, 30, 0),
          datePreset: CashierDatePreset.today,
        ),
      );

      expect(result.bills.length, 1);
      final request = transport.requests.single;
      expect(request.uri.path, '/cashier/order/today');
      expect(request.uri.queryParameters['shopId'], '8');
      expect(request.uri.queryParameters['startTime'], '2026/10/15');
      expect(request.uri.queryParameters['endTime'], '2026/10/15');
    });

    test('translates 403 admin:super permission error into user-friendly ApiException', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/order/today': jsonEncode({
          'code': 403,
          'msg': '无权限：admin:super',
        }),
      });
      final repo = RealCashierBillRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          shopId: 8,
        ),
      );

      expect(
        () => repo.loadBills(
          CashierBillQuery(
            startTime: DateTime(2026, 10, 15, 0, 0, 0),
            endTime: DateTime(2026, 10, 15, 23, 59, 59),
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('超级管理员权限(admin:super)'),
          ),
        ),
      );
    });

    test('when keyword is present, routes to /cashier/order/search with time range', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/order/search': jsonEncode({
          'code': 200,
          'data': {
            'rows': [
              {'id': 1002, 'tableNumber': '03', 'transac_status': 'success'},
            ],
            'totalCount': '1',
          },
        }),
      });
      final repo = RealCashierBillRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          shopId: 8,
        ),
      );

      final result = await repo.loadBills(
        CashierBillQuery(
          keyword: '03',
          startTime: DateTime(2026, 10, 15, 0, 0, 0),
          endTime: DateTime(2026, 10, 15, 23, 59, 59),
        ),
      );

      expect(result.bills.length, 1);
      final request = transport.requests.single;
      expect(request.uri.path, '/cashier/order/search');
      expect(request.uri.queryParameters['keyword'], '03');
      expect(request.uri.queryParameters.containsKey('startTime'), isTrue);
      expect(request.uri.queryParameters.containsKey('endTime'), isTrue);
    });
  });

  group('CashierBillDateRangeDialog Widget Tests', () {
    testWidgets('renders presets, pickers, and validates input range', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CashierBillDateRangeResult? dialogResult;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                dialogResult = await showDialog<CashierBillDateRangeResult>(
                  context: context,
                  builder: (_) => const CashierBillDateRangeDialog(
                    initialQuery: CashierBillQuery(),
                    hasSuperPermission: false,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Verify header & super-admin notice
      expect(find.text('选择账单查询时间范围'), findsOneWidget);
      expect(find.textContaining('需要超级管理员权限 (admin:super)'), findsOneWidget);

      // Verify presets
      expect(find.byKey(const Key('preset-default')), findsOneWidget);
      expect(find.byKey(const Key('preset-today-full')), findsOneWidget);
      expect(find.byKey(const Key('preset-yesterday')), findsOneWidget);
      expect(find.byKey(const Key('preset-last-7-days')), findsOneWidget);

      // Click "今日全天"
      await tester.tap(find.byKey(const Key('preset-today-full')));
      await tester.pumpAndSettle();

      // Confirm
      await tester.tap(find.byKey(const Key('btn-confirm-date-dialog')));
      await tester.pumpAndSettle();

      expect(dialogResult, isNotNull);
      expect(dialogResult!.preset, CashierDatePreset.today);
      expect(dialogResult!.startTime, isNotNull);
      expect(dialogResult!.endTime, isNotNull);
    });

    testWidgets('validates end time cannot be before start time', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          CashierBillDateRangeDialog(
            initialQuery: CashierBillQuery(
              startTime: DateTime(2026, 10, 15, 12, 0),
              endTime: DateTime(2026, 10, 15, 8, 0), // invalid!
              datePreset: CashierDatePreset.custom,
            ),
            hasSuperPermission: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Notice should be hidden when hasSuperPermission is true
      expect(find.textContaining('需要超级管理员权限'), findsNothing);

      // Click confirm with invalid range
      await tester.tap(find.byKey(const Key('btn-confirm-date-dialog')));
      await tester.pumpAndSettle();

      // Error banner must be visible
      expect(find.byKey(const Key('date-range-error-banner')), findsOneWidget);
      expect(find.text('结束时间不能早于开始时间'), findsOneWidget);
    });

    testWidgets('validates time span cannot exceed 31 days', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          CashierBillDateRangeDialog(
            initialQuery: CashierBillQuery(
              startTime: DateTime(2026, 8, 1, 0, 0),
              endTime: DateTime(2026, 10, 1, 0, 0), // 61 days!
              datePreset: CashierDatePreset.custom,
            ),
            hasSuperPermission: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn-confirm-date-dialog')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('date-range-error-banner')), findsOneWidget);
      expect(find.text('自定义时间范围不能超过31天'), findsOneWidget);
    });
  });

  group('CashierBillPage Top Filter Bar Time Range Integration', () {
    testWidgets('shows button and active chip with clear functionality', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _TestBillRepository([
        CashierBill.fromJson({
          'id': 1,
          'order_no': 'A001',
          'transac_status': 'success',
          'sett_amount': 88.0,
        }),
      ]);

      await tester.pumpWidget(
        _wrap(
          CashierBillPage(
            repository: repo,
            approvalRepository: _StubAccessApprovalRepository(),
            isSuperAdmin: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initially shows '时间范围' inactive button
      expect(find.byKey(const Key('btn-open-date-range')), findsOneWidget);
      expect(find.byKey(const Key('chip-active-time-range')), findsNothing);

      // Open dialog
      await tester.tap(find.byKey(const Key('btn-open-date-range')));
      await tester.pumpAndSettle();

      // Click "昨日全天" preset
      await tester.tap(find.byKey(const Key('preset-yesterday')));
      await tester.pumpAndSettle();

      // Click confirm
      await tester.tap(find.byKey(const Key('btn-confirm-date-dialog')));
      await tester.pumpAndSettle();

      // Dialog closed, active chip should now be visible with "昨日全天"
      expect(find.byKey(const Key('chip-active-time-range')), findsOneWidget);
      expect(find.text('昨日全天'), findsOneWidget);
      expect(repo.lastQuery?.datePreset, CashierDatePreset.yesterday);
      expect(repo.lastQuery?.hasCustomTimeRange, isTrue);

      // Click clear button on the active chip
      await tester.tap(find.byKey(const Key('btn-clear-date-range')));
      await tester.pumpAndSettle();

      // Back to default
      expect(find.byKey(const Key('btn-open-date-range')), findsOneWidget);
      expect(find.byKey(const Key('chip-active-time-range')), findsNothing);
      expect(repo.lastQuery?.hasCustomTimeRange, isFalse);
    });
  });
}
