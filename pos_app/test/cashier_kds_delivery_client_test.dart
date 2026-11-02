import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_delivery_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  AdminApiClient buildClient(FakeHttpTransport transport) {
    return AdminApiClient(
      baseUrl: 'http://api.test',
      transport: transport,
      token: 't',
      shopId: 3,
    );
  }

  group('cashier kds delivery client authority lease', () {
    test('acquire lease posts ACQUIRE and parses authority identity', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/kds/authority/lease': jsonEncode({
          'code': 0,
          'data': {
            'shopId': 3,
            'deviceCode': 'DEV-1',
            'authorityEpoch': 5,
            'leaseToken': 'LEASE-ABCDEFGHIJKLMNOPQRSTUVWXYZ012345',
            'leaseUntilMs': 1730000000000,
            'renewAfterMs': 10000,
            'snapshotRequired': true,
            'lastAckCursor': 42,
            'headCursor': 128,
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
      );

      final result = await client.acquireLease(clientVersion: 'pos/2.1.9');

      expect(result.authorityEpoch, 5);
      expect(result.leaseToken, 'LEASE-ABCDEFGHIJKLMNOPQRSTUVWXYZ012345');
      expect(result.snapshotRequired, isTrue);
      expect(result.lastAckCursor, 42);
      expect(result.headCursor, 128);
      expect(client.authorityEpoch, 5);
      expect(client.leaseToken, 'LEASE-ABCDEFGHIJKLMNOPQRSTUVWXYZ012345');

      final request = transport.requests.single;
      final body = jsonDecode(request.body!) as Map<String, Object?>;
      expect(body['action'], 'ACQUIRE');
      expect(body['clientVersion'], 'pos/2.1.9');
      expect(request.headers['X-Cashier-Device-Code'], 'DEV-1');
      expect(request.headers['X-Shop-Id'], '3');
      expect(request.headers.containsKey('X-Cashier-Authority-Epoch'), isFalse);
    });

    test('renew lease posts RENEW with epoch and token', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/kds/authority/lease': jsonEncode({
          'code': 0,
          'data': {
            'shopId': 3,
            'deviceCode': 'DEV-1',
            'authorityEpoch': 5,
            'leaseToken': 'LEASE-TOKEN-00000000000000000000000000000000',
            'leaseUntilMs': 1730000001000,
            'renewAfterMs': 10000,
            'snapshotRequired': false,
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
        authorityEpoch: 5,
        leaseToken: 'LEASE-TOKEN-00000000000000000000000000000000',
      );

      final result = await client.renewLease(
        authorityEpoch: 5,
        leaseToken: 'LEASE-TOKEN-00000000000000000000000000000000',
      );

      expect(result.snapshotRequired, isFalse);
      final request = transport.requests.single;
      final body = jsonDecode(request.body!) as Map<String, Object?>;
      expect(body['action'], 'RENEW');
      expect(body['authorityEpoch'], 5);
      expect(body['leaseToken'], 'LEASE-TOKEN-00000000000000000000000000000000');
      expect(request.headers['X-Cashier-Authority-Epoch'], '5');
      expect(request.headers['X-Cashier-Lease-Token'],
          'LEASE-TOKEN-00000000000000000000000000000000');
    });
  });

  group('cashier kds delivery client events', () {
    test('fetch events parses order projection events', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/kds/delivery/events': jsonEncode({
          'code': 0,
          'data': {
            'currentCursor': 128,
            'nextCursor': 129,
            'minAvailableCursor': 0,
            'snapshotRequired': false,
            'events': [
              {
                'eventId': '11111111-2222-3333-4444-555555555555',
                'cursor': 43,
                'shopId': 3,
                'eventType': 'ORDER_READY',
                'orderId': 7,
                'projectionVersion': 3,
                'originChannel': 'CASHIER',
                'occurredAtMs': 1730000000000,
                'changedDetailIds': [91],
                'projection': {
                  'orderId': 7,
                  'orderNo': 'ORD7',
                  'shopId': 3,
                  'projectionVersion': 3,
                  'state': 'READY',
                  'sourceChannel': 'CASHIER',
                  'fulfillmentType': 'DINE_IN',
                  'tableNumber': '12',
                  'createdAtMs': 1730000000000,
                  'lines': [
                    {
                      'detailId': 91,
                      'dishId': 5,
                      'dishName': '油边王',
                      'quantity': 4,
                      'refundedQuantity': 0,
                      'remainingQuantity': 4,
                      'lineStatus': 'NORMAL',
                      'lineType': 'NORMAL',
                      'workflowQueue': 'pending_cook',
                      'rushed': true,
                    },
                  ],
                },
              },
            ],
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
        authorityEpoch: 5,
        leaseToken: 'L',
      );

      final result = await client.fetchEvents(afterCursor: 42);

      expect(result.currentCursor, 128);
      expect(result.nextCursor, 129);
      expect(result.events, hasLength(1));
      final event = result.events.single;
      expect(event.eventType, 'ORDER_READY');
      expect(event.eventId, '11111111-2222-3333-4444-555555555555');
      expect(event.isLineStatusEvent, isFalse);
      final projection = event.projection;
      expect(projection, isNotNull);
      expect(projection!.orderNo, 'ORD7');
      expect(projection.tableNumber, '12');
      expect(projection.lines.single.dishName, '油边王');
      expect(projection.lines.single.rushed, isTrue);
      final request = transport.requests.single;
      expect(request.headers['X-Cashier-Authority-Epoch'], '5');
      expect(request.headers['X-Cashier-Lease-Token'], 'L');
    });

    test('fetch events parses line status increment projection', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/kds/delivery/events': jsonEncode({
          'code': 0,
          'data': {
            'currentCursor': 10,
            'nextCursor': 11,
            'minAvailableCursor': 0,
            'snapshotRequired': false,
            'events': [
              {
                'eventId': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
                'cursor': 10,
                'shopId': 3,
                'eventType': 'ORDER_LINE_STATUS_CHANGED',
                'orderId': 7,
                'projectionVersion': 0,
                'originChannel': 'KDS',
                'occurredAtMs': 1730000000000,
                'projection': {
                  'eventType': 'ORDER_LINE_STATUS_CHANGED',
                  'orderId': 7,
                  'orderNo': 'ORD7',
                  'shopId': 3,
                  'occurredAtMs': 1730000000000,
                  'lines': [
                    {
                      'detailId': 91,
                      'itemStatus': 2,
                      'prepQuantity': 4,
                      'cookedQuantity': 4,
                      'servedQuantity': 2,
                      'rushFlag': 0,
                      'overdueFlag': 1,
                      'addDishFlag': 0,
                      'archived': 0,
                      'updatedAtMs': 1730000000000,
                    },
                  ],
                },
              },
            ],
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
      );

      final result = await client.fetchEvents(afterCursor: 9);

      final event = result.events.single;
      expect(event.isLineStatusEvent, isTrue);
      expect(event.projection, isNull);
      final delta = event.lineStatusProjection;
      expect(delta, isNotNull);
      expect(delta!.orderNo, 'ORD7');
      expect(delta.lines.single.itemStatus, 2);
      expect(delta.lines.single.cookedQuantity, 4);
      expect(delta.lines.single.overdueFlag, 1);
    });
  });

  group('cashier kds delivery client snapshots', () {
    test('bootstrap posts pagination query and parses base cursor', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/kds/delivery/bootstrap': jsonEncode({
          'code': 0,
          'data': {
            'snapshotToken': 'TOK-1',
            'baseCursor': 40,
            'nextPageToken': 'PAGE-2',
            'complete': false,
            'orders': [
              {
                'orderId': 7,
                'orderNo': 'ORD7',
                'shopId': 3,
                'projectionVersion': 1,
                'state': 'READY',
                'sourceChannel': 'CASHIER',
                'fulfillmentType': 'DINE_IN',
                'createdAtMs': 1730000000000,
                'lines': <Object?>[],
              },
            ],
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
      );

      final result = await client.bootstrap();

      expect(result.baseCursor, 40);
      expect(result.snapshotToken, 'TOK-1');
      expect(result.nextPageToken, 'PAGE-2');
      expect(result.complete, isFalse);
      expect(result.orders.single.orderId, 7);
    });

    test('business day orders sends compound cursor and parses next cursor',
        () async {
      final transport = FakeHttpTransport({
        'GET /cashier/kds/delivery/business-day/orders': jsonEncode({
              'code': 0,
              'data': {
                'shopId': 3,
                'businessDay': '2026-10-06',
                'openTime': '16:00',
                'closeTime': '04:00',
                'orders': [
                  {'id': 12, 'orderNo': 'ORD12'},
                ],
                'nextCursor': '2026-10-06T16:05:00:13',
                'complete': false,
              },
            }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
      );

      final result = await client.businessDayOrders(
        cursor: '2026-10-06T16:00:00:12',
      );

      expect(result.businessDay, '2026-10-06');
      expect(result.nextCursor, '2026-10-06T16:05:00:13');
      expect(result.orders, hasLength(1));
    });

    test('order projection resolves path placeholder', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/kds/orders/7/projection': jsonEncode({
          'code': 0,
          'data': {
            'orderId': 7,
            'orderNo': 'ORD7',
            'shopId': 3,
            'projectionVersion': 2,
            'state': 'READY',
            'sourceChannel': 'MINI_PROGRAM',
            'fulfillmentType': 'TAKEOUT',
            'createdAtMs': 1730000000000,
            'lines': <Object?>[],
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
      );

      final result = await client.orderProjection(orderId: 7);

      expect(result.orderId, 7);
      expect(result.sourceChannel, 'MINI_PROGRAM');
      expect(result.fulfillmentType, 'TAKEOUT');
      expect(transport.requests.single.uri.path, '/cashier/kds/orders/7/projection');
    });
  });

  group('cashier kds delivery client ack and status', () {
    test('ack posts through cursor and parses duplicate result', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/kds/delivery/ack': jsonEncode({
          'code': 0,
          'data': {
            'acknowledgedCursor': 128,
            'headCursor': 200,
            'duplicate': true,
            'lag': 72,
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
      );

      final result = await client.ack(
        throughCursor: 128,
        lastEventId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        localCommittedAtMs: 1730000000000,
      );

      expect(result.acknowledgedCursor, 128);
      expect(result.headCursor, 200);
      expect(result.duplicate, isTrue);
      expect(result.lag, 72);
      final request = transport.requests.single;
      final body = jsonDecode(request.body!) as Map<String, Object?>;
      expect(body['throughCursor'], 128);
      expect(body['lastEventId'], 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
      expect(body['localCommittedAtMs'], 1730000000000);
    });

    test('delivery status parses authority online state', () async {
      final transport = FakeHttpTransport({
        'GET /cashier/kds/delivery/status': jsonEncode({
          'code': 0,
          'data': {
            'shopId': 3,
            'headCursor': 500,
            'acknowledgedCursor': 400,
            'minAvailableCursor': 0,
            'lag': 100,
            'authorityOnline': true,
            'authorityDeviceCode': 'DEV-1',
            'authorityEpoch': 5,
            'leaseUntilMs': 1730000000000,
            'snapshotRequired': false,
          },
        }),
      });
      final client = CashierKdsDeliveryClient(
        client: buildClient(transport),
        deviceCode: 'DEV-1',
      );

      final result = await client.deliveryStatus();

      expect(result.headCursor, 500);
      expect(result.acknowledgedCursor, 400);
      expect(result.lag, 100);
      expect(result.authorityOnline, isTrue);
      expect(result.authorityDeviceCode, 'DEV-1');
    });
  });
}
