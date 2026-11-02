import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/data/real_coupon_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/coupon_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('coupon M-J repository', () {
    RealCouponRepository build(FakeHttpTransport transport) {
      return RealCouponRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );
    }

    test('loadCoupons parses list with snake_case fields', () async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/list': jsonEncode({
          'list': [
            {
              'id': 5,
              'coupon_name': '满50减10',
              'coupon_type': 'full_reduction',
              'status': 1,
              'discount_value': 10,
              'min_amount': 50,
              'stock': 100,
              'granted_count': 12,
              'start_time': '2026-08-01 00:00:00',
              'end_time': '2026-12-31 23:59:59',
            },
          ],
          'total': 1,
        }),
      });
      final repository = build(transport);

      final coupons = await repository.loadCoupons(status: 1);

      expect(coupons.single.name, '满50减10');
      expect(coupons.single.status, 1);
      expect(coupons.single.discountValue, 10);
      expect(coupons.single.stock, 100);
      expect(coupons.single.grantedCount, 12);
      expect(
        transport.requests.single.uri.queryParameters['status'],
        '1',
      );
    });

    test('loadRedeemCodes parses rows with used state', () async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/redeem-code/list': jsonEncode({
          'list': [
            {
              'id': 9,
              'coupon_id': 5,
              'redeem_code': 'LAOFEI-ABC',
              'status': 1,
              'used_openid': 'oX_1',
              'used_time': '2026-09-01 12:00:00',
              'create_time': '2026-08-01 00:00:00',
            },
          ],
          'total': 1,
        }),
      });
      final repository = build(transport);

      final codes = await repository.loadRedeemCodes(couponId: 5, status: 1);

      expect(codes.single.redeemCode, 'LAOFEI-ABC');
      expect(codes.single.status, 1);
      expect(codes.single.usedOpenid, 'oX_1');
    });

    test('deleteRedeemCodes posts ids and returns deleted count', () async {
      final transport = FakeHttpTransport({
        'POST /admin/coupon/redeem-code/delete':
            jsonEncode({'deleted': 2}),
      });
      final repository = build(transport);

      final deleted = await repository.deleteRedeemCodes([1, 9]);

      expect(deleted, 2);
      expect(jsonDecode(transport.requests.single.body!), {'ids': [1, 9]});
    });

    test('deleteRedeemCodes rejects empty ids', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.deleteRedeemCodes(const []),
        throwsArgumentError,
      );
    });

    test('loadUserCoupons parses rows with order and status', () async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/user-coupon/list': jsonEncode({
          'list': [
            {
              'id': 33,
              'user_openid': 'oX_2',
              'coupon_id': 5,
              'coupon_name': '满50减10',
              'status': 1,
              'order_no': 'NO20260901001',
              'get_time': '2026-08-02 10:00:00',
              'use_time': '2026-09-01 12:00:00',
            },
          ],
          'total': 1,
        }),
      });
      final repository = build(transport);

      final rows = await repository.loadUserCoupons(couponId: 5, status: 1);

      expect(rows.single.couponName, '满50减10');
      expect(rows.single.orderNo, 'NO20260901001');
      expect(rows.single.status, 1);
    });

    test('grantByExcel posts multipart with couponId field and file',
        () async {
      final transport = FakeHttpTransport({
        'POST /admin/coupon/user-coupon/batch-grant-excel': jsonEncode({
          'couponId': 5,
          'fileName': 'openids.xlsx',
          'readCount': 10,
          'duplicateCount': 2,
          'targetOpenidCount': 8,
          'grantedCount': 8,
        }),
      });
      final repository = build(transport);
      final body = utf8.encode('openid\nabc123');

      final result = await repository.grantByExcel(
        couponId: 5,
        bytes: body,
        fileName: 'openids.xlsx',
      );

      expect(result.grantedCount, 8);
      expect(result.targetOpenidCount, 8);
      final requestBody = utf8.decode(
        transport.requests.single.bodyBytes!,
        allowMalformed: true,
      );
      expect(requestBody, contains('name="couponId"'));
      expect(requestBody, contains('name="file"'));
      expect(requestBody, contains('filename="openids.xlsx"'));
    });

    test('grantByExcel rejects empty bytes', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.grantByExcel(
          couponId: 1,
          bytes: const [],
          fileName: 'x.xlsx',
        ),
        throwsArgumentError,
      );
    });

    test('voidUserCoupon and unbindUserCoupon post userCouponId', () async {
      final transport = FakeHttpTransport({
        'POST /admin/coupon/user-coupon/void': jsonEncode({'ok': true}),
        'POST /admin/coupon/user-coupon/unbind': jsonEncode({'ok': true}),
      });
      final repository = build(transport);

      await repository.voidUserCoupon(33);
      await repository.unbindUserCoupon(33);

      expect(transport.requests[0].method, 'POST');
      expect(
        transport.requests[0].uri.path,
        '/admin/coupon/user-coupon/void',
      );
      expect(jsonDecode(transport.requests[0].body!), {'userCouponId': 33});
      expect(
        transport.requests[1].uri.path,
        '/admin/coupon/user-coupon/unbind',
      );
      expect(jsonDecode(transport.requests[1].body!), {'userCouponId': 33});
    });

    test('verifyRedeemCodeQrcode returns status for PNG endpoint', () async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/redeem-code/qrcode': 'binary-png-placeholder',
      });
      final repository = build(transport);

      final verified = await repository.verifyRedeemCodeQrcode('LAOFEI-ABC');

      expect(verified, isTrue);
      expect(
        transport.requests.single.uri.queryParameters['redeem_code'],
        'LAOFEI-ABC',
      );
    });

    test('addCoupon posts toSaveJson and returns id', () async {
      final transport = FakeHttpTransport({
        'POST /admin/coupon/add': jsonEncode({'id': 7}),
      });
      final repository = build(transport);

      final id = await repository.addCoupon(
        CouponTemplate(
          id: 0,
          name: '新客券',
          couponType: 'full_reduction',
          discountValue: 5,
          minAmount: 30,
          stock: 100,
        ),
      );

      expect(id, 7);
      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['coupon_name'], '新客券');
      expect(body['coupon_type'], 'full_reduction');
      expect(body['apply_dining_type'], 'all');
      expect(body.containsKey('id'), isFalse);
    });

    test('updateCoupon posts body with id', () async {
      final transport = FakeHttpTransport({
        'POST /admin/coupon/update': jsonEncode({'ok': true}),
      });
      final repository = build(transport);

      await repository.updateCoupon(
        CouponTemplate(
          id: 7,
          name: '新客券',
          couponType: 'discount',
          discountValue: 0.9,
          stock: -1,
          status: 1,
        ),
      );

      final body = jsonDecode(transport.requests.single.body!) as Map;
      expect(body['id'], 7);
      expect(body['status'], 1);
      expect(body['stock'], -1);
    });

    test('deleteCoupon calls GET with id', () async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/delete': jsonEncode({'ok': true}),
      });
      final repository = build(transport);

      await repository.deleteCoupon(7);

      expect(
        transport.requests.single.uri.queryParameters['id'],
        '7',
      );
    });

    test('loadCouponDetail parses nested coupon object', () async {
      final transport = FakeHttpTransport({
        'GET /admin/coupon/get': jsonEncode({
          'coupon': {
            'id': 7,
            'coupon_name': '新客券',
            'coupon_type': 'direct_reduction',
            'status': 1,
            'validity_time': 24,
          },
        }),
      });
      final repository = build(transport);

      final detail = await repository.loadCouponDetail(7);

      expect(detail.name, '新客券');
      expect(detail.validityTime, 24);
      expect(
        transport.requests.single.uri.queryParameters['id'],
        '7',
      );
    });

    test('createRedeemCodes posts couponId/count and parses codes', () async {
      final transport = FakeHttpTransport({
        'POST /admin/coupon/redeem-code/create': jsonEncode({
          'couponId': 7,
          'count': 2,
          'codes': [
            {'id': 1, 'redeem_code': 'LAOFEI-A'},
            {'id': 2, 'redeem_code': 'LAOFEI-B'},
          ],
        }),
      });
      final repository = build(transport);

      final codes = await repository.createRedeemCodes(
        couponId: 7,
        count: 2,
      );

      expect(codes, hasLength(2));
      expect(codes.first.redeemCode, 'LAOFEI-A');
      expect(jsonDecode(transport.requests.single.body!), {
        'couponId': 7,
        'count': 2,
      });
    });

    test('createRedeemCodes rejects out-of-range count', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.createRedeemCodes(couponId: 7, count: 501),
        throwsArgumentError,
      );
    });

    test('grantCoupon posts openid or phone', () async {
      final transport = FakeHttpTransport({
        'POST /admin/coupon/user-coupon/grant': jsonEncode({'ok': true}),
      });
      final repository = build(transport);

      await repository.grantCoupon(couponId: 7, openid: 'oX_1');

      expect(jsonDecode(transport.requests.single.body!), {
        'couponId': 7,
        'openid': 'oX_1',
      });

      final phoneTransport = FakeHttpTransport({
        'POST /admin/coupon/user-coupon/grant': jsonEncode({'ok': true}),
      });
      final phoneRepository = build(phoneTransport);
      await phoneRepository.grantCoupon(couponId: 7, phone: '13800138000');
      expect(jsonDecode(phoneTransport.requests.single.body!), {
        'couponId': 7,
        'phone': '13800138000',
      });
    });

    test('grantCoupon rejects missing openid and phone', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.grantCoupon(couponId: 7),
        throwsArgumentError,
      );
    });
  });
}
