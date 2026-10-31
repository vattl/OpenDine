import 'package:admin_panel_flutter/src/features/cashier_shift/data/cashier_shift_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/presentation/cashier_shift_workbench.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDailySequenceRepository implements CashierShiftRepository {
  _FakeDailySequenceRepository({
    this.precheckResult,
  });

  DailyPrecheckResult? precheckResult;
  CashierZReportHistoryPage? zReportsPage;
  int precheckCalls = 0;
  String? lastPrecheckStatDate;

  @override
  Future<DailyPrecheckResult> loadDailyContext({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => precheckDaily(statDate: statDate, shopId: shopId, minutes: minutes);

  @override
  Future<DailyPrecheckResult> precheckDaily({
    String? statDate,
    int? shopId,
    int? minutes,
  }) async {
    precheckCalls++;
    lastPrecheckStatDate = statDate;
    return precheckResult ??
        DailyPrecheckResult(
          canSettle: true,
          isAlreadySettled: false,
          statDate: statDate ?? '2026-10-24',
          currentBusinessDay: '2026-10-25',
          nextCloseBusinessDay: '2026-10-24',
          pendingDayCount: 2,
          hasPreviousUnclosedDay: true,
          precheckToken: 'test-token',
        );
  }

  @override
  Future<CashierZReportHistoryPage> loadZReports({
    int? shopId,
    String? dateFrom,
    String? dateTo,
    Object? cursor,
    int limit = 20,
  }) async {
    return zReportsPage ??
        const CashierZReportHistoryPage(
          currentBusinessDay: '2026-10-25',
          nextCloseBusinessDay: '2026-10-24',
          pendingDayCount: 2,
          items: [
            CashierZReportHistoryItem(
              id: null,
              businessDay: '2026-10-25',
              closeState: 'PENDING',
              canClose: false,
              isNextCloseBusinessDay: false,
            ),
            CashierZReportHistoryItem(
              id: null,
              businessDay: '2026-10-24',
              closeState: 'PENDING',
              canClose: true,
              isNextCloseBusinessDay: true,
            ),
            CashierZReportHistoryItem(
              id: 101,
              snapshotNo: 'Z20261023-01',
              businessDay: '2026-10-23',
              closeState: 'CLOSED',
              canClose: false,
              orderCount: 15,
              netSales: 320.0,
            ),
          ],
        );
  }

  @override
  Future<CommercialZReport> loadZReport({String? statDate, int? shopId}) async {
    return CommercialZReport(
      reportType: 'Z_REPORT',
      isClosed: true,
      shopId: shopId ?? 1,
      shopName: '深圳宝安店',
      businessDay: statDate ?? '2026-10-23',
      totalSales: 320.0,
      discountAmount: 0.0,
      refundAmount: 0.0,
      netSales: 320.0,
      orderCount: 15,
      totalCashVariance: 0.0,
      totalAdjustment: 0.0,
      adjustedNetSales: 320.0,
      printableText: 'Z-REPORT',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WI-067 DailyPrecheckResult sequence parsing', () {
    test('parses snake_case sequence fields from backend', () {
      final json = <String, Object?>{
        'can_settle': true,
        'is_already_settled': false,
        'stat_date': '2026-10-24',
        'current_business_day': '2026-10-25',
        'next_close_business_day': '2026-10-24',
        'pending_day_count': 2,
        'has_previous_unclosed_day': true,
        'precheck_token': 'token-wi067',
      };

      final result = DailyPrecheckResult.fromJson(json);

      expect(result.canSettle, isTrue);
      expect(result.isAlreadySettled, isFalse);
      expect(result.statDate, '2026-10-24');
      expect(result.currentBusinessDay, '2026-10-25');
      expect(result.nextCloseBusinessDay, '2026-10-24');
      expect(result.pendingDayCount, 2);
      expect(result.hasPreviousUnclosedDay, isTrue);
      expect(result.precheckToken, 'token-wi067');
    });

    test('falls back to next_close_business_day when stat_date is missing', () {
      final json = <String, Object?>{
        'can_settle': true,
        'next_close_business_day': '2026-10-24',
        'pending_day_count': 1,
        'has_previous_unclosed_day': false,
      };

      final result = DailyPrecheckResult.fromJson(json);
      expect(result.statDate, '2026-10-24');
      expect(result.hasPreviousUnclosedDay, isFalse);
      expect(result.pendingDayCount, 1);
    });
  });

  group('WI-068 CashierZReportHistory models continuous calendar parsing', () {
    test('parses items with nullable id, close_state, and can_close', () {
      final json = <String, Object?>{
        'current_business_day': '2026-10-25',
        'next_close_business_day': '2026-10-24',
        'pending_day_count': 2,
        'has_more': false,
        'next_cursor': '20261023',
        'items': [
          {
            'business_day': '2026-10-25',
            'close_state': 'PENDING',
            'can_close': false,
            'is_next_close_business_day': false,
            'id': null,
          },
          {
            'business_day': '2026-10-24',
            'close_state': 'PENDING',
            'can_close': true,
            'is_next_close_business_day': true,
            'id': null,
          },
          {
            'business_day': '2026-10-23',
            'close_state': 'CLOSED',
            'can_close': false,
            'id': 101,
            'snapshot_no': 'Z20261023-001',
            'net_sales_fen': 45000,
            'order_count': 20,
          },
          {
            'business_day': '2026-10-22',
            'close_state': 'REOPENED',
            'can_close': false,
            'id': 100,
            'snapshot_no': 'Z20261022-001',
            'net_sales_fen': 30000,
            'order_count': 10,
          },
        ],
      };

      final page = CashierZReportHistoryPage.fromJson(json);

      expect(page.currentBusinessDay, '2026-10-25');
      expect(page.nextCloseBusinessDay, '2026-10-24');
      expect(page.pendingDayCount, 2);
      expect(page.nextCursor, '20261023');
      expect(page.items.length, 4);

      // Item 0: PENDING, not canClose
      expect(page.items[0].id, isNull);
      expect(page.items[0].businessDay, '2026-10-25');
      expect(page.items[0].closeState, 'PENDING');
      expect(page.items[0].canClose, isFalse);
      expect(page.items[0].isNextCloseBusinessDay, isFalse);

      // Item 1: PENDING, canClose (earliest unclosed day)
      expect(page.items[1].id, isNull);
      expect(page.items[1].businessDay, '2026-10-24');
      expect(page.items[1].closeState, 'PENDING');
      expect(page.items[1].canClose, isTrue);
      expect(page.items[1].isNextCloseBusinessDay, isTrue);

      // Item 2: CLOSED
      expect(page.items[2].id, 101);
      expect(page.items[2].businessDay, '2026-10-23');
      expect(page.items[2].closeState, 'CLOSED');
      expect(page.items[2].canClose, isFalse);
      expect(page.items[2].netSales, 450.0);
      expect(page.items[2].orderCount, 20);

      // Item 3: REOPENED
      expect(page.items[3].id, 100);
      expect(page.items[3].closeState, 'REOPENED');
    });
  });

  group('WI-068 CashierZReportHistoryListPage Widget UI', () {
    testWidgets('renders backlog banner, status badges, and [去日结] button', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repository = _FakeDailySequenceRepository();
      String? openedDailyCloseDate;

      await tester.pumpWidget(
        MaterialApp(
          theme: CashierAppTheme.light(),
          home: Scaffold(
            body: CashierZReportHistoryListPage(
              repository: repository,
              shopId: 1,
              onOpenReport: (_) {},
              onOpenDailyClose: (date) => openedDailyCloseDate = date,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Backlog banner
      expect(find.textContaining('当前共有 2 个营业日待日结'), findsOneWidget);

      // Status badges
      expect(find.text('最早待结日'), findsOneWidget);
      expect(find.text('待日结'), findsNWidgets(2));
      expect(find.text('已结 (快照锁定)'), findsOneWidget);

      // Button [去日结] for 2026-10-24
      expect(find.text('去日结'), findsOneWidget);
      // Non-closable label for 2026-10-25
      expect(find.text('需先结更早营业日'), findsOneWidget);
      // Button [查看报表] for 2026-10-23
      expect(find.text('查看报表'), findsOneWidget);

      // Tap [去日结]
      await tester.tap(find.text('去日结'));
      await tester.pumpAndSettle();
      expect(openedDailyCloseDate, '2026-10-24');
    });

    testWidgets('taps [查看报表] to open historic commercial Z report', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repository = _FakeDailySequenceRepository();
      String? openedReportDate;

      await tester.pumpWidget(
        MaterialApp(
          theme: CashierAppTheme.light(),
          home: Scaffold(
            body: CashierZReportHistoryListPage(
              repository: repository,
              shopId: 1,
              onOpenReport: (date) => openedReportDate = date,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('查看报表'));
      await tester.pumpAndSettle();
      expect(openedReportDate, '2026-10-23');
    });
  });

  group('WI-067 CashierDailyClosePage sequence backlog banner', () {
    testWidgets('renders sequence backlog alert container when pendingDayCount > 1', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final repository = _FakeDailySequenceRepository(
        precheckResult: const DailyPrecheckResult(
          canSettle: true,
          isAlreadySettled: false,
          statDate: '2026-10-24',
          currentBusinessDay: '2026-10-25',
          nextCloseBusinessDay: '2026-10-24',
          pendingDayCount: 2,
          hasPreviousUnclosedDay: true,
          precheckToken: 'valid-token',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: CashierAppTheme.light(),
          home: Scaffold(
            body: CashierDailyClosePage(
              repository: repository,
              summary: const CashierDailySummary(
                statDate: '2026-10-24',
                totalAmount: 1200,
                discountAmount: 100,
                refundAmount: 0,
                settled: false,
              ),
              onSettle: ({targetBusinessDay, precheck, context}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Page Title shows target business day
      expect(find.text('营业日 2026-10-24'), findsOneWidget);

      // Sequence Backlog banner
      expect(find.textContaining('历史积压 2 天未关账'), findsOneWidget);
      expect(find.textContaining('INV-CLOSE-SEQ-001'), findsOneWidget);
    });

    testWidgets('CashierDailyClosePage taps settle button passing historical targetBusinessDay', (tester) async {
      final repository = _FakeDailySequenceRepository(
        precheckResult: const DailyPrecheckResult(
          statDate: '2026-10-24',
          canSettle: true,
          isAlreadySettled: false,
          blockers: [],
          warnings: [],
          watermarks: {},
          preview: {'net_sales_fen': 120000},
          hasPreviousUnclosedDay: false,
          precheckToken: 'valid-token',
        ),
      );

      String? settledTargetDay;
      DailyPrecheckResult? passedPrecheck;

      await tester.pumpWidget(
        MaterialApp(
          theme: CashierAppTheme.light(),
          home: Scaffold(
            body: CashierDailyClosePage(
              repository: repository,
              targetBusinessDay: '2026-10-24',
              summary: const CashierDailySummary(
                statDate: '2026-10-25',
                totalAmount: 1200,
                discountAmount: 100,
                refundAmount: 0,
                settled: false,
              ),
              onSettle: ({targetBusinessDay, precheck, context}) async {
                settledTargetDay = targetBusinessDay;
                passedPrecheck = precheck;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final settleButton = find.text('运行预检并日结');
      expect(settleButton, findsOneWidget);

      await tester.tap(settleButton);
      await tester.pumpAndSettle();

      expect(settledTargetDay, equals('2026-10-24'));
      expect(passedPrecheck?.precheckToken, equals('valid-token'));
    });
  });
}
