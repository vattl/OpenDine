import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/api_providers.dart';
import 'package:admin_panel_flutter/src/features/mobile/presentation/boss_reports_page.dart';

class _FakeAdminApiClient extends Fake implements AdminApiClient {
  @override
  Future<Object?> get(
    AdminEndpoint endpoint, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    return {
      'code': 0,
      'msg': 'success',
      'report': {
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
      },
    };
  }
}

void main() {
  testWidgets('BossReportsPage renders all commercial daily report sections', (tester) async {
    final client = _FakeAdminApiClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          home: BossReportsPage(),
        ),
      ),
    );

    // Initial loading
    expect(find.text('营业报表'), findsOneWidget);
    await tester.pumpAndSettle();

    // Verify metadata banner
    expect(find.text('总店 / 旗舰店'), findsOneWidget);
    expect(find.text('已关账 (Z-Report)'), findsOneWidget);
    expect(find.text('关账人：店长张华'), findsOneWidget);

    // Verify 8 KPI metrics
    expect(find.text('实收营业额 (净入账)'), findsOneWidget);
    expect(find.text('账面原价销售额'), findsOneWidget);
    expect(find.text('折扣减免总额'), findsOneWidget);
    expect(find.text('退款总额'), findsOneWidget);

    // Verify Cards
    expect(find.text('💳 支付渠道实收明细'), findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);

    expect(find.text('🪙 收银钱箱与现金盘点'), findsOneWidget);
    expect(find.text('开箱备用金'), findsOneWidget);

    expect(find.text('🍽️ 就餐方式与订单类型'), findsOneWidget);
    expect(find.text('堂食就餐'), findsOneWidget);

    expect(find.text('👑 会员储值与运营'), findsOneWidget);
    expect(find.text('今日会员充值总额'), findsOneWidget);

    expect(find.text('🛡️ 异常与风控审计'), findsOneWidget);
    expect(find.text('反结账/重开次数'), findsOneWidget);

    expect(find.text('🔥 热销菜品 TOP 10'), findsOneWidget);
    expect(find.text('招牌秘制烤羊肉串'), findsOneWidget);

    // Verify printable preview action
    expect(find.text('🖨️ 小票预览'), findsOneWidget);
    await tester.tap(find.text('🖨️ 小票预览'));
    await tester.pumpAndSettle();
    expect(find.text('🖨️ 热敏小票打印预览'), findsOneWidget);
    expect(find.text('=== Z REPORT ==='), findsOneWidget);
  });
}
