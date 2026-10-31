import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/real_marketing_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/marketing_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('marketing M-G repository', () {
    RealMarketingRepository build(FakeHttpTransport transport) {
      return RealMarketingRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );
    }

    test('loadInviteReward parses enabled and rewardPercent', () async {
      final transport = FakeHttpTransport({
        'GET /admin/config/invite-first-order-balance-reward':
            jsonEncode({'enabled': true, 'rewardPercent': 5}),
      });
      final repository = build(transport);

      final value = await repository.loadInviteReward();

      expect(value.enabled, isTrue);
      expect(value.rewardPercent, 5);
    });

    test('saveInviteReward posts enabled/rewardPercent', () async {
      final transport = FakeHttpTransport({
        'PUT /admin/config/invite-first-order-balance-reward':
            jsonEncode({'enabled': false, 'rewardPercent': 0}),
      });
      final repository = build(transport);

      await repository.saveInviteReward(enabled: false, rewardPercent: 0);

      expect(jsonDecode(transport.requests.single.body!), {
        'enabled': false,
        'rewardPercent': 0,
      });
    });

    test('loadInvitePoster parses nested qr block', () async {
      final transport = FakeHttpTransport({
        'GET /admin/config/invite-poster': jsonEncode({
          'backgroundPath': '/images/poster.png',
          'qr': {'x': 120, 'y': 800, 'size': 220},
        }),
      });
      final repository = build(transport);

      final poster = await repository.loadInvitePoster();

      expect(poster.backgroundPath, '/images/poster.png');
      expect(poster.qrX, 120);
      expect(poster.qrY, 800);
      expect(poster.qrSize, 220);
    });

    test('saveInvitePoster posts backgroundPath and qr block', () async {
      final transport = FakeHttpTransport({
        'PUT /admin/config/invite-poster':
            jsonEncode({'backgroundPath': '/a.png', 'qr': {'x': 1, 'y': 2, 'size': 3}}),
      });
      final repository = build(transport);

      await repository.saveInvitePoster(
        backgroundPath: '/a.png',
        qrX: 1,
        qrY: 2,
        qrSize: 3,
      );

      expect(jsonDecode(transport.requests.single.body!), {
        'backgroundPath': '/a.png',
        'qr': {'x': 1, 'y': 2, 'size': 3},
      });
    });

    test('loadNinefold and saveNinefold use payment ninefold routes', () async {
      final transport = FakeHttpTransport({
        'GET /admin/payment/ninefold': jsonEncode({
          'enabled': true,
          'payRate': 0.9,
          'minBaseYuan': 100,
          'timeStart': '00:30',
          'timeEnd': '03:00',
          'zoneId': 'Asia/Shanghai',
          'eligibleDiningTypes': ['堂食', '打包'],
          'hasOwnConfig': true,
          'inheritsGlobal': false,
        }),
        'PUT /admin/payment/ninefold': jsonEncode({
          'enabled': true,
          'payRate': 0.9,
          'minBaseYuan': 100,
          'timeStart': '00:30',
          'timeEnd': '03:00',
          'zoneId': 'Asia/Shanghai',
          'eligibleDiningTypes': ['堂食'],
        }),
      });
      final repository = build(transport);

      final value = await repository.loadNinefold();
      expect(value.enabled, isTrue);
      expect(value.payRate, 0.9);
      expect(value.eligibleDiningTypes, ['堂食', '打包']);
      expect(value.hasOwnConfig, isTrue);

      final saved = await repository.saveNinefold(value);
      expect(saved.eligibleDiningTypes, ['堂食']);
      expect(transport.requests.last.method, 'PUT');
      expect(transport.requests.last.uri.path, '/admin/payment/ninefold');
      expect(
        jsonDecode(transport.requests.last.body!),
        contains('payRate'),
      );
    });

    test('loadCampaigns parses items with stats', () async {
      final transport = FakeHttpTransport({
        'GET /admin/marketing/first-order/campaigns': jsonEncode({
          'items': [
            {
              'id': 3,
              'name': '新客满减',
              'campaignType': 'DISCOUNT',
              'status': 'ACTIVE',
              'thresholdAmount': 50,
              'discountValue': 10,
              'startTime': '2026-08-01 00:00:00',
              'endTime': '2026-12-31 23:59:59',
              'stats': {'redemptions': 8, 'restorations': 1},
            },
          ],
        }),
      });
      final repository = build(transport);

      final campaigns = await repository.loadCampaigns(status: 'ACTIVE');

      expect(campaigns.single.name, '新客满减');
      expect(campaigns.single.redemptions, 8);
      expect(campaigns.single.restorations, 1);
      expect(transport.requests.single.uri.queryParameters['status'], 'ACTIVE');
    });

    test('loadCampaignDetail parses detail with version', () async {
      final transport = FakeHttpTransport({
        'GET /admin/marketing/first-order/campaigns/3': jsonEncode({
          'id': 3,
          'name': '新客满减',
          'campaignType': 'GIFT',
          'status': 'DRAFT',
          'version': 2,
        }),
      });
      final repository = build(transport);

      final detail = await repository.loadCampaignDetail(3);

      expect(detail.id, 3);
      expect(detail.campaignType, 'GIFT');
      expect(detail.version, 2);
      expect(transport.requests.single.uri.path,
          '/admin/marketing/first-order/campaigns/3');
    });

    test('evaluateEligibility posts customerId/orderAmount and parses result',
        () async {
      final transport = FakeHttpTransport({
        'POST /admin/marketing/first-order/eligibility/evaluate': jsonEncode({
          'eligible': true,
          'reason': '符合全部规则',
          'conflicts': [],
          'campaign': {'name': '新客满减'},
        }),
      });
      final repository = build(transport);

      final result = await repository.evaluateEligibility(
        customerId: 'oX_abc123',
        orderAmount: 88.5,
      );

      expect(result.eligible, isTrue);
      expect(result.campaignName, '新客满减');
      expect(jsonDecode(transport.requests.single.body!), {
        'customerId': 'oX_abc123',
        'orderAmount': 88.5,
      });
    });

    test('evaluateEligibility rejects empty customerId', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.evaluateEligibility(customerId: '  '),
        throwsArgumentError,
      );
    });

    test('createCampaign posts toSaveJson and parses created campaign',
        () async {
      final transport = FakeHttpTransport({
        'POST /admin/marketing/first-order/campaigns': jsonEncode({
          'id': 9,
          'name': '新客首单立减',
          'campaignType': 'DISCOUNT',
          'status': 'DRAFT',
          'version': 1,
        }),
      });
      final repository = build(transport);

      final created = await repository.createCampaign(
        MarketingCampaign(
          id: 0,
          name: '新客首单立减',
          campaignType: 'DISCOUNT',
          status: 'DRAFT',
          thresholdAmount: 30,
          discountValue: 8,
          startTime: '2026-10-01 00:00:00',
          endTime: '2026-12-31 23:59:59',
        ),
      );

      expect(created.id, 9);
      expect(created.version, 1);
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['name'], '新客首单立减');
      expect(body['campaignType'], 'DISCOUNT');
      expect(body['startTime'], '2026-10-01 00:00:00');
      expect(body.containsKey('version'), isFalse);
    });

    test('createCampaign rejects empty name', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.createCampaign(
          MarketingCampaign(
            id: 0,
            name: '',
            campaignType: 'DISCOUNT',
            status: 'DRAFT',
          ),
        ),
        throwsArgumentError,
      );
    });

    test('updateCampaign posts body with version lock', () async {
      final transport = FakeHttpTransport({
        'PUT /admin/marketing/first-order/campaigns/9': jsonEncode({
          'id': 9,
          'name': '新客首单立减',
          'campaignType': 'DISCOUNT',
          'status': 'ACTIVE',
          'version': 2,
        }),
      });
      final repository = build(transport);

      final updated = await repository.updateCampaign(
        MarketingCampaign(
          id: 9,
          name: '新客首单立减',
          campaignType: 'DISCOUNT',
          status: 'ACTIVE',
          startTime: '2026-10-01 00:00:00',
          endTime: '2026-12-31 23:59:59',
          version: 1,
        ),
      );

      expect(updated.version, 2);
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['version'], 1);
      expect(body['status'], 'ACTIVE');
      expect(
        transport.requests.single.uri.path,
        '/admin/marketing/first-order/campaigns/9',
      );
    });

    test('updateCampaign rejects missing id or version', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.updateCampaign(
          MarketingCampaign(
            id: 0,
            name: 'x',
            campaignType: 'DISCOUNT',
            status: 'DRAFT',
            version: 1,
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.updateCampaign(
          MarketingCampaign(
            id: 9,
            name: 'x',
            campaignType: 'DISCOUNT',
            status: 'DRAFT',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('marketing banners repository', () {
    RealMarketingRepository build(FakeHttpTransport transport) {
      return RealMarketingRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );
    }

    test('listBanners parses the banners array', () async {
      final transport = FakeHttpTransport({
        'GET /admin/order/banners': jsonEncode({
          'code': 0,
          'banners': [
            {'id': 3, 'image': 'https://img.test/a.png', 'url': null, 'status': 1, 'type': 'home'},
            {'id': 4, 'image': 'https://img.test/b.png', 'url': 'https://x.test', 'status': 0, 'type': 'bottom'},
          ],
        }),
      });
      final repository = build(transport);

      final banners = await repository.listBanners();

      expect(banners, hasLength(2));
      expect(banners.first.id, 3);
      expect(banners.first.type, 'home');
      expect(banners.first.status, 1);
      expect(banners.last.url, 'https://x.test');
      expect(banners.last.status, 0);
    });

    test('addBanner posts image/url/status/type and reads bannerId', () async {
      final transport = FakeHttpTransport({
        'POST /admin/order/addbanners': jsonEncode({'code': 0, 'bannerId': 11}),
      });
      final repository = build(transport);

      final saved = await repository.addBanner(
        const MarketingBanner(
          id: 0,
          image: 'https://img.test/c.png',
          url: 'https://y.test',
          status: 1,
          type: 'home',
        ),
      );

      expect(transport.requests.single.method, 'POST');
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['image'], 'https://img.test/c.png');
      expect(body['url'], 'https://y.test');
      expect(body['status'], 1);
      expect(body['type'], 'home');
      expect(saved.id, 11);
    });

    test('addBanner rejects empty image', () async {
      final transport = FakeHttpTransport({
        'POST /admin/order/addbanners': jsonEncode({'code': 0, 'bannerId': 1}),
      });
      final repository = build(transport);

      await expectLater(
        repository.addBanner(
          const MarketingBanner(id: 0, image: '  ', status: 1, type: 'home'),
        ),
        throwsArgumentError,
      );
    });

    test('deleteBanner deletes by path id', () async {
      final transport = FakeHttpTransport({
        'DELETE /admin/order/delete_banners/7': jsonEncode({'code': 0}),
      });
      final repository = build(transport);

      await repository.deleteBanner(id: 7);

      expect(transport.requests.single.method, 'DELETE');
      expect(transport.requests.single.uri.path, '/admin/order/delete_banners/7');
    });

    test('updateBanner puts status for quick enable/disable', () async {
      final transport = FakeHttpTransport({
        'PUT /admin/order/update_banners/3': jsonEncode({'code': 0, 'msg': '更新成功'}),
      });
      final repository = build(transport);

      await repository.updateBanner(
        const MarketingBanner(
          id: 3,
          image: 'https://img.test/a.png',
          url: null,
          status: 0,
          type: 'home',
        ),
      );

      expect(transport.requests.single.method, 'PUT');
      expect(
        transport.requests.single.uri.path,
        '/admin/order/update_banners/3',
      );
      final body = jsonDecode(transport.requests.single.body!) as Map;
      // id 走 path 参数，保存体不携带（与 addBanner 一致）。
      expect(body.containsKey('id'), isFalse);
      expect(body['image'], 'https://img.test/a.png');
      expect(body['status'], 0);
      expect(body['type'], 'home');
    });

    test('uploadBannerImage posts multipart file and reads msg path', () async {
      final transport = FakeHttpTransport({
        'POST /admin/order/uploadBannerFile':
            jsonEncode({'code': 0, 'msg': '/image/avatar/uuid-1.png'}),
      });
      final repository = build(transport);

      final path = await repository.uploadBannerImage(
        bytes: [1, 2, 3, 4],
        filename: 'banner.png',
      );

      expect(transport.requests.single.method, 'POST');
      expect(
        transport.requests.single.uri.path,
        '/admin/order/uploadBannerFile',
      );
      final multipart = utf8.decode(transport.requests.single.bodyBytes!);
      expect(multipart, contains('banner.png'));
      expect(path, '/image/avatar/uuid-1.png');
    });

    test('uploadBannerImage rejects empty bytes', () async {
      final transport = FakeHttpTransport({
        'POST /admin/order/uploadBannerFile': jsonEncode({'code': 0, 'msg': 'x'}),
      });
      final repository = build(transport);

      await expectLater(
        repository.uploadBannerImage(bytes: [], filename: 'b.png'),
        throwsArgumentError,
      );
    });
  });

  group('marketing popup repository', () {
    RealMarketingRepository build(FakeHttpTransport transport) {
      return RealMarketingRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );
    }

    test('listPopups parses the popup array', () async {
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
      });
      final repository = build(transport);

      final popups = await repository.listPopups();

      expect(popups, hasLength(1));
      expect(popups.first.name, '周年庆');
      expect(popups.first.popupImage, '/image/avatar/a.png');
      expect(popups.first.isEnabled, 1);
      expect(popups.first.applyShopIds, '[1,5]');
      expect(popups.first.type, 'page_banner');
    });

    test('loadPopupDetail posts id and parses popup', () async {
      final transport = FakeHttpTransport({
        'POST /activity/getCarouselDetail': jsonEncode({
          'code': 0,
          'popup': {
            'id': 5,
            'name': '周年庆',
            'popup_image': '/image/avatar/a.png',
            'is_enabled': 0,
          },
        }),
      });
      final repository = build(transport);

      final popup = await repository.loadPopupDetail(id: 5);

      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['id'], 5);
      expect(popup.id, 5);
      expect(popup.isEnabled, 0);
    });

    test('addPopup posts full popup body', () async {
      final transport = FakeHttpTransport({
        'POST /activity/addPopup': jsonEncode({'code': 0, 'msg': '添加成功'}),
      });
      final repository = build(transport);

      await repository.addPopup(
        const MarketingPopup(
          name: '新店开业',
          popupImage: '/image/avatar/b.png',
          targetUser: 'new',
          startTime: '2026-10-07 08:00:00',
          endTime: '2026-10-08 08:00:00',
          isEnabled: 1,
          maxShowCount: 0,
          sorting: 2,
          type: 'home_top',
          applyShopIds: null,
        ),
      );

      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['name'], '新店开业');
      expect(body['popup_image'], '/image/avatar/b.png');
      expect(body['start_time'], '2026-10-07 08:00:00');
      expect(body['type'], 'home_top');
      expect(body.containsKey('apply_shop_ids'), isFalse);
    });

    test('addPopup rejects missing name/image/time', () async {
      final transport = FakeHttpTransport({
        'POST /activity/addPopup': jsonEncode({'code': 0}),
      });
      final repository = build(transport);

      await expectLater(
        repository.addPopup(const MarketingPopup(name: '', popupImage: 'x')),
        throwsArgumentError,
      );
      await expectLater(
        repository.addPopup(
          const MarketingPopup(name: 'x', popupImage: ''),
        ),
        throwsArgumentError,
      );
      await expectLater(
        repository.addPopup(
          const MarketingPopup(name: 'x', popupImage: 'y'),
        ),
        throwsArgumentError,
      );
    });

    test('updatePopup posts full body with id', () async {
      final transport = FakeHttpTransport({
        'POST /activity/updatePopup': jsonEncode({'code': 0, 'msg': '更新成功'}),
      });
      final repository = build(transport);

      await repository.updatePopup(
        const MarketingPopup(
          id: 5,
          name: '周年庆2',
          popupImage: '/image/avatar/a.png',
          isEnabled: 0,
        ),
      );

      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['id'], 5);
      expect(body['name'], '周年庆2');
      expect(body['is_enabled'], 0);
    });

    test('deletePopup posts id', () async {
      final transport = FakeHttpTransport({
        'POST /activity/deletePopup': jsonEncode({'code': 0}),
      });
      final repository = build(transport);

      await repository.deletePopup(id: 5);

      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['id'], 5);
    });
  });
}
