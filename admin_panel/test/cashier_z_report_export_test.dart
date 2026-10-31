import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/domain/cashier_shift.dart';
import 'package:admin_panel_flutter/src/features/cashier_shift/presentation/cashier_shift_workbench.dart';
import 'package:admin_panel_flutter/src/features/reports/domain/daily_report.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockDailyDetail = DailyReport.fromJson({
    'totalAmount': 9800.0,
    'orderCount': 45,
    'grossRevenue': 10580.0,
    'netRevenue': 9800.0,
    'totalDiscount': 780.0,
    'totalRefund': 180.0,
    'metadata': {
      'date': '2026-10-15',
      'shopName': '测试烤肉旗舰店',
      'settledAt': '2026-10-15 22:30:00',
    },
    'summary': {
      'dinerCount': 168,
      'avgOrderAmount': 217.78,
      'avgDinerAmount': 58.33,
      'tableTurnoverRate': 2.8,
    },
    'paymentChannels': [
      {'channelCode': 'WECHAT', 'channelLabel': '微信支付', 'amount': 5200.0, 'orderCount': 25, 'percentage': 53.1},
      {'channelCode': 'ALIPAY', 'channelLabel': '支付宝', 'amount': 2620.0, 'orderCount': 12, 'percentage': 26.7},
      {'channelCode': 'CASH', 'channelLabel': '现金支付', 'amount': 1980.0, 'orderCount': 8, 'percentage': 20.2},
    ],
    'cashDrawer': {
      'openingFloat': 500.0,
      'cashIn': 1980.0,
      'cashRefund': 0.0,
      'cashOut': 0.0,
      'theoreticalCash': 2480.0,
      'countedCash': 2480.0,
      'variance': 0.0,
      'sessionCount': 1,
    },
    'orderTypes': [
      {'type': 'DINE_IN', 'label': '堂食', 'orderCount': 38, 'amount': 8900.0, 'percentage': 90.8},
      {'type': 'TAKEOUT', 'label': '外带自提', 'orderCount': 7, 'amount': 900.0, 'percentage': 9.2},
    ],
    'member': {
      'rechargeTotal': 3200.0,
      'rechargePrincipal': 3000.0,
      'rechargeGift': 200.0,
      'rechargeCount': 8,
      'memberConsumption': 6500.0,
      'newMembers': 12,
    },
    'exceptions': {
      'uncheckoutCount': 0,
      'uncheckoutAmount': 0.0,
      'refundCount': 2,
      'refundAmount': 180.0,
      'discountAmount': 780.0,
      'freeDishesCount': 3,
      'freeDishesAmount': 60.0,
    },
    'topDishes': [
      {'rank': 1, 'dishName': '招牌牛五花', 'quantity': 68, 'amount': 2584.0, 'percentage': 26.4},
      {'rank': 2, 'dishName': '秘制调味牛排', 'quantity': 42, 'amount': 1932.0, 'percentage': 19.7},
      {'rank': 3, 'dishName': '冰爽生啤 500ml', 'quantity': 85, 'amount': 1020.0, 'percentage': 10.4},
    ],
  });

  final mockReport = CommercialZReport(
    reportType: 'DAILY_Z_REPORT',
    isClosed: true,
    shopId: 101,
    shopName: '测试烤肉旗舰店',
    businessDay: '2026-10-15',
    closedAt: DateTime(2026, 10, 15, 22, 30),
    operatorName: '店长-李强',
    totalSales: 10580.0,
    discountAmount: 780.0,
    refundAmount: 180.0,
    netSales: 9800.0,
    orderCount: 45,
    channels: const {'WECHAT': 5200.0, 'ALIPAY': 2620.0, 'CASH': 1980.0},
    channelDetails: const [
      CashierPayChannelRevenue(code: 'WECHAT', label: '微信支付', amount: 5200.0, transactionCount: 25),
      CashierPayChannelRevenue(code: 'ALIPAY', label: '支付宝', amount: 2620.0, transactionCount: 12),
      CashierPayChannelRevenue(code: 'CASH', label: '现金支付', amount: 1980.0, transactionCount: 8),
    ],
    drawerSummary: const {
      'opening_float': 500.0,
      'counted_cash': 2480.0,
      'theoretical_cash': 2480.0,
      'variance': 0.0,
    },
    totalCashVariance: 0.0,
    totalAdjustment: 0.0,
    adjustedNetSales: 9800.0,
    printableText: '=== 商业级营业日结 (Z-Report) ===\n营业日: 2026-10-15\n实收: 9800.00',
    dailyDetail: mockDailyDetail,
  );

  group('CommercialZReport and DailyDetail model integration', () {
    test('convenience getters fall back or retrieve correctly from dailyDetail', () {
      expect(mockReport.dinerCount, 168);
      expect(mockReport.avgOrderAmount, 217.78);
      expect(mockReport.avgDinerAmount, 58.33);
      expect(mockReport.tableTurnoverRate, 2.8);
      expect(mockReport.orderTypes.length, 2);
      expect(mockReport.member?.newMembers, 12);
      expect(mockReport.exceptions?.refundCount, 2);
      expect(mockReport.topDishes.length, 3);
      expect(mockReport.topDishes.first.dishName, '招牌牛五花');
    });

    test('copyWith updates fields while preserving dailyDetail', () {
      final updated = mockReport.copyWith(operatorName: '副店长-张伟');
      expect(updated.operatorName, '副店长-张伟');
      expect(updated.dailyDetail?.summary.dinerCount, 168);
      expect(updated.dinerCount, 168);
    });

    test('channel details successCount alias matches transactionCount', () {
      expect(mockReport.channelDetails.first.successCount, 25);
      expect(mockReport.channelDetails.first.transactionCount, 25);
    });
  });

  group('generateCommercialZReportCsv', () {
    test('generates UTF-8 BOM and contains all 8 major sections', () {
      final csv = generateCommercialZReportCsv(mockReport);

      // Verify UTF-8 BOM
      expect(csv.startsWith('\uFEFF'), isTrue);

      // Verify 8 sections
      expect(csv, contains('连锁餐饮收银日结对账单 (Z-Report 已关账)'));
      expect(csv, contains('【核心营收与营运指标】'));
      expect(csv, contains('【支付渠道实收明细】'));
      expect(csv, contains('【收银钱箱现金对账】'));
      expect(csv, contains('【就餐方式与订单类型分布】'));
      expect(csv, contains('【会员储值与运营简报】'));
      expect(csv, contains('【异常与风控审计】'));
      expect(csv, contains('【热销菜品销售排行 TOP 10】'));

      // Verify specific data items
      expect(csv, contains('2026-10-15'));
      expect(csv, contains('店长-李强'));
      expect(csv, contains('微信支付'));
      expect(csv, contains('招牌牛五花'));
      expect(csv, contains('堂食'));
      expect(csv, contains('账实相符'));
    });
  });

  group('CashierZReportPage Widget Test', () {
    testWidgets('renders all 8 dimensions and 4 action buttons', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierZReportPage(
              report: mockReport,
              onPrint: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify header titles
      expect(find.text('Z 报表'), findsOneWidget);
      expect(find.text('关账快照已锁定'), findsWidgets);

      // Verify action buttons
      expect(find.byKey(const Key('copy-z-report-button')), findsOneWidget);
      expect(find.byKey(const Key('preview-z-report-button')), findsOneWidget);
      expect(find.byKey(const Key('export-z-report-csv-button')), findsOneWidget);
      expect(find.byKey(const Key('print-z-report-button')), findsOneWidget);

      // Verify dimension card titles
      expect(find.text('核心营收与营运指标'), findsOneWidget);
      expect(find.text('支付渠道实收对账'), findsOneWidget);
      expect(find.text('收银钱箱现金盘点'), findsOneWidget);
      expect(find.text('🍽️ 就餐方式与订单类型'), findsOneWidget);
      expect(find.text('👑 会员储值与运营'), findsOneWidget);
      expect(find.text('🛡️ 异常与风控审计'), findsOneWidget);
      expect(find.text('🔥 菜品销售额排行 TOP 10'), findsOneWidget);

      // Verify Top dishes content
      expect(find.text('招牌牛五花'), findsOneWidget);
      expect(find.text('秘制调味牛排'), findsOneWidget);

      // Tap preview button to test receipt preview modal
      await tester.tap(find.byKey(const Key('preview-z-report-button')));
      await tester.pumpAndSettle();

      expect(find.text('58mm 热敏小票打印预览'), findsOneWidget);
      expect(find.text('复制文本'), findsOneWidget);
      expect(find.text('关闭'), findsOneWidget);

      // Close modal
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('58mm 热敏小票打印预览'), findsNothing);

      // Test clipboard copy button
      final log = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          log.add(call);
          return null;
        },
      );

      await tester.tap(find.byKey(const Key('copy-z-report-button')));
      await tester.pump();

      expect(log.any((call) => call.method == 'Clipboard.setData'), isTrue);
    });
  });
}
