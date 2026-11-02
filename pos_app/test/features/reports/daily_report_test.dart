import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/reports/domain/daily_report.dart';

void main() {
  group('DailyReport JSON deserialization', () {
    test('parses full commercial 8-dimension payload correctly', () {
      final json = {
        'totalAmount': 91.0,
        'orderCount': 2,
        'grossRevenue': 95.0,
        'netRevenue': 91.0,
        'totalDiscount': 10.0,
        'totalRefund': 3.0,
        'metadata': {
          'shopId': 7,
          'shopName': '总店 / 旗舰店',
          'businessDay': '2026-10-02',
          'windowStart': '2026-10-02 04:00:00',
          'windowEnd': '2026-10-03 04:00:00',
          'generatedAt': '2026-10-15 18:30:00',
          'isSettled': true,
          'reportType': 'Z_REPORT',
          'operatorName': '店长张华',
          'snapshotNo': 'DSN2026100200078832',
        },
        'summary': {
          'grossRevenue': 95.0,
          'totalDiscount': 10.0,
          'netRevenue': 91.0,
          'totalRefund': 3.0,
          'orderCount': 2,
          'dinerCount': 4,
          'avgOrderAmount': 45.5,
          'avgDinerAmount': 22.75,
          'tableTurnoverRate': 1.2,
        },
        'paymentChannels': [
          {
            'channelCode': 'wechat_native',
            'channelLabel': '微信支付',
            'amount': 50.0,
            'orderCount': 1,
            'refundCount': 0,
            'percentage': 54.9,
          },
          {
            'channelCode': 'cash',
            'channelLabel': '现金支付',
            'amount': 41.0,
            'orderCount': 1,
            'refundCount': 0,
            'percentage': 45.1,
          },
        ],
        'cashDrawer': {
          'openingFloat': 200.0,
          'cashIn': 41.0,
          'cashRefund': 0.0,
          'cashOut': 0.0,
          'theoreticalCash': 241.0,
          'countedCash': 241.0,
          'variance': 0.0,
          'sessionCount': 1,
        },
        'orderTypes': [
          {
            'type': 'dine_in',
            'label': '堂食就餐',
            'orderCount': 2,
            'amount': 91.0,
            'percentage': 100.0,
          },
        ],
        'member': {
          'rechargeTotal': 500.0,
          'rechargePrincipal': 400.0,
          'rechargeGift': 100.0,
          'rechargeCount': 2,
          'memberConsumption': 0.0,
          'newMembers': 3,
        },
        'exceptions': {
          'uncheckoutCount': 0,
          'uncheckoutAmount': 0.0,
          'refundCount': 1,
          'refundAmount': 3.0,
          'discountAmount': 10.0,
          'freeDishesCount': 0,
          'freeDishesAmount': 0.0,
        },
        'topDishes': [
          {
            'rank': 1,
            'dishName': '招牌秘制烤羊肉串',
            'quantity': 12,
            'amount': 48.0,
            'percentage': 52.0,
          },
        ],
        'printableText': '=== Z REPORT ===',
      };

      final report = DailyReport.fromJson(json);

      expect(report.totalAmount, 91.0);
      expect(report.orderCount, 2);
      expect(report.grossRevenue, 95.0);
      expect(report.totalDiscount, 10.0);
      expect(report.totalRefund, 3.0);

      // Metadata
      expect(report.metadata.shopId, 7);
      expect(report.metadata.shopName, '总店 / 旗舰店');
      expect(report.metadata.isSettled, isTrue);
      expect(report.metadata.reportType, 'Z_REPORT');

      // Summary
      expect(report.summary.dinerCount, 4);
      expect(report.summary.avgOrderAmount, 45.5);
      expect(report.summary.avgDinerAmount, 22.75);
      expect(report.summary.tableTurnoverRate, 1.2);

      // Channels
      expect(report.paymentChannels.length, 2);
      expect(report.paymentChannels[0].channelCode, 'wechat_native');
      expect(report.paymentChannels[0].amount, 50.0);

      // Drawer
      expect(report.cashDrawer.openingFloat, 200.0);
      expect(report.cashDrawer.countedCash, 241.0);
      expect(report.cashDrawer.variance, 0.0);

      // Order Types
      expect(report.orderTypes.length, 1);
      expect(report.orderTypes[0].label, '堂食就餐');

      // Member
      expect(report.member.rechargeTotal, 500.0);
      expect(report.member.newMembers, 3);

      // Exceptions
      expect(report.exceptions.refundCount, 1);
      expect(report.exceptions.refundAmount, 3.0);

      // Top Dishes
      expect(report.topDishes.length, 1);
      expect(report.topDishes[0].dishName, '招牌秘制烤羊肉串');
      expect(report.topDishes[0].quantity, 12);

      expect(report.printableText, '=== Z REPORT ===');
    });

    test('handles fallback/sparse payload gracefully', () {
      final json = {
        'totalAmount': 50.0,
        'orderCount': 1,
      };

      final report = DailyReport.fromJson(json);

      expect(report.totalAmount, 50.0);
      expect(report.orderCount, 1);
      expect(report.summary.netRevenue, 50.0);
      expect(report.summary.orderCount, 1);
      expect(report.paymentChannels, isEmpty);
      expect(report.cashDrawer.variance, 0.0);
      expect(report.metadata.isSettled, isFalse);
    });
  });
}
