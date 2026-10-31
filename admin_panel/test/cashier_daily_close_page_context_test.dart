import 'package:admin_panel_flutter/src/features/cashier_shift/data/cashier_shift_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/presentation/cashier_shift_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDailyCloseRepo implements CashierShiftRepository {
  DailyPrecheckResult result;
  String? lastLoadedStatDate;

  _FakeDailyCloseRepo(this.result);

  @override
  Future<DailyPrecheckResult> loadDailyContext({
    String? statDate,
    int? shopId,
    int? minutes,
  }) async {
    lastLoadedStatDate = statDate;
    return result;
  }

  @override
  Future<DailyPrecheckResult> precheckDaily({
    String? statDate,
    int? shopId,
    int? minutes,
  }) => loadDailyContext(statDate: statDate, shopId: shopId, minutes: minutes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('CashierDailyClosePage renders live preview from loadDailyContext', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = _FakeDailyCloseRepo(
      const DailyPrecheckResult(
        canSettle: false,
        isAlreadySettled: false,
        statDate: '2026-10-24',
        blockers: const [
          DailyPrecheckBlocker(
            code: 'OPEN_ORDERS',
            message: '存在 2 笔未完成订单',
            count: 2,
          ),
        ],
        summary: const {
          'gross_sales_fen': 125000,
          'discount_amount_fen': 5000,
          'refund_amount_fen': 2000,
          'net_sales_fen': 118000,
          'order_count': 35,
          'cash_variance_fen': 0,
        },
        channelDetails: const [
          CashierPayChannelRevenue(
            code: 'wechat_native',
            label: '微信支付',
            amount: 880.0,
            transactionCount: 25,
          ),
          CashierPayChannelRevenue(
            code: 'alipay',
            label: '支付宝',
            amount: 300.0,
            transactionCount: 10,
          ),
        ],
      ),
    );

    const dummySummary = CashierDailySummary(
      statDate: '2026-10-24',
      totalAmount: 0,
      discountAmount: 0,
      refundAmount: 0,
      settled: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDailyClosePage(
          repository: repo,
          summary: dummySummary,
          targetBusinessDay: '2026-10-24',
          onSettle: ({context, precheck, targetBusinessDay}) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(repo.lastLoadedStatDate, '2026-10-24');
    expect(find.text('营业日 2026-10-24'), findsOneWidget);
    expect(find.text('当前不能日结'), findsOneWidget);
    expect(find.text('预检未通过'), findsOneWidget);

    // 财务指标
    expect(find.text('¥ 1250.00'), findsOneWidget);
    expect(find.text('− ¥ 50.00'), findsOneWidget);
    expect(find.text('− ¥ 20.00'), findsOneWidget);
    expect(find.text('¥ 1180.00'), findsOneWidget);
    expect(find.text('35 笔'), findsOneWidget);

    // 渠道列表
    expect(find.text('微信支付'), findsOneWidget);
    expect(find.text('¥ 880.00'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);
    expect(find.text('¥ 300.00'), findsOneWidget);
  });

  testWidgets('CashierDailyClosePage renders settled state from loadDailyContext', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final repo = _FakeDailyCloseRepo(
      const DailyPrecheckResult(
        canSettle: false,
        isAlreadySettled: true,
        statDate: '2026-10-23',
        blockers: const [],
        summary: const {
          'gross_sales_fen': 320000,
          'discount_amount_fen': 10000,
          'refund_amount_fen': 0,
          'net_sales_fen': 310000,
          'order_count': 80,
          'cash_variance_fen': 0,
        },
        channelDetails: const [
          CashierPayChannelRevenue(
            code: 'wechat_native',
            label: '微信支付',
            amount: 3100.0,
            transactionCount: 80,
          ),
        ],
      ),
    );

    const dummySummary = CashierDailySummary(
      statDate: '2026-10-23',
      totalAmount: 0,
      discountAmount: 0,
      refundAmount: 0,
      settled: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDailyClosePage(
          repository: repo,
          summary: dummySummary,
          targetBusinessDay: '2026-10-23',
          onSettle: ({context, precheck, targetBusinessDay}) async {},
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('该营业日已完成日结'), findsOneWidget);
    expect(find.text('已日结归档'), findsOneWidget);
    expect(find.text('该日已日结'), findsOneWidget);
    expect(find.text('¥ 3200.00'), findsOneWidget);
    expect(find.text('¥ 3100.00'), findsNWidgets(2));
    expect(find.text('80 笔'), findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);
  });
}
