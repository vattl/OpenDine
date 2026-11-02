import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/reports/domain/daily_report.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/presentation/cashier_shift_workbench.dart';

void main() {
  group('DailyReport & CommercialZReport Receivables Alignment (v1.2.306 / WI-029)', () {
    test('DailyReport.fromJson parses receivableSummary and totalCollections correctly', () {
      final json = <String, Object?>{
        'netRevenue': 12850.0,
        'grossRevenue': 14200.0,
        'totalDiscount': 1350.0,
        'totalRefund': 0.0,
        'orderCount': 68,
        'totalCollectionsFen': 1320000,
        'totalCollections': 13200.0,
        'receivableSummary': {
          'chargedFen': 150000,
          'collectedFen': 120000,
          'writeoffFen': 0,
          'reversedFen': 0,
          'outstandingFen': 1830000,
          'cutoffLedgerId': 1088,
        },
        'metadata': {
          'shopId': 1,
          'shopName': '总店',
          'businessDay': '2026-10-19',
          'isSettled': true,
        },
        'summary': {
          'grossRevenue': 14200.0,
          'totalDiscount': 1350.0,
          'netRevenue': 12850.0,
          'totalRefund': 0.0,
          'totalCollections': 13200.0,
          'orderCount': 68,
          'dinerCount': 182,
          'avgOrderAmount': 188.97,
          'avgDinerAmount': 70.60,
          'tableTurnoverRate': 3.2,
        },
        'paymentChannels': [
          {
            'channelCode': 'wechat',
            'channelLabel': '微信支付',
            'amount': 8500.0,
            'orderCount': 45,
            'refundCount': 0,
            'percentage': 66.1,
          },
          {
            'channelCode': 'alipay',
            'channelLabel': '支付宝',
            'amount': 2200.0,
            'orderCount': 15,
            'refundCount': 0,
            'percentage': 17.1,
          },
        ],
        'cashDrawer': {
          'openingFloat': 500.0,
          'cashIn': 650.0,
          'cashRefund': 0.0,
          'cashOut': 0.0,
          'theoreticalCash': 1150.0,
          'countedCash': 1150.0,
          'variance': 0.0,
          'sessionCount': 1,
        },
        'orderTypes': [],
        'member': {
          'rechargeTotal': 1000.0,
          'rechargePrincipal': 650.0,
          'rechargeGift': 350.0,
          'rechargeCount': 5,
          'memberConsumption': 800.0,
          'newMembers': 3,
        },
        'exceptions': {
          'uncheckoutCount': 0,
          'uncheckoutAmount': 0.0,
          'refundCount': 0,
          'refundAmount': 0.0,
          'discountAmount': 1350.0,
          'freeDishesCount': 0,
          'freeDishesAmount': 0.0,
        },
        'topDishes': [],
      };

      final report = DailyReport.fromJson(json);

      expect(report.netRevenue, 12850.0);
      expect(report.totalCollectionsFen, 1320000);
      expect(report.totalCollections, 13200.0);
      expect(report.summary.totalCollections, 13200.0);

      final rec = report.receivableSummary;
      expect(rec, isNotNull);
      expect(rec!.chargedFen, 150000);
      expect(rec.chargedAmount, 1500.0);
      expect(rec.collectedFen, 120000);
      expect(rec.collectedAmount, 1200.0);
      expect(rec.writeoffFen, 0);
      expect(rec.writeoffAmount, 0.0);
      expect(rec.reversedFen, 0);
      expect(rec.reversedAmount, 0.0);
      expect(rec.outstandingFen, 1830000);
      expect(rec.outstandingAmount, 18300.0);
      expect(rec.cutoffLedgerId, 1088);
    });

    test('CommercialZReport parses receivable_summary and outputs in CSV', () {
      final zReportJson = <String, Object?>{
        'report_type': 'Z_REPORT',
        'is_closed': true,
        'shop_id': 1,
        'shop_name': '总店',
        'business_day': '2026-10-19',
        'sales_summary': {
          'net_sales': 12850.0,
          'total_sales': 14200.0,
          'discount_amount': 1350.0,
          'refund_amount': 0.0,
          'order_count': 68,
        },
        'total_collections_fen': 1320000,
        'total_collections': 13200.0,
        'receivable_summary': {
          'charged_fen': 150000,
          'collected_fen': 120000,
          'writeoff_fen': 0,
          'reversed_fen': 0,
          'outstanding_fen': 1830000,
          'cutoff_ledger_id': 1088,
        },
        'watermarks': {
          'payment_ledger_id': 500,
          'order_id': 68,
          'receivable_ledger_id': 1088,
        },
        'channels': {
          'wechat': 8500.0,
          'alipay': 2200.0,
        },
      };

      final zReport = CommercialZReport.fromJson(zReportJson);

      expect(zReport.netSales, 12850.0);
      expect(zReport.actualCollections, 13200.0);
      expect(zReport.receivables, isNotNull);
      expect(zReport.receivables!.chargedAmount, 1500.0);
      expect(zReport.receivables!.collectedAmount, 1200.0);
      expect(zReport.receivables!.outstandingAmount, 18300.0);
      expect(zReport.receivables!.cutoffLedgerId, 1088);

      final csv = generateCommercialZReportCsv(zReport);
      expect(csv, contains('净销售额 (含挂账)'));
      expect(csv, contains('实际收款合计 (已入账)'));
      expect(csv, contains('13200.00'));
      expect(csv, contains('【挂账与应收对账】'));
      expect(csv, contains('当期新增挂账 (Charged)'));
      expect(csv, contains('1500.00'));
      expect(csv, contains('当期应收回款 (Collected)'));
      expect(csv, contains('1200.00'));
      expect(csv, contains('期末应收余额 (Outstanding)'));
      expect(csv, contains('18300.00'));
      expect(csv, contains('应收流水截止水位'));
      expect(csv, contains('1088'));
      expect(csv, contains('【支付渠道实收明细】'));
    });

    test('CommercialZReport handles absent receivableSummary gracefully', () {
      final legacyJson = <String, Object?>{
        'report_type': 'Z_REPORT',
        'is_closed': true,
        'shop_id': 1,
        'shop_name': '总店',
        'business_day': '2026-10-19',
        'sales_summary': {
          'net_sales': 5000.0,
          'total_sales': 5000.0,
          'discount_amount': 0.0,
          'refund_amount': 0.0,
          'order_count': 20,
        },
      };

      final report = CommercialZReport.fromJson(legacyJson);
      expect(report.netSales, 5000.0);
      expect(report.actualCollections, 5000.0); // Fallbacks to netSales
      expect(report.receivables, isNull);

      final csv = generateCommercialZReportCsv(report);
      expect(csv, contains('净销售额 (含挂账)'));
      expect(csv, contains('实际收款合计 (已入账)'));
      expect(csv, contains('5000.00'));
      expect(csv, isNot(contains('【挂账与应收对账】')));
    });

    testWidgets('CashierZReportPage renders net sales, actual collections and receivables section', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      final report = CommercialZReport.fromJson({
        'report_type': 'Z_REPORT',
        'is_closed': true,
        'shop_id': 1,
        'shop_name': '总店',
        'business_day': '2026-10-19',
        'sales_summary': {
          'net_sales': 12850.0,
          'total_sales': 14200.0,
          'discount_amount': 1350.0,
          'refund_amount': 0.0,
          'order_count': 68,
        },
        'total_collections_fen': 1320000,
        'total_collections': 13200.0,
        'receivable_summary': {
          'charged_fen': 150000,
          'collected_fen': 120000,
          'writeoff_fen': 0,
          'reversed_fen': 0,
          'outstanding_fen': 1830000,
          'cutoff_ledger_id': 1088,
        },
        'watermarks': {
          'payment_ledger_id': 500,
          'order_id': 68,
          'receivable_ledger_id': 1088,
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierZReportPage(
              report: report,
              onPrint: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('净销售额 (含挂账)'), findsOneWidget);
      expect(find.text('实际收款合计 (已入账)'), findsOneWidget);
      expect(find.text('挂账与应收对账专区'), findsOneWidget);
      expect(find.text('当期新增挂账 (Charged)'), findsOneWidget);
      expect(find.text('当期应收回款 (Collected)'), findsOneWidget);
      expect(find.text('期末应收余额 (Outstanding)'), findsOneWidget);
      expect(find.text('会计勾稽与对账指引'), findsOneWidget);
      expect(find.text('流水水位 #1088'), findsOneWidget);
      expect(find.text('应收流水'), findsOneWidget);
    });
  });
}
