import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_payment/data/real_cashier_payment_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('payment M-F repository', () {
    RealCashierPaymentRepository build(FakeHttpTransport transport) {
      return RealCashierPaymentRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 8,
        ),
      );
    }

    test('loadNotifyUrls parses camel and snake response fields', () async {
      final transport = FakeHttpTransport({
        'GET /admin/payment/notify-urls': jsonEncode({
          'wechat_pay_notify': 'https://api.test/n/wx/pay',
          'wechatRefundNotify': 'https://api.test/n/wx/refund',
          'alipayPayNotify': 'https://api.test/n/alipay/pay',
        }),
      });
      final repository = build(transport);

      final urls = await repository.loadNotifyUrls();

      expect(urls.wechatPayNotify, 'https://api.test/n/wx/pay');
      expect(urls.wechatRefundNotify, 'https://api.test/n/wx/refund');
      expect(urls.alipayPayNotify, 'https://api.test/n/alipay/pay');
      expect(transport.requests.single.headers['X-Shop-Id'], '8');
    });

    test('uploadWechatPrivateKey sends multipart with pem bytes and merchant key',
        () async {
      const pem = '-----BEGIN PRIVATE KEY-----\nabc123\n-----END PRIVATE KEY-----';
      final transport = FakeHttpTransport({
        'POST /admin/payment/private-key/upload': jsonEncode({
          'privateKeyRef': 'payment-keys/wechat-default.pem',
        }),
      });
      final repository = build(transport);

      final result = await repository.uploadWechatPrivateKey(
        pemBytes: utf8.encode(pem),
        filename: 'wechat-default.pem',
        merchantKey: 'default',
      );

      expect(result.privateKeyRef, 'payment-keys/wechat-default.pem');
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/admin/payment/private-key/upload');
      expect(request.uri.queryParameters['merchantKey'], 'default');
      expect(request.headers['Content-Type'], contains('multipart/form-data'));
      final body = utf8.decode(request.bodyBytes!);
      expect(body, contains('name="file"'));
      expect(body, contains('wechat-default.pem'));
      expect(body, contains(pem));
    });

    test('uploadWechatPrivateKey rejects empty bytes', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.uploadWechatPrivateKey(
          pemBytes: const [],
          filename: 'x.pem',
        ),
        throwsArgumentError,
      );
    });

    test('uploadMerchantPrivateKey targets merchant-scoped path and parses form',
        () async {
      const pem = '-----BEGIN RSA PRIVATE KEY-----\nxyz\n-----END RSA PRIVATE KEY-----';
      final transport = FakeHttpTransport({
        'POST /admin/payment/merchants/31/private-key/upload': jsonEncode({
          'id': 31,
          'channel': 'wechat',
          'merchantKey': 'default',
          'privateKeyRef': 'payment-keys/wechat-31.pem',
        }),
      });
      final repository = build(transport);

      final form = await repository.uploadMerchantPrivateKey(
        merchantId: 31,
        pemBytes: utf8.encode(pem),
        filename: 'wechat-merchant-31.pem',
      );

      expect(form.id, 31);
      expect(form.privateKeyRef, 'payment-keys/wechat-31.pem');
      expect(transport.requests.single.uri.path,
          '/admin/payment/merchants/31/private-key/upload');
      expect(
        utf8.decode(transport.requests.single.bodyBytes!),
        contains('wechat-merchant-31.pem'),
      );
    });

    test('uploadWechatPlatformPublicKey sends multipart with cert bytes and merchant key',
        () async {
      const pem = '-----BEGIN PUBLIC KEY-----\npub123\n-----END PUBLIC KEY-----';
      final transport = FakeHttpTransport({
        'POST /admin/payment/platform-public-key/upload': jsonEncode({
          'platformPubKeyRef': 'payment-keys/shop-8/wechat-default-platform-public.pem',
          'materialType': 'PUBLIC_KEY',
        }),
      });
      final repository = build(transport);

      final result = await repository.uploadWechatPlatformPublicKey(
        pemBytes: utf8.encode(pem),
        filename: 'wechatpay_pub.pem',
        merchantKey: 'default',
      );

      expect(result.platformPubKeyRef,
          'payment-keys/shop-8/wechat-default-platform-public.pem');
      expect(result.materialType, 'PUBLIC_KEY');
      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/admin/payment/platform-public-key/upload');
      expect(request.uri.queryParameters['merchantKey'], 'default');
      expect(request.headers['Content-Type'], contains('multipart/form-data'));
      final body = utf8.decode(request.bodyBytes!);
      expect(body, contains('name="file"'));
      expect(body, contains('wechatpay_pub.pem'));
      expect(body, contains(pem));
    });

    test('uploadWechatPlatformPublicKey rejects empty bytes', () async {
      final transport = FakeHttpTransport({});
      final repository = build(transport);

      await expectLater(
        repository.uploadWechatPlatformPublicKey(
          pemBytes: const [],
          filename: 'cert.pem',
        ),
        throwsArgumentError,
      );
    });
  });
}
