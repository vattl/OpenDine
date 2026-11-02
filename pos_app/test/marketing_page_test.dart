import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/cashier_settings_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_marketing_page.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/presentation/cashier_settings_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

class _FakeSettingsRepository implements CashierSettingsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('marketing settings page (M-G)', () {
    Widget build({
      required FakeHttpTransport transport,
      required String sectionId,
      Set<String> permissions = const {},
    }) {
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token',
        shopId: 8,
      );
      return MaterialApp(
        home: Scaffold(
          body: CashierSettingsMarketingPage(
            repository: _FakeSettingsRepository(),
            client: client,
            section: SettingsSectionSpec(
              sectionId,
              'section',
              Icons.campaign_outlined,
            ),
            permissions: permissions,
          ),
        ),
      );
    }

    testWidgets('redemptions sends filters and shows real restored history', (
      tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /admin/marketing/first-order/redemptions': jsonEncode({
          'page': 1,
          'pageSize': 20,
          'total': 1,
          'items': [
            {
              'orderNo': 'ORDER-17',
              'campaignId': 9,
              'customerId': 'c1',
              'amount': 12,
              'status': 'RESTORED',
              'restoredReason': 'full_refund',
            },
          ],
        }),
      });
      await tester.pumpWidget(
        build(transport: transport, sectionId: 'redemptions'),
      );
      await tester.pumpAndSettle();
      expect(find.text('ORDER-17'), findsOneWidget);
      expect(find.text('资格已恢复'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextFormField, '活动编号'), '9');
      await tester.enterText(
        find.widgetWithText(TextFormField, '订单号'),
        'ORDER-17',
      );
      await tester.tap(find.text('查询'));
      await tester.pumpAndSettle();
      expect(transport.requests.last.uri.queryParameters['campaignId'], '9');
      expect(
        transport.requests.last.uri.queryParameters['orderNo'],
        'ORDER-17',
      );
      expect(
        transport.requests.where((request) => request.method != 'GET'),
        isEmpty,
      );
    });

    testWidgets('campaigns section lists activities with detail button',
        (tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /admin/marketing/first-order/campaigns': jsonEncode({
          'items': [
            {
              'id': 3,
              'name': '新客满减',
              'campaignType': 'DISCOUNT',
              'status': 'ACTIVE',
              'stats': {'redemptions': 8, 'restorations': 1},
            },
          ],
        }),
        'GET /admin/marketing/first-order/campaigns/3': jsonEncode({
          'id': 3,
          'name': '新客满减',
          'campaignType': 'DISCOUNT',
          'status': 'ACTIVE',
          'thresholdAmount': 50,
          'discountValue': 10,
          'version': 1,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'campaigns'),
      );
      await tester.pumpAndSettle();

      expect(find.text('首单活动'), findsOneWidget);
      expect(find.text('新客满减'), findsOneWidget);
      // 「启用」同时出现在筛选 chip 与状态徽标，用 atLeastN。
      expect(find.text('启用'), findsAtLeastNWidgets(1));

      await tester.ensureVisible(
        find.byKey(const Key('marketing-campaign-detail-3')),
      );
      await tester.tap(
        find.byKey(const Key('marketing-campaign-detail-3')));
      await tester.pumpAndSettle();
      expect(find.text('活动详情：新客满减'), findsOneWidget);
      expect(find.textContaining('门槛金额'), findsOneWidget);
    });

    testWidgets('eligibility section evaluates customer', (tester) async {
      final transport = FakeHttpTransport({
        'POST /admin/marketing/first-order/eligibility/evaluate': jsonEncode({
          'eligible': true,
          'reason': '符合全部规则',
          'conflicts': [],
          'campaign': {'name': '新客满减'},
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'eligibility'),
      );
      await tester.pumpAndSettle();

      expect(find.text('首单资格评估'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField).first,
        'oX_abc123');
      await tester.tap(
        find.byKey(const Key('marketing-eligibility-evaluate')));
      await tester.pumpAndSettle();

      expect(find.text('符合首单资格'), findsOneWidget);
    });

    testWidgets('invite-reward section loads and shows save button',
        (tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /admin/config/invite-first-order-balance-reward':
            jsonEncode({'enabled': true, 'rewardPercent': 5,
        }),
        'PUT /admin/config/invite-first-order-balance-reward':
            jsonEncode({'enabled': true, 'rewardPercent': 5,
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'invite-reward'),
      );
      await tester.pumpAndSettle();

      expect(find.text('邀请首单返利'), findsOneWidget);
      expect(
        find.byKey(const Key('marketing-invite-reward-save')),
        findsOneWidget,
      );
    });

    testWidgets('ninefold section renders dining type chips', (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/payment/ninefold': jsonEncode({
          'enabled': true,
          'payRate': 0.9,
          'minBaseYuan': 100,
          'timeStart': '00:30',
          'timeEnd': '03:00',
          'zoneId': 'Asia/Shanghai',
          'eligibleDiningTypes': ['堂食'],
        }),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'ninefold',
          permissions: const {'payment:config:write'},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('夜间九折'), findsOneWidget);
      expect(
        find.byKey(const Key('marketing-ninefold-type-堂食')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('marketing-ninefold-save')),
        findsOneWidget);
    });
    testWidgets('campaigns section opens create form and shows row actions',
        (tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /admin/marketing/first-order/campaigns': jsonEncode({
          'items': [
            {
              'id': 3,
              'name': '新客满减',
              'campaignType': 'DISCOUNT',
              'status': 'ACTIVE',
              'stats': {'redemptions': 8, 'restorations': 1},
            },
          ],
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'campaigns'),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('marketing-campaign-create')), findsOneWidget,
      );
      expect(
        find.byKey(const Key('marketing-campaign-edit-3')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('marketing-campaign-pause-3')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('marketing-campaign-create')));
      await tester.pumpAndSettle();
      expect(find.text('新增首单活动'), findsOneWidget);
      expect(
        find.byKey(const Key('marketing-campaign-form-name')),
        findsOneWidget,
      );
    });

    testWidgets('banners section lists rows and hides create without permission',
        (tester) async {
      final transport = FakeHttpTransport({
        'GET /admin/order/banners': jsonEncode({
          'code': 0,
          'banners': [
            {'id': 3, 'image': 'https://img.test/a.png', 'url': null, 'status': 1, 'type': 'home',
              },
            {'id': 4, 'image': 'https://img.test/b.png', 'url': 'https://x.test', 'status': 0, 'type': 'bottom',
              },
          ],
        }),
      });

      await tester.pumpWidget(
        build(transport: transport, sectionId: 'banners'),
      );
      await tester.pumpAndSettle();

      expect(find.text('轮播图'), findsWidgets);
      expect(find.text('https://img.test/a.png'), findsOneWidget);
      expect(find.text('首页'), findsWidgets);
      expect(find.text('底部'), findsOneWidget);
      // 无 banner:manage 权限时新增/删除按钮禁用。
      final create = tester.widget<TextButton>(
        find.byKey(const Key('marketing-banner-create')),
      );
      expect(create.onPressed, isNull);
      final delete = tester.widget<TextButton>(
        find.byKey(const Key('marketing-banner-delete-3')),
      );
      expect(delete.onPressed, isNull);
    },
    );

    testWidgets('banners section creates then deletes with permission',
        (tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /admin/order/banners': jsonEncode({
          'code': 0,
          'banners': [
            {'id': 3, 'image': 'https://img.test/a.png', 'url': null, 'status': 1, 'type': 'home',
            },
          ],
        }),
        'POST /admin/order/addbanners': jsonEncode({
          'code': 0,
          'bannerId': 9}),
        'DELETE /admin/order/delete_banners/3': jsonEncode({'code': 0}),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'banners',
          permissions: const {'banner:manage'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('marketing-banner-create')));
      await tester.pumpAndSettle();
      expect(find.text('新增轮播图'), findsWidgets);

      await tester.enterText(
        find.byType(TextField).first,
        'https://img.test/new.png',
      );
      await tester.tap(find.byKey(const Key('marketing-banner-submit')));
      await tester.pumpAndSettle();

      final post = transport.requests.firstWhere(
        (request) =>
            request.method == 'POST' &&
            request.uri.path == '/admin/order/addbanners',
      );
      final body = jsonDecode(post.body!) as Map;
      expect(body['image'], 'https://img.test/new.png');
      expect(body['status'], 1);
      expect(body['type'], 'home');

      // 删除行触发确认并走 DELETE 端点。
      await tester.ensureVisible(
        find.byKey(const Key('marketing-banner-delete-3')),
      );
      await tester.tap(find.byKey(const Key('marketing-banner-delete-3')));
      await tester.pumpAndSettle();
      expect(find.text('删除轮播图'), findsOneWidget);
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      final deleted = transport.requests.any(
        (request) =>
            request.method == 'DELETE' &&
            request.uri.path == '/admin/order/delete_banners/3',
      );
      expect(deleted, isTrue);
    });

    testWidgets('banners section toggles enable/disable with permission',
        (tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /admin/order/banners': jsonEncode({
          'code': 0,
          'banners': [
            {'id': 3, 'image': 'https://img.test/a.png', 'url': null, 'status': 1, 'type': 'home',
            },
          ],
        }),
        'PUT /admin/order/update_banners/3':
            jsonEncode({'code': 0, 'msg': '更新成功',
        }),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'banners',
          permissions: const {'banner:manage'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('marketing-banner-toggle-3')),
      );
      await tester.tap(find.byKey(const Key('marketing-banner-toggle-3')));
      await tester.pumpAndSettle();
      expect(find.text('禁用轮播图'), findsOneWidget);
      await tester.tap(find.text('禁用').last);
      await tester.pumpAndSettle();

      final put = transport.requests.any(
        (request) =>
            request.method == 'PUT' &&
            request.uri.path == '/admin/order/update_banners/3',
      );
      expect(put, isTrue);
    });

    testWidgets('banners section edit button opens drawer and updates',
        (tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /admin/order/banners': jsonEncode({
          'code': 0,
          'banners': [
            {'id': 3, 'image': 'https://img.test/a.png', 'url': null, 'status': 1, 'type': 'home',
            },
          ],
        }),
        'PUT /admin/order/update_banners/3':
            jsonEncode({'code': 0, 'msg': '更新成功',
        }),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'banners',
          permissions: const {'banner:manage'},
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(
        find.byKey(const Key('marketing-banner-edit-3')),
      );
      await tester.tap(find.byKey(const Key('marketing-banner-edit-3')));
      await tester.pumpAndSettle();
      expect(find.text('编辑轮播图'), findsOneWidget);
      // 图片 URL 同时出现在表格行与抽屉回填，用 atLeastN。
      expect(find.text('https://img.test/a.png'), findsAtLeastNWidgets(1));

      await tester.tap(find.byKey(const Key('marketing-banner-submit')));
      await tester.pumpAndSettle();

      final put = transport.requests.any(
        (request) =>
            request.method == 'PUT' &&
            request.uri.path == '/admin/order/update_banners/3',
      );
      expect(put, isTrue);
    });

    testWidgets('banners section popup tab lists rows and opens edit form',
        (tester,
    ) async {
      final transport = FakeHttpTransport({
        'GET /activity/getAllPopup': jsonEncode({
          'code': 0,
          'popup': [
            {
              'id': 5,
              'name': '周年庆',
              'popup_image': '/image/avatar/a.png',
              'target_user': 'all',
              'start_time': '2026-10-01 00:00:00',
              'end_time': '2026-10-31 23:59:59',
              'is_enabled': 1,
              'max_show_count': 3,
              'sorting': 1,
              'type': 'page_banner',
              'apply_shop_ids': '[1,5]',
            },
          ],
        }),
        'POST /activity/getCarouselDetail': jsonEncode({
          'code': 0,
          'popup': {
            'id': 5,
            'name': '周年庆',
            'popup_image': '/image/avatar/a.png',
            'target_user': 'all',
            'start_time': '2026-10-01 00:00:00',
            'end_time': '2026-10-31 23:59:59',
            'is_enabled': 1,
            'max_show_count': 3,
            'sorting': 1,
            'type': 'page_banner',
            'apply_shop_ids': '[1,5]',
          },
        }),
        'POST /activity/updatePopup': jsonEncode({'code': 0, 'msg': '更新成功'}),
      });

      await tester.pumpWidget(
        build(
          transport: transport,
          sectionId: 'banners',
          permissions: const {'banner:manage'},
        ),
      );
      await tester.pumpAndSettle();

      // 切到弹窗广告 Tab。
      await tester.tap(find.text('弹窗广告'));
      await tester.pumpAndSettle();
      expect(find.text('周年庆'), findsOneWidget);
      expect(find.textContaining('2026-10-01'), findsOneWidget);
      // 有效期列含「每日上限 · 门店」（对齐原型列布局）。
      expect(find.textContaining('每日上限'), findsOneWidget);

      // 编辑弹窗回填表单并全量提交。
      await tester.ensureVisible(
        find.byKey(const Key('marketing-popup-edit-5')),
      );
      await tester.tap(find.byKey(const Key('marketing-popup-edit-5')));
      await tester.pumpAndSettle();
      expect(find.text('编辑弹窗广告'), findsOneWidget);
      await tester.tap(find.byKey(const Key('marketing-popup-submit')));
      await tester.pumpAndSettle();

      final update = transport.requests.firstWhere(
        (request) => request.uri.path == '/activity/updatePopup',
      );
      final body = jsonDecode(update.body!) as Map;
      expect(body['id'], 5);
      expect(body['name'], '周年庆');
    });
  });
}
