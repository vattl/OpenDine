import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('POS payment channel contract', () {
    test('exposes the public order-scoped capability endpoint', () {
      expect(publicPaymentCapabilitiesEndpoint.method, 'GET');
      expect(
        publicPaymentCapabilitiesEndpoint.path,
        '/config/payment-capabilities',
      );
      expect(publicPaymentCapabilitiesEndpoint.permissionCode, 'public');
      expect(publicPaymentCapabilitiesEndpoint.attachShopHeader, isTrue);
    });

    test('normalizes unified codes and legacy aliases to stable kinds', () {
      const aliases = <String, PosPaymentChannelKind>{
        'cash': PosPaymentChannelKind.cash,
        '现金支付': PosPaymentChannelKind.cash,
        'clients.cashier.channels.cash': PosPaymentChannelKind.cash,
        'offline_wechat_qr': PosPaymentChannelKind.wechat,
        'wechat': PosPaymentChannelKind.wechat,
        '微信支付': PosPaymentChannelKind.wechat,
        'cashier_wechat_enabled': PosPaymentChannelKind.wechat,
        'cashierWechatEnabled': PosPaymentChannelKind.wechat,
        'clients.cashier.channels.wechat': PosPaymentChannelKind.wechat,
        'cashier.wechat': PosPaymentChannelKind.wechat,
        'offlineCollect.wechat': PosPaymentChannelKind.wechat,
        'offline_alipay_qr': PosPaymentChannelKind.alipay,
        'alipay': PosPaymentChannelKind.alipay,
        '支付宝支付': PosPaymentChannelKind.alipay,
        'cashierAlipayEnabled': PosPaymentChannelKind.alipay,
        'clients.cashier.channels.alipay': PosPaymentChannelKind.alipay,
        'offlineCollect.alipay': PosPaymentChannelKind.alipay,
        'online_balance': PosPaymentChannelKind.balance,
        'member_balance': PosPaymentChannelKind.balance,
        '余额支付': PosPaymentChannelKind.balance,
        'cashierBalanceEnabled': PosPaymentChannelKind.balance,
        'cashier.balance': PosPaymentChannelKind.balance,
        'online_combined': PosPaymentChannelKind.combined,
        'partial_cash': PosPaymentChannelKind.combined,
        '组合支付': PosPaymentChannelKind.combined,
        'cashierCombinedEnabled': PosPaymentChannelKind.combined,
        'clients.cashier.channels.combined': PosPaymentChannelKind.combined,
      };

      for (final entry in aliases.entries) {
        expect(
          PosPaymentChannelKind.normalize(entry.key),
          entry.value,
          reason: entry.key,
        );
      }
      expect(PosPaymentChannelKind.normalize('unsupported'), isNull);
      expect(
        PosPaymentChannelKind.normalize('offline_collect_enabled'),
        isNull,
      );
      expect(PosPaymentChannelKind.cash.canonicalCode, 'cash');
      expect(PosPaymentChannelKind.wechat.canonicalCode, 'offline_wechat_qr');
      expect(PosPaymentChannelKind.alipay.canonicalCode, 'offline_alipay_qr');
      expect(PosPaymentChannelKind.balance.canonicalCode, 'online_balance');
      expect(PosPaymentChannelKind.combined.canonicalCode, 'online_combined');
    });

    test('settlement counts positive channels and balances minor units', () {
      const settlement = PosCheckoutSettlement(
        wechatMinor: 1234,
        alipayMinor: 0,
        balanceMinor: 100,
        cashMinor: 666,
        cashTenderMinor: 1000,
        changeAmountMinor: 334,
        changeChannel: PosChangeChannel.cash,
      );

      expect(settlement.positiveChannelCount, 3);
      expect(settlement.isBalanced(2000), isTrue);
      expect(settlement.isBalanced(1999), isFalse);
    });

    test(
      'loads cashier payment methods from order-scoped capabilities',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/category/listAll': jsonEncode({
            'code': 200,
            'data': {'categoryList': []},
          }),
          'POST /admin/dish/list': jsonEncode({
            'code': 200,
            'data': {'dishList': []},
          }),
          'GET /admin/table/status': jsonEncode({
            'code': 200,
            'data': {
              'tableList': [
                {'id': 120, 'number': '40', 'status': 1},
              ],
              'orderList': [
                {'id': 40, 'order_no': 'ORD40', 'sett_amount': 20},
              ],
            },
          }),
          'GET /config/payment-capabilities': jsonEncode({
            'code': 0,
            'data': {
              'clients': {
                'cashier': {
                  'paymentMethods': [
                    {
                      'code': 'cash',
                      'name': '现金',
                      'type': 'offline',
                      'enabled': true,
                      'sortOrder': 0,
                    },
                    {
                      'code': 'online_combined',
                      'name': '组合支付',
                      'type': 'online',
                      'enabled': true,
                      'sortOrder': 30,
                    },
                    {
                      'code': 'offline_wechat_qr',
                      'name': '微信收款码',
                      'type': 'offline',
                      'enabled': true,
                      'sortOrder': 10,
                    },
                    {
                      'code': 'wechat',
                      'name': '微信支付（兼容项）',
                      'type': 'offline',
                      'enabled': true,
                      'sortOrder': 11,
                    },
                    {
                      'code': 'offline_alipay_qr',
                      'name': '支付宝收款码',
                      'type': 'offline',
                      'enabled': true,
                      'sortOrder': 12,
                    },
                    {
                      'code': 'online_balance',
                      'name': '余额支付',
                      'type': 'online',
                      'enabled': false,
                      'sortOrder': 20,
                    },
                  ],
                },
              },
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        final workspace = await repository.loadWorkspace(
          DiningTable.fromJson({'id': 120, 'number': '40', 'status': 1}),
        );

        expect(workspace.paymentMethods.map((method) => method.kind), [
          PosPaymentChannelKind.cash,
          PosPaymentChannelKind.wechat,
          PosPaymentChannelKind.alipay,
          PosPaymentChannelKind.combined,
        ]);
        expect(workspace.paymentConfigurationAvailable, isTrue);
        final request = transport.requests.singleWhere(
          (item) => item.uri.path == '/config/payment-capabilities',
        );
        expect(request.method, 'GET');
        expect(request.uri.queryParameters, {'order_no': 'ORD40'});
        expect(request.headers['X-Shop-Id'], '2');
      },
    );

    test('loads unified effective cashier payment channels', () async {
      final transport = FakeHttpTransport({
        'GET /admin/category/listAll': jsonEncode({
          'code': 200,
          'data': {'categoryList': []},
        }),
        'POST /admin/dish/list': jsonEncode({
          'code': 200,
          'data': {'dishList': []},
        }),
        'GET /config/payment-capabilities': jsonEncode({
          'code': 0,
          'data': {
            'clients': {
              'cashier': {
                'effectiveEnabled': true,
                'effectiveChannels': {
                  'wechat': true,
                  'alipay': false,
                  'balance': true,
                  'combined': true,
                },
              },
            },
          },
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 2,
        ),
      );

      final workspace = await repository.loadWorkspace(
        DiningTable.fromJson({'id': 120, 'number': '40', 'status': 0}),
      );

      expect(workspace.paymentConfigurationAvailable, isTrue);
      expect(workspace.paymentMethods.map((method) => method.kind), [
        PosPaymentChannelKind.cash,
        PosPaymentChannelKind.wechat,
        PosPaymentChannelKind.balance,
        PosPaymentChannelKind.combined,
        PosPaymentChannelKind.receivable,

      ]);
    });

    test('posts complete combined checkout amounts from minor units', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/checkout': jsonEncode({
          'code': 0,
          'order_no': 'ORD40',
          'payment_channel_code': 'online_combined',
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 2,
        ),
      );

      await repository.checkoutCombined(
        orderNo: 'ORD40',
        memberOpenid: 'member-openid',
        memberPhone: '13800000000',
        settlement: const PosCheckoutSettlement(
          wechatMinor: 1234,
          alipayMinor: 0,
          balanceMinor: 100,
          cashMinor: 666,
          cashTenderMinor: 1000,
          changeAmountMinor: 334,
          changeChannel: PosChangeChannel.cash,
        ),
      );

      expect(jsonDecode(transport.requests.single.body!), {
        'order_no': 'ORD40',
        'payment_method': 'online_combined',
        'pay_amount_wechat': 12.34,
        'pay_amount_alipay': 0,
        'pay_amount_balance': 1,
        'pay_amount_cash': 6.66,
        'checkout_cash_tender': 10,
        'checkout_change_amount': 3.34,
        'openid': 'member-openid',
        'member_phone': '13800000000',
        'checkout_change_channel': 'cash',
      });
      expect(transport.requests.single.headers['X-Shop-Id'], '2');
    });

    test(
      'offline QR confirmation is not treated as completed checkout',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/order/checkout': jsonEncode({
            'code': 0,
            'data': {
              'order_no': 'ORD40',
              'payment_channel_code': 'offline_wechat_qr',
              'status': 'CONFIRMED',
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        await expectLater(
          repository.checkout(
            orderNo: 'ORD40',
            paymentMethod: 'offline_wechat_qr',
            collectionSessionId: 'collection-session-1',
          ),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('尚未完成结账'),
            ),
          ),
        );
      },
    );

    test(
      'offline QR cancellation releases the exact cashier session',
      () async {
        final transport = FakeHttpTransport({
          'POST /pay/offline-collect/cancel': jsonEncode({'code': 0}),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        await repository.cancelOfflineCollection(
          channel: 'wechat',
          orderNo: 'ORD40',
          sessionId: 'collection-session-1',
        );

        expect(transport.requests.single.headers['X-Shop-Id'], '2');
        expect(jsonDecode(transport.requests.single.body!), {
          'channel': 'wechat',
          'order_no': 'ORD40',
          'session_id': 'collection-session-1',
        });
      },
    );

    test(
      'offline QR checkout reconciles an incomplete response against order status',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/order/checkout': jsonEncode({
            'code': 0,
            'data': {
              'order_no': 'ORD40',
              'payment_channel_code': 'offline_wechat_qr',
              'status': 'CONFIRMED',
            },
          }),
          'GET /admin/table/status': jsonEncode({
            'code': 200,
            'data': {
              'orderList': [
                {'order_no': 'ORD40', 'transac_status': 'success'},
              ],
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        await repository.checkout(
          orderNo: 'ORD40',
          paymentMethod: 'offline_wechat_qr',
          collectionSessionId: 'collection-session-1',
        );

        expect(transport.requests, hasLength(2));
        expect(transport.requests.last.uri.path, '/admin/table/status');
        expect(transport.requests.last.uri.queryParameters, {
          'orderNo': 'ORD40',
        });
      },
    );

    test(
      'offline QR checkout completes only with matching order and channel',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/order/checkout': jsonEncode({
            'code': 0,
            'order_no': 'ORD40',
            'payment_method': '微信收款码',
            'payment_channel_code': 'offline_wechat_qr',
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        await repository.checkout(
          orderNo: 'ORD40',
          paymentMethod: 'offline_wechat_qr',
          collectionSessionId: 'collection-session-1',
        );

        expect(jsonDecode(transport.requests.single.body!), {
          'order_no': 'ORD40',
          'payment_method': 'offline_wechat_qr',
          'collection_session_id': 'collection-session-1',
        });
      },
    );

    test(
      'combined QR payment also rejects a pending checkout response',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/order/checkout': jsonEncode({
            'code': 0,
            'data': {
              'order_no': 'ORD40',
              'payment_channel_code': 'online_combined',
              'status': 'CONFIRMED',
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 'token',
            shopId: 2,
          ),
        );

        await expectLater(
          repository.checkoutCombined(
            orderNo: 'ORD40',
            settlement: const PosCheckoutSettlement(
              wechatMinor: 4000,
              cashMinor: 2000,
              cashTenderMinor: 2000,
            ),
            collectionSessionId: 'collection-session-1',
          ),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test('offline QR checkout rejects an online channel response', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/checkout': jsonEncode({
          'code': 0,
          'order_no': 'ORD40',
          'payment_channel_code': 'online_wechat',
          'status': 'success',
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 2,
        ),
      );

      await expectLater(
        repository.checkout(
          orderNo: 'ORD40',
          paymentMethod: 'offline_wechat_qr',
          collectionSessionId: 'collection-session-1',
        ),
        throwsA(isA<ApiException>()),
      );
    });
  });
}
