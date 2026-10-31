import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/mobile/data/api_providers.dart';
import 'package:admin_panel_flutter/src/features/mobile/presentation/daily_settle_page.dart';

class _FakeDailyAdminApiClient extends Fake implements AdminApiClient {
  final Map<String, Object?> contextResponse;
  final List<AdminEndpoint> calledEndpoints = [];
  final List<Map<String, Object?>> calledQueries = [];

  _FakeDailyAdminApiClient(this.contextResponse);

  @override
  Future<Object?> get(
    AdminEndpoint endpoint, {
    Map<String, Object?> query = const {},
    Map<String, String> headers = const {},
  }) async {
    calledEndpoints.add(endpoint);
    calledQueries.add(query);
    if (endpoint == dailyContextEndpoint) {
      return contextResponse;
    }
    return {'code': 0, 'data': {}};
  }
}

void main() {
  testWidgets('DailySettlePage loads context and renders unsettled state with blockers', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeClient = _FakeDailyAdminApiClient({
      'code': 0,
      'stat_date': '2026-10-24',
      'next_close_business_day': '2026-10-24',
      'pending_day_count': 1,
      'has_previous_unclosed_day': false,
      'is_already_settled': false,
      'can_settle': false,
      'blockers': [
        {'code': 'OPEN_ORDERS', 'message': '存在 2 笔未完成订单（草稿/待支付/制作中）'},
      ],
      'summary': {
        'net_sales': 1180.00,
        'gross_sales': 1250.00,
        'discount_amount': 50.00,
        'refund_amount': 20.00,
        'material_cost': 400.00,
        'order_count': 35,
      },
      'channel_details': [
        {
          'channel_code': 'wechat_native',
          'channel_label': '微信支付',
          'amount': 880.00,
          'order_count': 25,
        },
        {
          'channel_code': 'alipay',
          'channel_label': '支付宝',
          'amount': 300.00,
          'order_count': 10,
        },
      ],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(
          home: DailySettlePage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(fakeClient.calledEndpoints, contains(dailyContextEndpoint));
    expect(find.text('门店日结'), findsOneWidget);
    expect(find.textContaining('2026-10-24'), findsWidgets);
    expect(find.text('2026-10-24 待日结关账'), findsOneWidget);
    expect(find.text('日结前置阻断（须全部清零）'), findsOneWidget);
    expect(find.text('存在 2 笔未完成订单（草稿/待支付/制作中）'), findsOneWidget);
    expect(find.text('存在阻断无法日结'), findsOneWidget);
    expect(find.text('日结汇总'), findsOneWidget);
    expect(find.text('营业总额'), findsOneWidget);
    expect(find.text('35'), findsOneWidget);
    expect(find.text('支付渠道对账'), findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);
    expect(find.text('支付宝'), findsOneWidget);
  });

  testWidgets('DailySettlePage loads context and renders settled state', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final fakeClient = _FakeDailyAdminApiClient({
      'code': 0,
      'stat_date': '2026-10-23',
      'is_already_settled': true,
      'can_settle': false,
      'blockers': [],
      'summary': {
        'net_sales': 3100.00,
        'gross_sales': 3200.00,
        'discount_amount': 100.00,
        'refund_amount': 0.00,
        'order_count': 80,
      },
      'channel_details': [
        {
          'channel_code': 'wechat_native',
          'channel_label': '微信支付',
          'amount': 3100.00,
          'order_count': 80,
        },
      ],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(fakeClient),
        ],
        child: const MaterialApp(
          home: DailySettlePage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('2026-10-23 已完成日结'), findsOneWidget);
    expect(find.text('该营业日已日结'), findsOneWidget);
    expect(find.text('80'), findsOneWidget);
    expect(find.text('微信支付'), findsOneWidget);
    expect(find.text('日结前置阻断（须全部清零）'), findsNothing);
  });
}
