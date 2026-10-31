import 'package:admin_panel_flutter/src/features/cashier_shift/data/cashier_shift_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/presentation/cashier_shift_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MockCashierShiftRepository implements CashierShiftRepository {
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
    return const DailyPrecheckResult(
      canSettle: false,
      isAlreadySettled: false,
      statDate: '2026-10-18',
      blockers: [
        DailyPrecheckBlocker(
          code: 'ORDER_LEDGER_MISMATCH',
          message: '存在 2 笔未平账交易流水',
          count: 2,
          reasonSummary: '结账流水与订单实收金额不一致，差异总计 ¥85.00，请排查补录或冲正。',
          ledgerMismatches: [
            LedgerMismatchItem(
              orderId: 901,
              orderNo: 'ORD-MISMATCH-001',
              reasonCode: 'AMOUNT_MISMATCH',
              reason: '挂账回款少记 20 元',
              orderAmountFen: 12000,
              ledgerAmountFen: 10000,
              differenceFen: -2000,
            ),
            LedgerMismatchItem(
              orderId: 902,
              orderNo: 'ORD-MISMATCH-002',
              reasonCode: 'MISSING_LEDGER',
              reason: '订单结账未生成对应流水',
              orderAmountFen: 6500,
              ledgerAmountFen: 0,
              differenceFen: -6500,
            ),
          ],
        ),
      ],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('CashierDailyClosePage renders ORDER_LEDGER_MISMATCH blocker diagnostic card', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final mockRepo = MockCashierShiftRepository();
    const summary = CashierDailySummary(
      statDate: '2026-10-18',
      totalAmount: 1000.0,
      discountAmount: 0.0,
      refundAmount: 0.0,
      settled: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CashierDailyClosePage(
            repository: mockRepo,
            summary: summary,
            onSettle: ({targetBusinessDay, precheck, context}) async {},
          ),
        ),
      ),
    );

    // Initial load
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify reason summary is displayed
    expect(find.textContaining('差异概要：结账流水与订单实收金额不一致'), findsOneWidget);

    // Verify mismatch items table contents
    expect(find.text('ORD-MISMATCH-001'), findsOneWidget);
    expect(find.textContaining('挂账回款少记 20 元'), findsOneWidget);
    expect(find.text('ORD-MISMATCH-002'), findsOneWidget);
    expect(find.textContaining('订单结账未生成对应流水'), findsOneWidget);
  });
}
