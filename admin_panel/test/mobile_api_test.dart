import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/announcement_repository.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/dashboard_repository.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/idempotency.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

String _json(Object? body) => jsonEncode(body);

void main() {
  group('MobileDashboardRepository', () {
    test('parses dashboard summary from businessDay payload', () async {
      final transport = FakeHttpTransport({
        'GET /admin/report/dashboard': _json({
          'code': 0,
          'data': {
            'businessDay': {
              'startTime': 1787000000000,
              'endTime': 1787040000000,
              'todayRevenue': 1234.5,
              'todayOrderCount': 22,
              'todayPaidOrderCount': 20,
              'totalRefundAmount': 36.0,
              'totalDiscountAmount': 88.8,
              'todayUnpaidAmount': 120.0,
              'todayMemberRechargeAmount': 2000.0,
              'todayMemberRechargePrincipal': 1800.0,
              'todayMemberRechargeGift': 200.0,
              'todayMemberRechargeSuccessCount': 6,
              'revenueByPayChannel': [
                {'channelCode': 'wechat', 'channelLabel': '微信支付', 'amount': 1000.0},
                {'channelCode': 'cash', 'channelLabel': '现金', 'amount': 234.5},
              ],
            },
            'weeklyRepurchase': {
              'buyers': 120,
              'repurchasedBuyers': 45,
              'repurchaseRate': 0.375,
            },
            'monthlyRepurchase': {
              'buyers': 980,
              'repurchasedBuyers': 360,
              'repurchaseRate': 0.3673,
            },
            'newCustomerRepurchase': {
              'windowDays': 30,
              'newBuyers': 300,
              'repurchasedNewBuyers': 70,
              'repurchaseRate': 0.2333,
            },
            'register': {
              'sevenDaysRegisterCount': 210,
              'thisMonthRegisterCount': 640,
              'lastMonthRegisterCount': 780,
            },
          },
        }),
      });
      final repo = MobileDashboardRepository(
        AdminApiClient(
          baseUrl: 'https://example.com',
          transport: transport,
          token: 't',
          shopId: 1,
        ),
      );
      final summary = await repo.loadDashboardSummary();
      expect(summary.revenue, 1234.5);
      expect(summary.orderCount, 22);
      expect(summary.paidOrderCount, 20);
      expect(summary.avgOrderAmount, closeTo(61.7, 0.1));
      expect(summary.refundAmount, 36.0);
      expect(summary.discountAmount, 88.8);
      expect(summary.unpaidAmount, 120.0);
      expect(summary.memberRechargeAmount, 2000.0);
      expect(summary.memberRechargePrincipal, 1800.0);
      expect(summary.memberRechargeGift, 200.0);
      expect(summary.memberRechargeCount, 6);
      expect(summary.bizStart, DateTime.fromMillisecondsSinceEpoch(1787000000000));
      expect(summary.settlementWindowLabel, contains('最近已完成结算日'));
      expect(summary.payChannels.length, 2);
      expect(summary.payChannels.first.label, '微信支付');
      expect(summary.weeklyRepurchase.repurchaseRate, closeTo(0.375, 0.001));
      expect(summary.weeklyRepurchase.buyers, 120);
      expect(summary.monthlyRepurchase.repurchasedBuyers, 360);
      expect(summary.newCustomerRepurchase.newBuyers, 300);
      expect(summary.newCustomerRepurchase.windowDays, 30);
      expect(summary.register.sevenDays, 210);
      expect(summary.register.thisMonth, 640);
    });
  });

  group('RealAnnouncementRepository', () {
    test('list maps announcement payload', () async {
      final transport = FakeHttpTransport({
        'GET /admin/announcement/list': _json({
          'code': 0,
          'data': {
            'records': [
              {'id': 1, 'title': 'A', 'content': 'a', 'createdAt': '2026-07-01'},
            ],
          },
        }),
      });
      final repo = RealAnnouncementRepository(
        AdminApiClient(
          baseUrl: 'https://example.com',
          transport: transport,
          token: 't',
          shopId: 1,
        ),
      );
      final list = await repo.list();
      expect(list, hasLength(1));
      expect(list.first.title, 'A');
    });
  });

  group('IdempotencyKey', () {
    test('generates unique prefixed keys', () {
      final a = IdempotencyKey.next('quickOrder');
      final b = IdempotencyKey.next('quickOrder');
      expect(a, isNot(b));
      expect(a, startsWith('app-'));
    });
  });
}
