import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/features/auth/data/auth_repository.dart';
import 'package:admin_panel_flutter/src/features/catalog/data/real_catalog_repository.dart';
import 'package:admin_panel_flutter/src/features/catalog/domain/catalog_models.dart';
import 'package:admin_panel_flutter/src/features/orders/data/real_order_repository.dart';
import 'package:admin_panel_flutter/src/features/orders/data/pending_refund_store.dart';
import 'package:admin_panel_flutter/src/features/orders/domain/admin_order.dart';
import 'package:admin_panel_flutter/src/features/orders/domain/order_query.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/realtime/domain/realtime_models.dart';
import 'package:admin_panel_flutter/src/features/tables/data/real_table_repository.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:admin_panel_flutter/src/features/users/data/real_user_repository.dart';
import 'package:admin_panel_flutter/src/features/users/domain/admin_user.dart';
import 'package:admin_panel_flutter/src/features/users/domain/user_operation.dart';
import 'package:admin_panel_flutter/src/features/users/domain/user_query.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('P0 auth and request contracts', () {
    test(
      'login pulls token, permissions and shops from real endpoints',
      () async {
        final transport = FakeHttpTransport({
          'POST /adminLogin': jsonEncode({
            'code': 200,
            'data': {'token': 'jwt-token', 'scope': 'HQ'},
          }),
          'GET /admin/me/permissions': jsonEncode({
            'code': 200,
            'data': {
              'scope': 'HQ',
              'permissions': ['user:view', 'statistics:view'],
            },
          }),
          'GET /admin/me/shops': jsonEncode({
            'code': 200,
            'data': {
              'shops': [
                {'id': 2, 'code': 'SHOP002', 'name': '大学城店'},
              ],
            },
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
        );

        final session = await AuthRepository(
          client,
        ).login(username: 'admin', password: 'pw');

        expect(session.token, 'jwt-token');
        expect(session.permissions, contains('user:view'));
        expect(session.shops.single.id, 2);
        final loginBody =
            jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
        expect(loginBody['userName'], 'admin');
        expect(loginBody['password'], 'pw');
        expect(
          transport.requests.last.headers['Authorization'],
          'Bearer jwt-token',
        );
      },
    );

    test(
      'login loads every authorized shop page with the OpenAPI limit',
      () async {
        final transport = _PagedAuthorizedShopsTransport();
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
        );

        final session = await AuthRepository(
          client,
        ).login(username: 'admin', password: 'pw');

        expect(session.shops, hasLength(201));
        expect(session.shops.first.name, '门店 1');
        expect(session.shops.last.name, '门店 201');
        final shopRequests = transport.requests
            .where((request) => request.uri.path == '/admin/me/shops')
            .toList(growable: false);
        expect(
          shopRequests.map((request) => request.uri.queryParameters['page']),
          ['1', '2'],
        );
        expect(
          shopRequests.map(
            (request) => request.uri.queryParameters['pageSize'],
          ),
          ['200', '200'],
        );
      },
    );

    test(
      'restores a session from a saved token without posting credentials',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/me/permissions': jsonEncode({
            'code': 200,
            'data': {
              'scope': 'HQ',
              'permissions': ['cashier:operate'],
            },
          }),
          'GET /admin/me/shops': jsonEncode({
            'code': 200,
            'data': {
              'shops': [
                {'id': 2, 'code': 'SHOP002', 'name': '大学城店'},
              ],
            },
          }),
        });
        final repository = AuthRepository(
          AdminApiClient(baseUrl: 'http://api.test', transport: transport),
        );

        final session = await repository.restoreSession(
          'saved-jwt',
          actorName: 'cashier',
        );

        expect(session.token, 'saved-jwt');
        expect(session.actorName, 'cashier');
        expect(session.permissions, {'cashier:operate'});
        expect(session.shops.single.id, 2);
        expect(transport.requests, hasLength(2));
        expect(
          transport.requests.every((request) => request.method == 'GET'),
          isTrue,
        );
        expect(
          transport.requests.every(
            (request) => request.headers['Authorization'] == 'Bearer saved-jwt',
          ),
          isTrue,
        );
      },
    );

    test('admin request attaches shop header except whitelist paths', () {
      final request = const UserQuery().toAdminRequest(
        token: 'token',
        shopId: 2,
      );
      expect(request.endpoint, getUserInfoEndpoint);
      expect(request.headers['Authorization'], 'Bearer token');
      expect(request.headers['X-Shop-Id'], '2');

      final headers = adminHeaders(
        token: 'token',
        shopId: 2,
        endpoint: const AdminEndpoint(
          method: 'POST',
          path: '/adminLogin',
          permissionCode: 'public',
        ),
      );
      expect(headers.containsKey('X-Shop-Id'), isFalse);
    });

    test(
      'authenticated business requests require and attach shop context',
      () async {
        final missingShopClient = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: FakeHttpTransport(const {}),
          token: 'token',
        );
        await expectLater(
          missingShopClient.get(cashierOrderTodayEndpoint),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('缺少当前门店上下文'),
            ),
          ),
        );

        final transport = FakeHttpTransport({
          'GET /cashier/order/today': jsonEncode({'code': 0, 'list': []}),
        });
        await AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 9,
        ).get(cashierOrderTodayEndpoint);

        expect(transport.requests.single.headers['X-Shop-Id'], '9');
      },
    );
  });

  group('P1 user contracts', () {
    test(
      'AdminUser parses new OpenAPI user metrics with missing fields as zero',
      () {
        final user = AdminUser.fromJson({
          'id': 7,
          'openid': 'openid-7',
          'name': '测试用户',
          'phone': '13800000000',
          'consume_amount': 128.5,
        });

        expect(user.inviteRegisteredCount, 0);
        expect(user.availableCouponCount, 0);
        expect(user.consumeAmount, 128.5);
      },
    );

    test(
      'RealUserRepository omits empty parameters and caps pageSize at 100',
      () async {
        final transport = FakeHttpTransport({
          'POST /admin/order/getUserInfo': jsonEncode({
            'code': 200,
            'data': {
              'records': [
                {'id': 1, 'openid': 'o1', 'consume_amount': 10},
              ],
              'total': 1,
            },
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
        );

        final page = await RealUserRepository(client).getUsers(
          const UserQuery(
            pageNum: 2,
            pageSize: 500,
            query: '  张三  ',
            amountSort: 'invalid',
          ),
          shopId: 2,
        );

        expect(page.total, 1);
        expect(transport.requests.single.headers['X-Shop-Id'], '2');
        final body =
            jsonDecode(transport.requests.single.body!) as Map<String, Object?>;
        expect(body, {
          'pageNum': 2,
          'pageSize': 100,
          'query': '张三',
          'includeStats': true,
        });
      },
    );

    test('operation entries respect user and coupon permissions', () {
      final labels = visibleUserOperations({
        'user:view',
        'user:recharge',
      }).map((operation) => operation.label).toList();

      expect(labels, contains('充值'));
      expect(labels, isNot(contains('加积分')));
      expect(labels, isNot(contains('发券')));
    });
  });

  group('P2 cashier order contracts', () {
    test(
      'real order repository exposes todayCount and checkout change fields',
      () async {
        final transport = FakeHttpTransport({
          'POST /admin/order/list': jsonEncode({
            'code': 200,
            'data': {
              'records': [
                {
                  'id': 1,
                  'order_no': 'ORD1',
                  'checkout_cash_tender': 150,
                  'checkout_change_amount': 21.5,
                  'checkout_change_channel_label': '现金找零',
                  'kds_order_status': 'cooking',
                },
              ],
              'total': 1,
            },
          }),
          'GET /admin/order/todayCount': jsonEncode({'code': 200, 'data': 6}),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
        );

        final page = await RealOrderRepository(client).listOrders(
          const OrderQuery(pageNum: 2, pageSize: 20, status: 'unsettled'),
          shopId: 1,
        );
        final first = page.orders.first;

        expect(page.todayCount, 6);
        expect(first.checkoutCashTender, 150);
        expect(first.checkoutChangeAmount, 21.5);
        expect(first.checkoutChangeChannelLabel, '现金找零');
        expect(first.kdsOrderStatus, 'cooking');
        final listBody =
            jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
        expect(listBody['pageNum'], 2);
        expect(listBody['pageSize'], 20);
        expect(listBody['start'], 20);
        expect(listBody['transac_status'], 'unsettled');
        expect(listBody['query'], 'unsettled');
      },
    );

    test('cashier hang order endpoint posts order_no and parses hang number',
        () async {
      expect(cashierOrderHangEndpoint.method, 'POST');
      expect(cashierOrderHangEndpoint.path, '/cashier/order/hang');
      expect(cashierOrderHangEndpoint.permissionCode, 'cashier:operate');

      final transport = FakeHttpTransport({
        'POST /cashier/order/hang': jsonEncode({
          'code': 0,
          'data': {'hang_no': 'HANG-88'},
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 't',
        shopId: 3,
      );
      final hangNo = await RealPosRepository(client).hangOrder(
        orderNo: ' ORD1 ',
      );
      expect(hangNo, 'HANG-88');
      final body = jsonDecode(transport.requests.single.body!) as Map<String, Object?>;
      expect(body['order_no'], 'ORD1');
      expect(transport.requests.single.headers['X-Shop-Id'], '3');
    });

    test('hang order tolerates missing hang number in response', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/hang': jsonEncode({'code': 0, 'data': <String, Object?>{}}),
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 't',
        shopId: 3,
      );
      expect(await RealPosRepository(client).hangOrder(orderNo: 'ORD2'), isNull);
    });

    test('order repository parses legacy orderList response fields', () async {
      final transport = FakeHttpTransport({
        'POST /admin/order/list': jsonEncode({
          'code': 0,
          'orderList': [
            {
              'id': 11901,
              'order_no': 'ORD20260703053134717',
              'table_number': '22',
              'sett_amount': 65,
              'transac_status': 'unsettled',
              'order_receiving': 'rec_order',
              'dineInOrTakeOut': '堂食',
              'order_time': '2026-07-03 05:31:34',
            },
          ],
          'total': 8490,
        }),
        'GET /admin/order/todayCount': jsonEncode({'code': 0, 'data': 1}),
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 't',
        shopId: 1,
      );

      final page = await RealOrderRepository(
        client,
      ).listOrders(const OrderQuery(), shopId: 1);

      expect(page.total, 8490);
      expect(page.orders.single.totalAmount, 65);
      expect(page.orders.single.receivingStatus, 'rec_order');
      expect(page.orders.single.payStatus, 'unsettled');
      expect(page.orders.single.orderType, '堂食');
      final body =
          jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
      expect(body['query'], '');
      expect(body['transac_status'], '');
      expect(body['start'], 0);
    });

    test('order detail endpoint fills drawer line items', () async {
      final transport = FakeHttpTransport({
        'GET /admin/orderDetail/list': jsonEncode({
          'code': 0,
          'orderDetailList': [
            {
              'id': 21,
              'dish_name': '油边王',
              'quantity': 2,
              'line_status': 'normal',
            },
          ],
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 't',
        shopId: 1,
      );
      final order = AdminOrder.fromJson({'id': 11901, 'order_no': 'ORD1'});

      final detail = await RealOrderRepository(client).loadOrderDetails(order);

      expect(transport.requests.single.uri.queryParameters['id'], '11901');
      expect(detail.lines.single.name, '油边王');
      expect(detail.lines.single.quantity, 2);
    });

    test(
      'refund only targets normal lines and reprint keeps receiving status',
      () async {
        final transport = FakeHttpTransport({
          'POST /admin/orderDetail/delete_menu': jsonEncode({
            'code': 200,
            'data': {},
          }),
          'POST /cashier/print/dispatch': jsonEncode({'code': 200, 'data': {}}),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 1,
        );
        final repository = RealOrderRepository(client);
        final order = AdminOrder.fromJson({
          'id': 1,
          'order_no': 'ORD1',
          'receiving_status': 'accepted',
          'lines': [
            {'id': 11, 'name': '正常菜', 'quantity': 1, 'line_status': 'normal'},
            {'id': 12, 'name': '已退菜', 'quantity': 1, 'line_status': 'refunded'},
          ],
        });

        final refunded = await repository.refundNormalLines(order);
        final refundBody =
            jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
        expect(refundBody['id'], 11);
        expect(refunded.lines.map((line) => line.lineStatus), [
          'refunded',
          'refunded',
        ]);

        final reprinted = await repository.reprintKitchenTicket(order);
        expect(reprinted.receivingStatus, order.receivingStatus);
      },
    );

    test('wechat refund sends a stable 64-character idempotency key', () async {
      final transport = _LoseFirstRefundResponseTransport();
      final repository = RealOrderRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 1,
        ),
        refundStore: _FakePendingRefundStore(),
      );
      final order = AdminOrder.fromJson({
        'id': 1,
        'order_no': 'ORD-REFUND-1',
        'transaction_id': 'WX-TXN-1',
        'refund_amount': 5,
      });

      await expectLater(
        repository.refundWechat(order, amount: 12.34, reason: '顾客退单'),
        throwsA(isA<StateError>()),
      );
      await repository.refundWechat(order, amount: 12.34, reason: '顾客退单');

      final first =
          jsonDecode(transport.requests[0].body!) as Map<String, Object?>;
      final retry =
          jsonDecode(transport.requests[1].body!) as Map<String, Object?>;
      expect(first['idempotency_key'], hasLength(64));
      expect(retry['idempotency_key'], first['idempotency_key']);
    });

    test('wechat refund retry after callback reuses the pending key', () async {
      final transport = _LoseFirstRefundResponseTransport();
      final store = _FakePendingRefundStore();
      final repository = RealOrderRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 1,
        ),
        refundStore: store,
      );
      final original = AdminOrder.fromJson({
        'id': 1,
        'order_no': 'ORD-REFUND-2',
        'transaction_id': 'WX-TXN-2',
        'refund_amount': 5,
      });
      await expectLater(
        repository.refundWechat(original, amount: 12.34, reason: '顾客退单'),
        throwsA(isA<StateError>()),
      );
      final afterCallback = AdminOrder.fromJson({
        'id': 1,
        'order_no': 'ORD-REFUND-2',
        'transaction_id': 'WX-TXN-2',
        'refund_amount': 17.34,
      });

      await repository.refundWechat(
        afterCallback,
        amount: 12.34,
        reason: '顾客退单',
      );

      expect(transport.requests, hasLength(2));
      final first =
          jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
      final retry =
          jsonDecode(transport.requests.last.body!) as Map<String, Object?>;
      expect(retry['idempotency_key'], first['idempotency_key']);
      expect(await store.read('ORD-REFUND-2'), isNull);
    });

    test('terminal refund conflict clears the rejected pending key', () async {
      final store = _FakePendingRefundStore();
      final transport = _ConflictAfterReplacingStoreTransport(store);
      final repository = RealOrderRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 1,
        ),
        refundStore: store,
      );
      final order = AdminOrder.fromJson({
        'id': 1,
        'order_no': 'ORD-REFUND-CONFLICT',
        'transaction_id': 'WX-TXN-CONFLICT',
      });

      await expectLater(
        repository.refundWechat(order, amount: 30, reason: 'duplicate window'),
        throwsA(isA<ApiException>()),
      );

      expect(
        (await store.read(order.orderNo))?.idempotencyKey,
        'other-window-key',
      );
    });

    test(
      'RealOrderRepository.fetchPrintPreview calls /admin/printing/preview and parses AST',
      () async {
        final transport = FakeHttpTransport({
          'POST /admin/printing/preview': jsonEncode({
            'code': 0,
            'data': {
              'scenario': 'CHECKOUT',
              'scenarioName': '结账小票',
              'paperSize': '80mm',
              'paperWidthMm': 80,
              'paperWidthChars': 48,
              'shopName': '老肥油边王',
              'totalTickets': 1,
              'tickets': [
                {
                  'ticketIndex': 1,
                  'title': '客户联',
                  'rawContent': 'RAW',
                  'plainText': '老肥油边王 结账单',
                  'elements': [
                    {
                      'type': 'HEADER',
                      'text': '老肥油边王 结账单',
                      'align': 'CENTER',
                      'bold': true,
                    },
                  ],
                },
              ],
            },
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token123',
          shopId: 1,
        );
        final repo = RealOrderRepository(client);

        final preview = await repo.fetchPrintPreview(
          scenario: 'CHECKOUT',
          orderId: 101,
          orderNo: 'ORD101',
          paperSize: '80mm',
        );

        expect(preview.scenario, 'CHECKOUT');
        expect(preview.tickets.first.elements.first.text, '老肥油边王 结账单');
        final reqBody =
            jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
        expect(reqBody['scenario'], 'CHECKOUT');
        expect(reqBody['orderId'], 101);
        expect(reqBody['orderNo'], 'ORD101');
        expect(reqBody['paperSize'], '80mm');
      },
    );

    test(
      'RealPosRepository.fetchPrintPreview calls /admin/printing/preview with parameters',
      () async {
        final transport = FakeHttpTransport({
          'POST /admin/printing/preview': jsonEncode({
            'code': 0,
            'data': {'scenario': 'ORDER', 'paperSize': '58mm', 'tickets': []},
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token123',
          shopId: 1,
        );
        final repo = RealPosRepository(client);

        final preview = await repo.fetchPrintPreview(
          scenario: 'ORDER',
          orderId: 202,
          orderNo: 'ORD202',
          paperSize: '58mm',
        );

        expect(preview.scenario, 'ORDER');
        expect(preview.paperSize, '58mm');
        final reqBody =
            jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
        expect(reqBody['scenario'], 'ORDER');
        expect(reqBody['orderId'], 202);
        expect(reqBody['orderNo'], 'ORD202');
      },
    );
  });

  group('P3 catalog and finance contracts', () {
    test('real dish stock is scoped by t_dish_shop shop dimension', () async {
      final transport = FakeHttpTransport({
        'POST /admin/dish/list': jsonEncode({
          'code': 200,
          'data': {
            'records': [
              {'id': 9, 'shop_id': 2, 'stock': 8, 'onsale': 1, 'sold_out': 0},
            ],
          },
        }),
      });
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 't',
      );

      final stock = await RealCatalogRepository(
        client,
      ).loadDishStock(dishId: 9, shopId: 2);

      expect(stock.shopId, 2);
      expect(stock.stock, 8);
      expect(transport.requests.single.headers['X-Shop-Id'], '2');
    });

    test('on sale and sold out updates do not overwrite each other', () {
      final stock = DishShopStock.fromJson({
        'dish_id': 1,
        'shop_id': 1,
        'stock': 3,
        'onsale': 1,
        'sold_out': 0,
      });

      expect(stock.updateOnSale(false).soldOut, isFalse);
      expect(stock.updateSoldOut(true).onsale, isTrue);
    });

    test('dashboard revenue and recharge totals match OpenAPI formula', () {
      const revenue = DashboardRevenue(
        settAmount: 100,
        discountAmount: 8,
        serviceFee: 3,
        refundAmount: 4,
        payAmountGift: 6,
      );
      expect(revenue.businessRevenueNet, 85);

      final total = successfulRechargeTotal(const [
        MemberRechargeFlow(amount: 100, giftAmount: 10, status: 'success'),
        MemberRechargeFlow(amount: 200, giftAmount: 20, status: 'pending'),
      ]);
      expect(total, 110);
    });
  });

  group('P4 realtime contracts', () {
    test('KDS devices use device token and screen tag binding', () {
      const session = KdsDeviceSession(
        deviceToken: 'device-token',
        screenTag: 'grill',
        shopId: 1,
      );

      expect(session.headers, {'X-Kds-Device-Token': 'device-token'});
      expect(session.acceptsScreenTag('grill'), isTrue);
      expect(session.acceptsScreenTag('bar'), isFalse);
    });

    test(
      'reconnect plan and takeout actions encode sync and liability rules',
      () {
        const reconnect = KdsReconnectPlan(
          wsPath: '/ws/kds',
          incrementalSyncPath: '/kds/sync/changes',
          lastEventId: 10,
        );

        expect(reconnect.requiresIncrementalSync, isTrue);
        expect(cancelDeliveryAction.requiresLiabilityPrompt, isTrue);
        expect(refundTakeoutAction.requiresLiabilityPrompt, isTrue);
      },
    );
  });

  group('P5 table status contracts', () {
    test('table overview counts dine-in from occupied tables only', () {
      final overview = TableOverview(
        tables: [
          DiningTable.fromJson({'number': '1', 'status': 0}),
          DiningTable.fromJson({'number': '2', 'status': 1}),
          DiningTable.fromJson({'number': '3', 'status': 2}),
        ],
        takeoutOrders: [
          FulfillmentOrder.fromJson({
            'id': 2036,
            'receiving_status': 'mis_order',
          }, type: FulfillmentType.takeout),
          FulfillmentOrder.fromJson({
            'id': 2037,
            'dispatch_status': 'delivering',
          }, type: FulfillmentType.takeout),
          FulfillmentOrder.fromJson({
            'id': 2038,
            'receiving_status': 'off_order',
          }, type: FulfillmentType.takeout),
        ],
        pickupOrders: [
          FulfillmentOrder.fromJson({
            'id': 2040,
            'receiving_status': 'rec_order',
          }, type: FulfillmentType.pickup),
          FulfillmentOrder.fromJson({
            'id': 2041,
            'receiving_status': 'off_order',
          }, type: FulfillmentType.pickup),
        ],
      );

      expect(overview.dineInCount, 2);
      expect(overview.takeoutCount, 2);
      expect(overview.pickupCount, 1);
    });

    test('fulfillment cards parse pickup code, elapsed time and statuses', () {
      final takeout = FulfillmentOrder.fromJson({
        'id': 2036,
        'dispatch_status': 'delivering',
        'kds_order_status': 20,
        'order_time': '2026-07-09 11:24:00',
      }, type: FulfillmentType.takeout);
      final pickup = FulfillmentOrder.fromJson({
        'id': 2037,
        'receiving_status': 'off_order',
        'order_time': '2026-07-09 11:24:00',
      }, type: FulfillmentType.pickup);

      expect(takeout.displayCode, 'B2036');
      expect(takeout.status, FulfillmentStatus.delivering);
      expect(takeout.kdsOrderStatus, '20');
      expect(
        takeout.elapsedDuration(DateTime(2026, 7, 9, 12)),
        const Duration(minutes: 36),
      );
      expect(pickup.displayCode, 'A2037');
      expect(pickup.status, FulfillmentStatus.completed);
    });

    test(
      'unsettled fulfillment order takes precedence over delivery state',
      () {
        final order = FulfillmentOrder.fromJson({
          'id': 88,
          'order_no': 'ORD88',
          'transac_status': 'unsettled',
          'dispatch_status': 'delivering',
          'sett_amount': 126.5,
        }, type: FulfillmentType.takeout);

        expect(order.status, FulfillmentStatus.pendingPayment);
        expect(order.orderNo, 'ORD88');
        expect(order.tableNumber, '');
        expect(order.amount, 126.5);
        expect(order.dispatchStatus, 'delivering');
      },
    );

    test(
      'tableless fulfillment detail resolves by order number from table status',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/table/status': jsonEncode({
            'code': 0,
            'data': {
              'tableList': [],
              'orderList': [
                {
                  'id': 88,
                  'order_no': 'ORD88',
                  'table_number': null,
                  'pickup_code': 'B2088',
                  'transac_status': 'success',
                  'dispatch_status': 'delivering',
                  'payment_method': '微信支付',
                  'sett_amount': 45,
                  'goods_list': [
                    {
                      'dish_name': '油边王',
                      'quantity': 3,
                      'unit_price': 15,
                      'total_price': 45,
                      'selectedSpicy': '辣度：微辣',
                    },
                  ],
                },
              ],
            },
          }),
        });
        final repository = RealTableRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final order = FulfillmentOrder.fromJson({
          'id': 88,
          'order_no': 'ORD88',
          'table_number': '',
        }, type: FulfillmentType.takeout);

        final detail = await repository.loadFulfillmentOrderDetail(order);

        final request = transport.requests.single;
        expect(request.uri.path, '/admin/table/status');
        expect(request.uri.queryParameters, {'orderNo': 'ORD88'});
        expect(request.headers['X-Shop-Id'], '2');
        expect(detail.order.orderNo, 'ORD88');
        expect(detail.order.tableNumber, '');
        expect(detail.paymentMethod, '微信支付');
        expect(detail.lines.single.name, '油边王');
        expect(detail.lines.single.quantity, 3);
        expect(detail.lines.single.specification, '微辣');
      },
    );

    test(
      'table repository updates pickup and takeout through real endpoints',
      () async {
        final transport = FakeHttpTransport({
          'POST /admin/order/receiving': jsonEncode({'code': 0}),
          'POST /admin/takeout/delivery/status': jsonEncode({'code': 0}),
        });
        final repository = RealTableRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final pickup = FulfillmentOrder.fromJson({
          'id': 18,
        }, type: FulfillmentType.pickup);
        final takeout = FulfillmentOrder.fromJson({
          'id': 19,
        }, type: FulfillmentType.takeout);

        await repository.updateFulfillmentStatus(
          pickup,
          FulfillmentStatus.completed,
        );
        await repository.updateFulfillmentStatus(
          takeout,
          FulfillmentStatus.delivering,
        );

        expect(jsonDecode(transport.requests[0].body!), {
          'id': 18,
          'order_receiving': 'off_order',
        });
        expect(jsonDecode(transport.requests[1].body!), {
          'orderId': 19,
          'dispatch_status': 'delivering',
        });
        expect(
          transport.requests.every(
            (request) => request.headers['X-Shop-Id'] == '2',
          ),
          isTrue,
        );
      },
    );

    test(
      'real table repository counts active takeout and pickup without filtering tables',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/table/status': jsonEncode({
            'code': 200,
            'data': {
              'tableList': [
                {'number': '1', 'status': 0},
                {'number': '2', 'status': 1},
                {'number': '3', 'status': 2},
              ],
            },
          }),
          'POST /admin/order/list': jsonEncode({
            'code': 200,
            'data': {
              'records': [
                {'receiving_status': 'mis_order', 'order_type': '外卖'},
                {
                  'receiving_status': 'rec_order',
                  'order_type': '外卖',
                  'dispatch_status': 'delivering',
                },
                {'receiving_status': 'rec_order', 'order_type': '自提'},
                {'receiving_status': 'off_order', 'order_type': '外卖'},
                {'receiving_status': 'mis_order', 'order_type': '堂食'},
              ],
            },
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        );

        final overview = await RealTableRepository(client).loadTableOverview();

        expect(overview.tables.length, 3);
        expect(overview.dineInCount, 2);
        expect(overview.takeoutCount, 2);
        expect(overview.pickupCount, 1);
        expect(overview.takeoutOrders.length, 3);
        expect(
          overview.takeoutOrders.map((order) => order.status),
          containsAll([
            FulfillmentStatus.waiting,
            FulfillmentStatus.delivering,
            FulfillmentStatus.completed,
          ]),
        );
        final paths = transport.requests.map((request) => request.uri.path);
        // 桌台概览先尝试收银状态图（/cashier/table/statusMap），空响应时
        // 回退运营端快照（/admin/table/status），外卖/自提计数走订单列表。
        expect(
          paths,
          unorderedEquals([
            '/cashier/table/statusMap',
            '/admin/table/status',
            '/admin/order/list',
          ]),
        );
        final orderRequest = transport.requests.singleWhere(
          (request) => request.uri.path == '/admin/order/list',
        );
        expect(orderRequest.headers['X-Shop-Id'], '2');
        final body = jsonDecode(orderRequest.body!) as Map<String, Object?>;
        expect(body['pageSize'], 100);
      },
    );

    test(
      'cashier table status map drives the table overview from list rows',
      () async {
        final transport = FakeHttpTransport({
          'GET /cashier/table/statusMap': jsonEncode({
            'code': 0,
            'data': {
              'list': [
                {'id': 1, 'number': '3', 'status': 1, 'number_of_diners': 2},
                {'id': 2, 'number': '5', 'status': 0},
              ],
            },
          }),
          'POST /admin/order/list': jsonEncode({
            'code': 200,
            'data': {'records': <Object?>[], 'total': 0},
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        );

        final overview = await RealTableRepository(client).loadTableOverview();

        expect(overview.tables.length, 2);
        expect(overview.tables.first.number, '3');
        expect(overview.tables.first.status, TableStatus.pending);
        expect(overview.tables.last.status, TableStatus.empty);
        final paths = transport.requests.map((request) => request.uri.path);
        expect(
          paths,
          unorderedEquals(['/cashier/table/statusMap', '/admin/order/list']),
        );
      },
    );

    test(
      'cashier table status map exposes map shape as table status cards',
      () async {
        final transport = FakeHttpTransport({
          'GET /cashier/table/statusMap': jsonEncode({
            'code': 0,
            'data': {
              'map': {'3': 1, '5': 0, '7': 2},
            },
          }),
          'POST /admin/order/list': jsonEncode({
            'code': 200,
            'data': {'records': <Object?>[], 'total': 0},
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        );

        final overview = await RealTableRepository(client).loadTableOverview();

        expect(overview.tables.length, 3);
        expect(overview.tables.first.number, '3');
        expect(overview.tables.first.status, TableStatus.pending);
        expect(overview.tables.last.number, '7');
        expect(overview.tables.last.status, TableStatus.settled);
        expect(
          transport.requests.any(
            (request) => request.uri.path == '/admin/table/status',
          ),
          isFalse,
        );
      },
    );

    test(
      'cashier table status map failure falls back to the legacy admin snapshot',
      () async {
        final transport = FakeHttpTransport({
          'GET /cashier/table/statusMap': jsonEncode({
            'code': 500,
            'message': 'boom',
          }),
          'GET /admin/table/status': jsonEncode({
            'code': 200,
            'data': {
              'tableList': [
                {'id': 1, 'number': '3', 'status': 1, 'number_of_diners': 2},
              ],
            },
          }),
          'POST /admin/order/list': jsonEncode({
            'code': 200,
            'data': {'records': <Object?>[], 'total': 0},
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        );

        final overview = await RealTableRepository(client).loadTableOverview();

        expect(overview.tables.length, 1);
        expect(overview.tables.single.number, '3');
        final paths = transport.requests.map((request) => request.uri.path);
        expect(
          paths,
          unorderedEquals([
            '/cashier/table/statusMap',
            '/admin/table/status',
            '/admin/order/list',
          ]),
        );
      },
    );

    test(
      'real table repository keeps a finished takeout whose dispatch was cancelled',
      () async {
        // 外卖配送取消（takeout_dispatch_status=cancelled）不等于订单取消：
        // 订单已结账、已完成，应照常进入外卖页签而非被过滤。
        final transport = FakeHttpTransport({
          'GET /admin/table/status': jsonEncode({
            'code': 200,
            'data': {'tableList': []},
          }),
          'POST /admin/order/list': jsonEncode({
            'code': 200,
            'data': {
              'records': [
                {
                  'id': 13629,
                  'receiving_status': 'off_order',
                  'order_type': '外卖',
                  'transac_status': 'success',
                  'takeout_dispatch_status': 'cancelled',
                },
              ],
            },
          }),
        });
        final client = AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        );

        final overview = await RealTableRepository(client).loadTableOverview();

        expect(overview.takeoutOrders.length, 1);
        expect(
          overview.takeoutOrders.single.status,
          FulfillmentStatus.completed,
        );
        expect(overview.takeoutOrders.single.dispatchStatus, 'cancelled');
      },
    );

    test('admin table status maps colors from backend numeric status', () {
      final empty = DiningTable.fromJson({
        'number': '1',
        'status': 0,
        'order_no': 'STALE_ORDER_NO',
      });
      final pending = DiningTable.fromJson({'number': '2', 'status': 1});
      final settled = DiningTable.fromJson({'number': '3', 'status': 2});

      expect(empty.status, TableStatus.empty);
      expect(pending.status, TableStatus.pending);
      expect(settled.status, TableStatus.settled);
      expect(
        DiningTable.fromJson({
          'status': 2,
          'amount': '0.00',
        }).canClearAfterCheckout,
        isTrue,
      );
      expect(
        DiningTable.fromJson({'status': 2}).canClearAfterCheckout,
        isFalse,
      );
      expect(
        DiningTable.fromJson({'status': 2, 'amount': 12}).canClearAfterCheckout,
        isFalse,
      );
    });

    test(
      'occupied duration is calculated from open_time only for occupied tables',
      () {
        final pending = DiningTable.fromJson({
          'number': '2',
          'status': 1,
          'open_time': '2026-07-09 10:15:00',
        });
        final empty = DiningTable.fromJson({
          'number': '1',
          'status': 0,
          'open_time': '2026-07-09 10:15:00',
        });

        expect(
          pending.occupiedDuration(DateTime(2026, 7, 9, 12)),
          const Duration(hours: 1, minutes: 45),
        );
        expect(empty.occupiedDuration(DateTime(2026, 7, 9, 12)), isNull);
      },
    );
  });

  group('P6 dine-in point of sale contracts', () {
    test(
      'dish specifications create distinct cart lines and stable totals',
      () {
        final dish = PosDish.fromJson({
          'id': 7,
          'name': '油边王',
          'typeId': 3,
          'unitprice': 15,
          'unit': '份',
          'stock': 12,
          'onsale': true,
          'sold_out': 0,
          'specification': '{"辣度":["微辣","不辣"]}',
        });

        expect(dish.specGroups.single.label, '辣度');
        expect(dish.specGroups.single.options, ['微辣', '不辣']);

        var cart = const PosCart();
        cart = cart.add(dish, selections: const {'辣度': '微辣'});
        cart = cart.add(dish, selections: const {'辣度': '微辣'});
        cart = cart.add(dish, selections: const {'辣度': '不辣'});

        expect(cart.lines, hasLength(2));
        expect(cart.lines.first.quantity, 2);
        expect(cart.lines.last.quantity, 1);
        expect(cart.total, 45);
        expect(cart.packagingFee, 1);
        expect(cart.totalWithPackaging, 46);
        expect(cart.lines.first.requestBody()['selectedSpicy'], '{"辣度":"微辣"}');
        expect(cart.lines.first.requestBody()['dish_id'], 7);
      },
    );

    test('order membership is derived from the bound phone field', () {
      final bound = PosOrder.fromJson({
        'id': 1,
        'order_no': 'ORD20260723014058928',
        'member_phone': '13800000000',
      });
      final unbound = PosOrder.fromJson({
        'id': 2,
        'order_no': 'ORD20260723014058929',
      });

      expect(bound.memberPhone, '13800000000');
      expect(bound.hasRegisteredMember, isTrue);
      expect(unbound.hasRegisteredMember, isFalse);
      expect(
        PosOrder.fromJson({'phone': '13800000000'}).hasRegisteredMember,
        isFalse,
      );
    });

    test('order detail lines retain the dish unit for quantity actions', () {
      final order = PosOrder.fromJson({
        'id': 1,
        'order_no': 'ORD-UNIT',
        'goods_list': [
          {
            'id': 11,
            'name': '油边王',
            'quantity': 2,
            'total_price': 30,
            'unit': '串',
          },
        ],
      });

      expect(order.lines.single.unit, '串');
    });

    test('pickup order uses cashier quick order with packing type', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/quickOrder': jsonEncode({
          'code': 200,
          'data': {
            'order_no': 'ORD20260723014058928',
            'id': 99,
            'accepted': true,
            'fulfillment_status': 'ready',
            'cloud_acceptance_status': 'mis_order',
            'order_details': [
              {
                'detail_id': 501,
                'dish_id': 7,
                'name': '油边王',
                'quantity': 1,
                'remaining_quantity': 1,
                'unit': '份',
                'client_line_id': 'line-1',
              },
            ],
          },
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );
      final dish = PosDish.fromJson({
        'id': 7,
        'name': '油边王',
        'typeId': 3,
        'unitprice': 15,
        'unit': '份',
      });
      final cart = const PosCart().add(dish);

      final result = await repository.submitPickupOrder(
        remark: '前台自提',
        lines: cart.lines,
        clientRequestId: 'pickup-action-1',
      );

      final body =
          jsonDecode(transport.requests.single.body!) as Map<String, Object?>;
      expect(result.orderNo, 'ORD20260723014058928');
      expect(body['tableNumber'], '打包');
      expect(body['dineInOrTakeOut'], '打包');
      expect(body['number_of_diners'], 1);
      expect(body['remark'], '前台自提');
      expect(
        (body['goods_list'] as List).single,
        containsPair('client_line_id', 'line-1'),
      );
      expect(result.accepted, isTrue);
      expect(result.fulfillmentStatus, 'ready');
      expect(result.orderDetails.single.detailId, 501);
      expect(
        transport.requests.single.headers['X-Client-Request-Id'],
        'pickup-action-1',
      );
    });

    test(
      'quick order rejects zero-priced lines before creating an order',
      () async {
        final transport = FakeHttpTransport(const {});
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final zeroPriceDish = PosDish.fromJson({
          'id': 7,
          'name': '价格异常菜品',
          'typeId': 3,
          'unitprice': 0,
          'unit': '份',
        });

        await expectLater(
          repository.submitOrder(
            tableNumber: '40',
            diners: 2,
            remark: '',
            lines: const PosCart().add(zeroPriceDish).lines,
          ),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('价格异常'),
            ),
          ),
        );
        expect(transport.requests, isEmpty);
      },
    );

    test(
      'refund dish sends a client request id for server idempotency',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/order/refundDish': jsonEncode({'code': 0}),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );

        await repository.refundDish(
          orderNo: 'ORD-REFUND-1',
          detailId: 31,
          quantity: 1,
          account: 'M1001',
          password: 'manager-password',
        );

        final request = transport.requests.single;
        expect(request.uri.path, '/cashier/order/refundDish');
        expect(
          request.headers['X-Client-Request-Id'],
          matches(RegExp(r'^cashier-refund-dish-')),
        );
      },
    );

    test('refund dish forwards stock_action and reason per v1.2.203', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/refundDish': jsonEncode({'code': 0}),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );

      await repository.refundDish(
        orderNo: 'ORD-REFUND-2',
        detailId: 32,
        quantity: 2,
        stockAction: PosRefundStockAction.outOfStock,
        reason: '食材缺货',
        account: 'M1001',
        password: 'manager-password',
      );

      final body =
          jsonDecode(transport.requests.single.body!) as Map<String, Object?>;
      expect(body['stock_action'], 'OUT_OF_STOCK');
      expect(body['reason'], '食材缺货');

      // 不选动作时不下发 stock_action，由服务端默认 RESTORE
      await repository.refundDish(
        orderNo: 'ORD-REFUND-3',
        detailId: 33,
        quantity: 1,
        reason: '  ',
        account: 'M1001',
        password: 'manager-password',
      );
      final fallbackBody =
          jsonDecode(transport.requests.last.body!) as Map<String, Object?>;
      expect(fallbackBody.containsKey('stock_action'), isFalse);
      expect(fallbackBody.containsKey('reason'), isFalse);
    });

    test(
      'quick order does not enter local-ready state before cloud commit',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/order/quickOrder': jsonEncode({
            'code': 0,
            'data': {
              'order_no': 'ORD-NOT-READY',
              'id': 100,
              'accepted': true,
              'fulfillment_status': 'processing',
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final dish = PosDish.fromJson({
          'id': 7,
          'name': '油边王',
          'typeId': 3,
          'unitprice': 15,
          'unit': '份',
        });

        await expectLater(
          repository.submitOrder(
            tableNumber: '40',
            diners: 2,
            remark: '',
            lines: const PosCart().add(dish).lines,
          ),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('尚未完成云端事务'),
            ),
          ),
        );
      },
    );

    test('loads a formal cloud snapshot for local KDS rebuild', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/orders/99/details': jsonEncode({
          'code': 0,
          'data': {
            'order': {
              'id': 99,
              'order_no': 'ORD99',
              'order_receiving': 'mis_order',
            },
            'lines': [
              {
                'detail_id': 501,
                'dish_id': 7,
                'name': '油边王',
                'quantity': 2,
                'refunded_quantity': 1,
                'remaining_quantity': 1,
                'unit': '份',
                'client_line_id': 'line-1',
              },
            ],
          },
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );

      final result = await repository.loadOrderForLocalKds(99);

      expect(result.orderNo, 'ORD99');
      expect(result.orderDetails.single.detailId, 501);
      expect(result.orderDetails.single.remainingQuantity, 1);
      expect(transport.requests.single.method, 'GET');
      expect(transport.requests.single.headers['X-Shop-Id'], '2');
    });

    test(
      'quick order rejects a success response without a valid order',
      () async {
        final transport = FakeHttpTransport({
          'POST /cashier/order/quickOrder': jsonEncode({
            'code': 200,
            'data': {},
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final dish = PosDish.fromJson({
          'id': 7,
          'name': '油边王',
          'typeId': 3,
          'unitprice': 15,
          'unit': '份',
        });

        await expectLater(
          repository.submitOrder(
            tableNumber: '40',
            diners: 2,
            remark: '',
            lines: const PosCart().add(dish).lines,
          ),
          throwsA(
            isA<ApiException>().having(
              (error) => error.message,
              'message',
              contains('未返回有效订单'),
            ),
          ),
        );
      },
    );

    test(
      'cashier workspace enriches menu dishes with combo definitions',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/category/listAll': jsonEncode({
            'code': 0,
            'data': {
              'categoryList': [
                {'id': 3, 'label': '套餐', 'cid': 'combo', 'sorting': 1},
              ],
            },
          }),
          'POST /admin/dish/list': jsonEncode({
            'code': 0,
            'data': {
              'dishList': [
                {
                  'id': 20,
                  'name': '双人套餐',
                  'typeId': 3,
                  'unitprice': 58,
                  'unit': '套',
                },
              ],
            },
          }),
          'GET /dish/listAll': jsonEncode({
            'code': 0,
            'data': {
              'allDish': [
                {
                  'id': 3,
                  'label': '套餐',
                  'cid': 'combo',
                  'dishList': [
                    {
                      'id': 20,
                      'name': '双人套餐',
                      'typeId': 3,
                      'unitprice': 58,
                      'comboDefinition': {
                        'comboId': 9,
                        'dishId': 20,
                        'comboType': 'fixed',
                        'status': 1,
                        'fixedItems': [
                          {'componentDishId': 7, 'qtyPerCombo': 2},
                        ],
                        'groups': [],
                      },
                    },
                  ],
                },
              ],
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );

        final workspace = await repository.loadWorkspace(
          DiningTable.fromJson({'id': 120, 'number': '40', 'status': 0}),
        );

        expect(workspace.dishes.single.comboDefinition?.comboId, 9);
        expect(
          transport.requests.map((request) => request.uri.path),
          contains('/dish/listAll'),
        );
      },
    );

    test(
      'real pos repository loads workspace and submits cashier quick order',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/category/listAll': jsonEncode({
            'code': 200,
            'data': {
              'categoryList': [
                {'id': 3, 'label': '招牌菜品', 'cid': 'signature', 'sorting': 1},
              ],
            },
          }),
          'POST /admin/dish/list': jsonEncode({
            'code': 200,
            'data': {
              'dishList': [
                {
                  'id': 7,
                  'name': '油边王',
                  'typeId': 3,
                  'unitprice': 15,
                  'unit': '份',
                  'stock': 12,
                  'onsale': true,
                  'sold_out': 0,
                },
              ],
            },
          }),
          'GET /config/payment-capabilities': jsonEncode({
            'code': 0,
            'data': {
              'clients': {
                'cashier': {
                  'enabled': true,
                  'channelStates': {
                    'wechat': {
                      'enabled': false,
                      'available': false,
                      'hint': '商户未配置',
                    },
                    'alipay': {
                      'enabled': false,
                      'available': false,
                      'hint': '商户未配置',
                    },
                    'wechat_qr': {
                      'enabled': true,
                      'available': true,
                      'hint': '',
                    },
                    'alipay_qr': {
                      'enabled': false,
                      'available': true,
                      'hint': '',
                    },
                    'balance': {
                      'enabled': false,
                      'available': true,
                      'hint': '',
                    },
                    'combined': {
                      'enabled': false,
                      'available': false,
                      'hint': '需至少两个基础渠道生效',
                    },
                  },
                },
              },
            },
          }),
          'POST /cashier/order/quickOrder': jsonEncode({
            'code': 200,
            'data': {
              'order_no': 'ORD40',
              'id': 99,
              'accepted': true,
              'fulfillment_status': 'ready',
              'cloud_acceptance_status': 'mis_order',
              'order_details': [
                {
                  'detail_id': 501,
                  'dish_id': 7,
                  'name': '油边王',
                  'quantity': 1,
                  'remaining_quantity': 1,
                  'unit': '份',
                  'client_line_id': 'line-1',
                },
              ],
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final table = DiningTable.fromJson({
          'id': 120,
          'number': '40',
          'status': 0,
        });

        final workspace = await repository.loadWorkspace(table);
        final cart = const PosCart().add(workspace.dishes.single);
        final result = await repository.submitOrder(
          tableNumber: '40',
          diners: 4,
          remark: '靠窗',
          lines: cart.lines,
        );

        expect(workspace.categories.single.name, '招牌菜品');
        expect(workspace.dishes.single.stockLabel, '剩余：12');
        expect(workspace.paymentMethods.map((method) => method.code), [
          'cash',
          'offline_wechat_qr',
          'receivable',
        ]);
        expect(workspace.paymentConfigurationAvailable, isTrue);
        expect(workspace.currentOrder, isNull);
        expect(result.orderNo, 'ORD40');
        final request = transport.requests.singleWhere(
          (item) => item.uri.path == '/cashier/order/quickOrder',
        );
        final body = jsonDecode(request.body!) as Map<String, Object?>;
        expect(body['tableNumber'], '40');
        expect(body['dineInOrTakeOut'], '堂食');
        expect(body['number_of_diners'], 4);
        expect(body['remark'], '靠窗');
        expect((body['goods_list'] as List).single, containsPair('mId', 7));
        expect((body['goods_list'] as List).single, containsPair('dish_id', 7));
        expect(
          (body['goods_list'] as List).single,
          containsPair('client_line_id', 'line-1'),
        );
        expect(request.headers['X-Shop-Id'], '2');
        expect(
          request.headers['X-Client-Request-Id'],
          matches(RegExp(r'^cashier-quick-order-')),
        );
        expect(
          transport.requests.map((item) => item.uri.path),
          isNot(contains('/admin/table/status')),
        );
      },
    );

    test(
      'workspace keeps only categories used by current shop dishes',
      () async {
        // /admin/category/listAll 为全局类目主数据（全表返回，含其他门店/空分类），
        // 收银台必须只展示本店菜品实际使用的分类，避免跨店分类串台。
        final transport = FakeHttpTransport({
          'GET /admin/category/listAll': jsonEncode({
            'code': 200,
            'data': {
              'categoryList': [
                {'id': 1, 'label': '其他门店分类', 'cid': 'other_shop', 'sorting': 0},
                {'id': 2, 'label': '招牌菜品', 'cid': 'signature', 'sorting': 1},
                {'id': 3, 'label': '空分类', 'cid': 'empty_cat', 'sorting': 2},
              ],
            },
          }),
          'POST /admin/dish/list': jsonEncode({
            'code': 200,
            'data': {
              'dishList': [
                {
                  'id': 7,
                  'name': '油边王',
                  'typeId': 2,
                  'unitprice': 15,
                  'unit': '份',
                  'stock': 12,
                  'onsale': true,
                  'sold_out': 0,
                },
              ],
            },
          }),
          // C 端菜单接口 404（_bestEffort 兜底为空），不额外提供分类/菜品。
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );

        final workspace = await repository.loadWorkspace(
          DiningTable.fromJson({'id': 120, 'number': '40', 'status': 0}),
        );

        expect(workspace.categories.map((category) => category.id), [2]);
        expect(workspace.categories.single.name, '招牌菜品');
        expect(workspace.categories.single.code, 'signature');
        expect(workspace.dishes.single.categoryId, 2);
      },
    );

    test(
      'occupied table loads detail and clears through cashier endpoint',
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
                {'id': 120, 'number': '40', 'status': 2},
              ],
              'orderList': [
                {'id': 99, 'order_no': 'ORD40', 'sett_amount': 60},
              ],
            },
          }),
          'POST /cashier/table/clear': jsonEncode({'code': 200, 'data': {}}),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final table = DiningTable.fromJson({
          'id': 120,
          'number': '40',
          'status': 2,
        });

        final workspace = await repository.loadWorkspace(table);
        await repository.clearTable('40');

        expect(workspace.table.id, 120);
        expect(workspace.currentOrder?.orderNo, 'ORD40');
        final detailRequest = transport.requests.singleWhere(
          (item) => item.uri.path == '/admin/table/status',
        );
        expect(detailRequest.uri.queryParameters['number'], '40');
        final clearRequest = transport.requests.singleWhere(
          (item) => item.uri.path == '/cashier/table/clear',
        );
        expect(clearRequest.method, 'POST');
        final clearBody =
            jsonDecode(clearRequest.body!) as Map<String, Object?>;
        expect(clearBody['tableNumber'], '40');
        expect(
          clearBody['idempotencyKey'],
          clearRequest.headers['Idempotency-Key'],
        );
      },
    );

    test(
      'occupied table resolves bound member phone from the order openid',
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
                {
                  'id': 99,
                  'order_no': 'ORD40',
                  'openid': 'member-openid',
                  'sett_amount': 60,
                },
              ],
            },
          }),
          'POST /admin/order/getUserInfo': jsonEncode({
            'code': 200,
            'data': {
              'user': [
                {'id': 7, 'openid': 'member-openid', 'phone': '13800000000'},
              ],
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final table = DiningTable.fromJson({
          'id': 120,
          'number': '40',
          'status': 1,
        });

        final workspace = await repository.loadWorkspace(table);

        expect(workspace.currentOrder?.memberPhone, '13800000000');
        expect(workspace.currentOrder?.hasRegisteredMember, isTrue);
        final request = transport.requests.singleWhere(
          (item) => item.uri.path == '/admin/order/getUserInfo',
        );
        expect(jsonDecode(request.body!), {
          'pageNum': 1,
          'pageSize': 1,
          'query': 'member-openid',
        });
      },
    );

    test(
      'real pos repository derives categories from admin dish list data',
      () async {
        final transport = FakeHttpTransport({
          'GET /admin/category/listAll': jsonEncode({
            'code': 500,
            'msg': 'category endpoint unavailable',
          }),
          'POST /admin/dish/list': jsonEncode({
            'code': 200,
            'data': {
              'categoryList': [
                {'id': 3, 'label': '招牌菜品', 'cid': 'signature', 'sorting': 1},
              ],
              'dishList': [
                {
                  'id': 7,
                  'name': '油边王',
                  'type': {
                    'id': 3,
                    'label': '招牌菜品',
                    'cid': 'signature',
                    'sorting': 1,
                  },
                  'unitprice': 15,
                  'unit': '份',
                  'onsale': true,
                },
              ],
            },
          }),
          'GET /config/payment-capabilities': jsonEncode({
            'code': 0,
            'data': {
              'clients': {
                'cashier': {'enabled': false, 'channelStates': {}},
              },
            },
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );
        final table = DiningTable.fromJson({
          'id': 120,
          'number': '40',
          'status': 0,
        });

        final workspace = await repository.loadWorkspace(table);

        expect(workspace.categories.single.id, 3);
        expect(workspace.categories.single.code, 'signature');
        expect(workspace.dishes.single.categoryId, 3);
        expect(workspace.dishes.single.categoryCode, 'signature');
      },
    );

    test(
      'payment methods fail closed when configuration cannot be loaded',
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
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );

        final workspace = await repository.loadWorkspace(
          DiningTable.fromJson({'id': 120, 'number': '40', 'status': 0}),
        );

        expect(workspace.paymentMethods, isEmpty);
        expect(workspace.paymentConfigurationAvailable, isFalse);
        expect(
          transport.requests.map((request) => request.uri.path),
          contains('/config/payment-capabilities'),
        );
      },
    );

    test(
      'fulfillment checkout workspace uses POS payment capabilities',
      () async {
        final transport = FakeHttpTransport({
          'GET /config/payment-capabilities': jsonEncode({
            'code': 0,
            'data': {
              'clients': {
                'cashier': {
                  'enabled': true,
                  'channelStates': {
                    'wechat_qr': {
                      'enabled': true,
                      'available': true,
                      'hint': '',
                    },
                    'alipay_qr': {
                      'enabled': true,
                      'available': true,
                      'hint': '',
                    },
                    'balance': {'enabled': true, 'available': true, 'hint': ''},
                    'combined': {
                      'enabled': true,
                      'available': true,
                      'hint': '',
                    },
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
            token: 't',
            shopId: 2,
          ),
        );
        const order = FulfillmentOrder(
          id: 77,
          type: FulfillmentType.takeout,
          status: FulfillmentStatus.pendingPayment,
          pickupCode: 'B2077',
          orderNo: 'ORD77',
          amount: 98,
          kdsOrderStatus: '30',
        );

        final workspace = await repository.loadFulfillmentCheckoutWorkspace(
          const FulfillmentOrderDetail(
            order: order,
            lines: [
              FulfillmentOrderLine(
                name: '油边王',
                quantity: 2,
                unitPrice: 49,
                totalPrice: 98,
              ),
            ],
          ),
        );

        expect(workspace.currentOrder?.orderNo, 'ORD77');
        expect(workspace.currentOrder?.kdsOrderStatus, '30');
        expect(workspace.currentOrder?.lines.single.name, '油边王');
        expect(
          workspace.paymentMethods.map((method) => method.kind),
          containsAll([
            PosPaymentChannelKind.cash,
            PosPaymentChannelKind.wechat,
            PosPaymentChannelKind.alipay,
            PosPaymentChannelKind.combined,
          ]),
        );
        expect(
          transport.requests.single.uri.queryParameters['order_no'],
          'ORD77',
        );
      },
    );

    test('table actions use cashier endpoints and idempotency keys', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/table/open': jsonEncode({'code': 200, 'data': {}}),
        'POST /cashier/table/merge': jsonEncode({'code': 200, 'data': {}}),
        'POST /cashier/table/transfer': jsonEncode({'code': 200, 'data': {}}),
        'POST /cashier/table/clear': jsonEncode({'code': 200, 'data': {}}),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );

      await repository.openTable('40');
      await repository.mergeTables(
        sourceTableNumber: '40',
        targetTableNumber: '41',
      );
      await repository.transferTable(orderNo: 'ORD40', targetTableNumber: '42');
      await repository.clearTable('40');

      final openRequest = transport.requests.singleWhere(
        (item) => item.uri.path == '/cashier/table/open',
      );
      final mergeRequest = transport.requests.singleWhere(
        (item) => item.uri.path == '/cashier/table/merge',
      );
      final transferRequest = transport.requests.singleWhere(
        (item) => item.uri.path == '/cashier/table/transfer',
      );
      final clearRequest = transport.requests.singleWhere(
        (item) => item.uri.path == '/cashier/table/clear',
      );
      final openBody = jsonDecode(openRequest.body!) as Map<String, Object?>;
      final mergeBody = jsonDecode(mergeRequest.body!) as Map<String, Object?>;
      final transferBody =
          jsonDecode(transferRequest.body!) as Map<String, Object?>;
      final clearBody = jsonDecode(clearRequest.body!) as Map<String, Object?>;
      expect(openBody['tableNumber'], '40');
      expect(mergeBody['sourceTableNumber'], '40');
      expect(mergeBody['targetTableNumber'], '41');
      expect(transferBody['orderNo'], 'ORD40');
      expect(transferBody['targetTableNumber'], '42');
      expect(clearBody['tableNumber'], '40');
      for (final request in [
        openRequest,
        mergeRequest,
        transferRequest,
        clearRequest,
      ]) {
        final body = jsonDecode(request.body!) as Map<String, Object?>;
        final key = request.headers['Idempotency-Key'];
        expect(key, isNotEmpty);
        expect(body['idempotencyKey'], key);
      }
      expect({
        openRequest.headers['Idempotency-Key'],
        mergeRequest.headers['Idempotency-Key'],
        transferRequest.headers['Idempotency-Key'],
        clearRequest.headers['Idempotency-Key'],
      }, hasLength(4));
      expect(
        transport.requests.map((item) => item.uri.path),
        isNot(contains('/admin/table/out')),
      );
    });

    test('pos discount and combined checkout follow OpenAPI fields', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/discount': jsonEncode({'code': 200, 'data': {}}),
        'POST /cashier/order/checkout': jsonEncode({'code': 200, 'data': {}}),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );

      await repository.discountOrder(
        orderNo: 'ORD40',
        discountAmount: 20,
        reason: '88折 · 熟客',
        account: 'M1001',
        password: 'manager-password',
      );
      await repository.checkoutCash(
        orderNo: 'ORD40',
        paymentMethod: 'cash',
        settlement: PosCashSettlement.fromMinorUnits(
          cashReceivedMinor: 7000,
          cashTenderMinor: 10000,
          changeChannel: PosChangeChannel.wechat,
        ),
      );

      final discountBody =
          jsonDecode(transport.requests.first.body!) as Map<String, Object?>;
      expect(discountBody, {
        'orderNo': 'ORD40',
        'discountAmount': 20,
        'reason': '88折 · 熟客',
        'authorization': {'account': 'M1001', 'password': 'manager-password'},
      });
      expect(transport.requests.first.uri.path, '/cashier/order/discount');
      expect(transport.requests.first.headers['X-Shop-Id'], '2');
      expect(
        transport.requests.map((request) => request.uri.path),
        isNot(contains('/admin/order/manualDiscount')),
      );
      final checkoutBody =
          jsonDecode(transport.requests.last.body!) as Map<String, Object?>;
      expect(checkoutBody, {
        'order_no': 'ORD40',
        'payment_method': 'cash',
        'cash_amount': 70,
        'checkout_cash_tender': 100,
        'checkout_change_amount': 30,
        'checkout_change_channel': 'wechat',
      });
      expect(transport.requests.last.headers['X-Shop-Id'], '2');
    });

    test(
      'POS offline QR and stored-value debit follow OpenAPI fields',
      () async {
        final transport = FakeHttpTransport({
          'POST /pay/offline-collect/temp-qrcode': jsonEncode({
            'code': 0,
            'qrImageBase64': 'cG5n',
            'jumpUrl': 'https://pay.test/jump?t=1',
            'expiresInSeconds': 180,
            'channel': 'wechat',
            'shopId': 2,
          }),
          'POST /cashier/order/checkout': jsonEncode({
            'code': 0,
            'paidYuan': 80,
            'payment_method': '余额支付',
          }),
        });
        final repository = RealPosRepository(
          AdminApiClient(
            baseUrl: 'http://api.test',
            transport: transport,
            token: 't',
            shopId: 2,
          ),
        );

        final qr = await repository.createOfflineCollectionQr(
          channel: 'wechat',
          orderNo: 'ORD40',
          sessionId: 'collection-session-1',
          amountMinor: 8000,
        );
        await repository.checkoutByBalance(
          orderNo: 'ORD40',
          openid: 'member-openid',
          memberPhone: '13800000000',
        );

        expect(qr.channel, 'wechat');
        expect(qr.shopId, 2);
        expect(qr.qrImageBase64, 'cG5n');
        expect(qr.expiresInSeconds, 180);
        expect(jsonDecode(transport.requests.first.body!), {
          'channel': 'wechat',
          'order_no': 'ORD40',
          'session_id': 'collection-session-1',
          'amount_fen': 8000,
        });
        expect(jsonDecode(transport.requests.last.body!), {
          'order_no': 'ORD40',
          'payment_method': 'online_balance',
          'openid': 'member-openid',
          'member_phone': '13800000000',
        });
        expect(transport.requests.first.headers['X-Shop-Id'], '2');
      },
    );

    test('front ticket (前台小票) uses the unified print dispatch contract', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': jsonEncode({
          'code': 200,
          'data': {
            'total_jobs': 1,
            'dispatched_count': 1,
            'failed_count': 0,
            'summary': '打印成功: 40号桌',
            'order_no': 'ORD40',
            'jobs': [],
          },
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );

      final result = await repository.printFrontTicket(
        orderId: 9,
        orderNo: 'ORD40',
      );

      expect(result.printSuccess, isTrue);
      expect(result.orderNo, 'ORD40');
      expect(result.content, contains('40号桌'));
      expect(transport.requests.single.method, 'POST');
      expect(transport.requests.single.uri.path, '/cashier/print/dispatch');
      expect(jsonDecode(transport.requests.single.body!), {
        'order_id': 9,
        'order_no': 'ORD40',
        'scenario': 'full_order',
        'is_reprint': true,
      });
      expect(transport.requests.single.headers['X-Shop-Id'], '2');
    });

    test('kitchen reprint uses the unified print dispatch contract', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/print/dispatch': jsonEncode({
          'code': 200,
          'msg': '厨房小票补打成功',
          'data': {
            'total_jobs': 1,
            'dispatched_count': 1,
            'failed_count': 0,
            'summary': '厨房小票补打成功',
            'jobs': [],
          },
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );

      await repository.reprintKitchenTicket(orderNo: ' ORD40 ');

      final request = transport.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.path, '/cashier/print/dispatch');
      expect(jsonDecode(request.body!), {
        'order_no': 'ORD40',
        'scenario': 'kitchen',
        'is_reprint': true,
      });
      expect(request.headers['X-Shop-Id'], '2');
    });
  });
}

class _PagedAuthorizedShopsTransport implements HttpTransport {
  final List<RecordedRequest> requests = [];

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    requests.add(
      RecordedRequest(
        method: method,
        uri: uri,
        headers: Map.of(headers),
        body: body,
      ),
    );
    if (method == 'POST' && uri.path == '/adminLogin') {
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 200,
          'data': {'token': 'jwt-token', 'scope': 'HQ'},
        }),
      );
    }
    if (method == 'GET' && uri.path == '/admin/me/permissions') {
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 200,
          'data': {
            'scope': 'HQ',
            'permissions': ['cashier:operate'],
          },
        }),
      );
    }
    if (method == 'GET' && uri.path == '/admin/me/shops') {
      final page = int.tryParse(uri.queryParameters['page'] ?? '') ?? 1;
      final start = (page - 1) * 200;
      final end = (start + 200).clamp(0, 201);
      final list = [
        for (var index = start; index < end; index++)
          {'id': index + 1, 'code': 'S${index + 1}', 'name': '门店 ${index + 1}'},
      ];
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 200,
          'data': {
            'scope': 'HQ',
            'list': list,
            'page': page,
            'pageSize': 200,
            'total': 201,
          },
        }),
      );
    }
    return const HttpResponseData(statusCode: 404, body: 'not found');
  }
}

class _FakePendingRefundStore implements PendingRefundStore {
  final values = <String, PendingRefund>{};

  @override
  Future<void> clear(String orderNo) async => values.remove(orderNo);

  @override
  Future<void> clearIfMatches(String orderNo, String idempotencyKey) async {
    if (values[orderNo]?.idempotencyKey == idempotencyKey) {
      values.remove(orderNo);
    }
  }

  @override
  Future<PendingRefund?> read(String orderNo) async => values[orderNo];

  @override
  Future<void> write(PendingRefund value) async {
    values[value.orderNo] = value;
  }
}

class _LoseFirstRefundResponseTransport implements HttpTransport {
  final requests = <RecordedRequest>[];
  var _loseNextResponse = true;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    requests.add(
      RecordedRequest(
        method: method,
        uri: uri,
        headers: Map.of(headers),
        body: body,
      ),
    );
    if (_loseNextResponse) {
      _loseNextResponse = false;
      throw StateError('response lost after request was sent');
    }
    return HttpResponseData(statusCode: 200, body: jsonEncode({'code': 0}));
  }
}

class _ConflictAfterReplacingStoreTransport implements HttpTransport {
  _ConflictAfterReplacingStoreTransport(this.store);

  final _FakePendingRefundStore store;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    final request = jsonDecode(body!) as Map<String, Object?>;
    await store.write(
      PendingRefund(
        orderNo: request['orderNo']! as String,
        amountMinor: 3000,
        reason: 'other window',
        baselineRefundMinor: 0,
        idempotencyKey: 'other-window-key',
      ),
    );
    return HttpResponseData(
      statusCode: 200,
      body: jsonEncode({'code': 40912, 'msg': 'conflicting refund'}),
    );
  }
}
