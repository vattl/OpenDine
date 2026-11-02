import 'dart:async';
import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/features/tables/data/real_table_repository.dart';
import 'package:admin_panel_flutter/src/features/tables/data/table_repository.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/takeout_dispatch_alert.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/takeout_delivery.dart';
import 'package:admin_panel_flutter/src/features/tables/presentation/amap_tile_map.dart';
import 'package:admin_panel_flutter/src/features/tables/presentation/fulfillment_order_detail_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  test('parses only valid takeout dispatch WebSocket events', () {
    final alert = TakeoutDispatchAlert.tryParse({
      'type': 'takeout_dispatch_alert',
      'alertType': 'order_missing',
      'shopId': 2,
      'orderId': 21,
      'orderNo': 'ORD21',
      'message': '配送订单已删除',
    });

    expect(alert?.isOrderMissing, isTrue);
    expect(alert?.shopId, 2);
    expect(alert?.orderId, 21);
    final changed = TakeoutDispatchAlert.tryParse({
      'type': 'takeout_dispatch_changed',
      'shopId': 2,
      'orderId': 21,
      'orderNo': 'ORD21',
      'zsqPhase': 'TO_SHOP',
    });
    expect(changed?.isDispatchChanged, isTrue);
    expect(TakeoutDispatchAlert.tryParse({'type': 'business_changed'}), isNull);
  });

  test('parses the ZSQ delivery snapshot and rider tracking contract', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'delivering',
        'zsq_dispatch_status': 'dispatched',
        'zsq_phase': 'TO_USER',
        'zsq_open_order_id': 901,
        'receiver_name': '张三',
        'receiver_phone': '13800138000',
        'address_full': '北京市朝阳区测试路 1 号',
        'lat': 39.91,
        'lng': 116.41,
      },
      'tracking': {
        'phase': 'TO_USER',
        'deliverySendStatusDesc': '骑手正在赶往用户',
        'rider': {
          'name': '李师傅',
          'phone': '13900139000',
          'lat': 39.905,
          'lng': 116.405,
        },
        'shop': {'lat': 39.9, 'lng': 116.4, 'address': '测试门店'},
        'user': {'lat': 39.91, 'lng': 116.41, 'address': '测试路 1 号'},
        'platformEta': {'durationText': '8分钟', 'distanceText': '2.1公里'},
        'computedEta': {'toUserMinutes': 9, 'riderToUserKm': 2.2},
      },
    });

    expect(snapshot.delivery.zsqOpenOrderId, 901);
    expect(snapshot.delivery.receiverName, '张三');
    expect(snapshot.tracking?.rider?.name, '李师傅');
    expect(snapshot.tracking?.rider?.position?.latitude, 39.905);
    expect(snapshot.tracking?.user?.longitude, 116.41);
    expect(snapshot.tracking?.etaText, '8分钟 · 2.1公里');
    expect(snapshot.receivingStatusLabel, '骑手配送中');
    expect(snapshot.canCancel, isTrue);
  });

  test('effective state overrides stale cancellation from an older batch', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'cancelled',
        'zsq_dispatch_status': 'cancelled',
        'zsq_phase': 'CANCELLED',
        'zsq_open_order_id': 54384514,
        'zsq_rider_lat': 39.8,
        'zsq_rider_lng': 116.3,
      },
      'tracking': {
        'phase': 'CANCELLED',
        'deliverySendStatus': 60,
        'deliverySendStatusDesc': '超时未接单',
        'effectiveState': {
          'sendStatus': 30,
          'statusDesc': '取货中',
          'phase': 'TO_SHOP',
          'source': 'ORDER_LOG',
          'effectiveLogId': 842232935031685,
          'parentOrderNo': 'JH842230763496325',
          'thirdPartyOrderNo': '3749203565953626113',
          'updatedAt': '2026-08-26 23:54:37',
        },
        'rider': {'lat': 39.9, 'lng': 116.4},
        'trajectoryState': {
          'orderStatus': '异常单',
          'deliveryStatus': '已取消',
          'cancelReason': '旧批次超时未接单',
        },
      },
    });

    expect(snapshot.effectivePhase, 'TO_SHOP');
    expect(snapshot.tracking?.effectiveState.sendStatus, 30);
    expect(snapshot.tracking?.effectiveState.source, 'ORDER_LOG');
    expect(snapshot.tracking?.effectiveState.effectiveLogId, 842232935031685);
    expect(snapshot.tracking?.effectiveStatusDescription, '取货中');
    expect(snapshot.receivingStatusLabel, '骑手取货中');
    expect(snapshot.tracking?.isCancelled, isFalse);
    expect(snapshot.currentCancelReason, isEmpty);
    expect(snapshot.isActive, isTrue);
    expect(snapshot.canCancel, isTrue);
    expect(snapshot.canRedispatch, isFalse);
    expect(snapshot.tracking?.activeRiderPosition, isNotNull);
  });

  test('waiting for a new rider hides cached rider coordinates', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'cancelled',
        'zsq_dispatch_status': 'cancelled',
        'zsq_phase': 'CANCELLED',
        'zsq_open_order_id': 901,
        'zsq_rider_lat': 39.8,
        'zsq_rider_lng': 116.3,
      },
      'tracking': {
        'effectiveState': {
          'sendStatus': 20,
          'statusDesc': '等待骑手接单',
          'phase': 'WAITING_RIDER',
          'source': 'ORDER_DETAIL',
        },
        'rider': {'lat': 39.9, 'lng': 116.4},
      },
    });

    expect(snapshot.receivingStatusLabel, '等待骑手接单');
    expect(snapshot.tracking?.activeRiderPosition, isNull);
    expect(snapshot.isActive, isTrue);
    expect(snapshot.canRedispatch, isFalse);
  });

  test('effective terminal states control actions and polling', () {
    final delivered = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'delivering',
        'zsq_dispatch_status': 'dispatched',
        'zsq_phase': 'TO_USER',
        'zsq_open_order_id': 901,
      },
      'tracking': {
        'effectiveState': {
          'sendStatus': 50,
          'statusDesc': '已完成',
          'phase': 'DELIVERED',
          'source': 'ORDER_LOG',
        },
      },
    });
    final cancelled = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'delivering',
        'zsq_dispatch_status': 'dispatched',
        'zsq_phase': 'TO_USER',
        'zsq_open_order_id': 902,
      },
      'tracking': {
        'effectiveState': {
          'sendStatus': 60,
          'statusDesc': '当前配送已取消',
          'phase': 'CANCELLED',
          'source': 'ORDER_LOG',
        },
        'trajectoryState': {'cancelReason': '当前批次无人接单'},
      },
    });

    expect(delivered.receivingStatusLabel, '配送已完成');
    expect(delivered.isCompleted, isTrue);
    expect(delivered.canRedispatch, isTrue);
    expect(delivered.trackingRefreshInterval, isNull);
    expect(cancelled.receivingStatusLabel, '配送已取消');
    expect(cancelled.currentCancelReason, '当前批次无人接单');
    expect(cancelled.canRedispatch, isTrue);
    expect(cancelled.trackingRefreshInterval, isNull);
  });

  test(
    'unknown effective state refreshes slowly without trusting local cancel',
    () {
      final snapshot = TakeoutDeliverySnapshot.fromJson({
        'delivery': {
          'dispatch_status': 'cancelled',
          'zsq_dispatch_status': 'cancelled',
          'zsq_phase': 'CANCELLED',
          'zsq_open_order_id': 901,
        },
        'tracking': {
          'effectiveState': {'phase': 'UNKNOWN', 'source': 'ORDER_DETAIL'},
        },
      });

      expect(snapshot.receivingStatusLabel, '状态同步中');
      expect(snapshot.isActive, isTrue);
      expect(snapshot.canRedispatch, isFalse);
      expect(snapshot.trackingRefreshInterval, const Duration(seconds: 60));
    },
  );

  test('balance failure is retryable but never cancellable', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'dispatch_failed',
        'zsq_dispatch_status': 'failed',
        'zsq_phase': 'WAITING_RIDER',
        'zsq_open_order_id': 901,
        'zsq_last_error': '余额不足，请充值',
      },
      'tracking': {
        'effectiveState': {'phase': 'WAITING_RIDER', 'source': 'ORDER_DETAIL'},
      },
    });

    expect(snapshot.canCancel, isFalse);
    expect(snapshot.canRetryDispatch, isTrue);
  });

  test('uses independent trajectory state to detect a cancelled delivery', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'delivering',
        'zsq_dispatch_status': 'dispatched',
        'zsq_phase': 'TO_SHOP',
      },
      'tracking': {
        'phase': 'TO_SHOP',
        'deliverySendStatus': 60,
        'deliverySendStatusDesc': '配送单已取消',
        'coordinateType': 'gcj02',
        'rider': {
          'name': '李师傅',
          'phone': '13900139000',
          'lat': 39.905,
          'lng': 116.405,
          'locationLogId': 108,
          'locationUpdatedAt': '2026-08-25 18:30:00',
        },
        'trajectoryState': {
          'callbackStatus': '取消配送单',
          'orderStatus': '异常单',
          'previousOrderStatus': '配送中',
          'deliveryStatus': '已取消',
          'cancelReason': '顾客临时取消',
          'latestStatusLogId': 109,
          'statusUpdatedAt': '2026-08-25 18:31:00',
        },
      },
    });

    expect(snapshot.tracking?.deliverySendStatus, 60);
    expect(snapshot.tracking?.coordinateType, 'gcj02');
    expect(snapshot.tracking?.rider?.locationLogId, 108);
    expect(snapshot.tracking?.rider?.locationUpdatedAt, '2026-08-25 18:30:00');
    expect(snapshot.tracking?.trajectoryState.orderStatus, '异常单');
    expect(snapshot.tracking?.trajectoryState.cancelReason, '顾客临时取消');
    expect(snapshot.receivingStatusLabel, '配送已取消');
    expect(snapshot.canRedispatch, isTrue);
    expect(snapshot.isActive, isFalse);
  });

  test('shows the rider-arrived state from the ZSQ send status', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'delivering',
        'zsq_dispatch_status': 'dispatched',
      },
      'tracking': {
        'phase': 'TO_SHOP',
        'deliverySendStatus': 80,
        'deliverySendStatusDesc': '骑手已到店',
      },
    });

    expect(snapshot.receivingStatusLabel, '骑手已到店');
    expect(snapshot.isActive, isTrue);
  });

  test('uses live tracking dispatch statuses ahead of persisted delivery', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'delivering',
        'zsq_dispatch_status': 'dispatched',
      },
      'tracking': {
        'phase': 'UNKNOWN',
        'dispatchStatus': 'completed',
        'zsqDispatchStatus': 'completed',
      },
    });

    expect(snapshot.tracking?.dispatchStatus, 'completed');
    expect(snapshot.tracking?.zsqDispatchStatus, 'completed');
    expect(snapshot.receivingStatusLabel, '配送已完成');
    expect(snapshot.isCompleted, isTrue);
    expect(snapshot.canRedispatch, isTrue);
    expect(snapshot.isActive, isFalse);
  });

  test(
    'rejects invalid tracking coordinates and stops polling terminal orders',
    () {
      final snapshot = TakeoutDeliverySnapshot.fromJson({
        'delivery': {'zsq_dispatch_status': 'completed', 'zsq_phase': ''},
        'tracking': {
          'phase': '',
          'shop': {'address': '只有地址，没有坐标'},
          'rider': {'name': '李师傅', 'lat': 200, 'lng': 116.4},
        },
      });

      expect(snapshot.tracking?.shop, isNull);
      expect(snapshot.tracking?.rider?.position, isNull);
      expect(snapshot.isActive, isFalse);
    },
  );

  test('marks a deleted ZSQ order as redispatchable and terminal', () {
    final snapshot = TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'dispatch_failed',
        'zsq_dispatch_status': 'order_missing',
        'zsq_phase': 'ORDER_MISSING',
        'zsq_open_order_id': 0,
        'zsq_last_error': '真省钱配送订单不存在或已删除，可重新下单配送',
      },
      'tracking': {'phase': 'ORDER_MISSING'},
    });

    expect(snapshot.receivingStatusLabel, '配送订单已删除');
    expect(snapshot.canRedispatch, isTrue);
    expect(snapshot.isActive, isFalse);
  });

  test('builds a GCJ-02 AMap road tile URI', () {
    final uri = buildAmapRoadTileUri(subdomain: '2', x: 421, y: 193, z: 10);

    expect(uri.scheme, 'https');
    expect(uri.host, 'webrd02.is.autonavi.com');
    expect(uri.path, '/appmaptile');
    expect(uri.queryParameters['lang'], 'zh_cn');
    expect(uri.queryParameters['style'], '8');
    expect(uri.queryParameters['x'], '421');
    expect(uri.queryParameters['y'], '193');
    expect(uri.queryParameters['z'], '10');
  });

  test(
    'real repository dispatches and redispatches through ZSQ endpoints',
    () async {
      final transport = FakeHttpTransport({
        'POST /admin/takeout/delivery/zsq/dispatch': jsonEncode({
          'code': 0,
          'delivery': {
            'dispatch_status': 'accepted',
            'zsq_dispatch_status': 'pending',
            'zsq_phase': 'WAITING_RIDER',
            'zsq_open_order_id': 901,
          },
        }),
        'POST /admin/takeout/delivery/zsq/redispatch': jsonEncode({
          'code': 0,
          'delivery': {
            'dispatch_status': 'accepted',
            'zsq_dispatch_status': 'pending',
            'zsq_phase': 'WAITING_RIDER',
            'zsq_open_order_id': 902,
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
        'id': 19,
        'receiving_status': 'rec_order',
      }, type: FulfillmentType.takeout);

      final first = await repository.dispatchTakeoutRider(order);
      final retry = await repository.dispatchTakeoutRider(
        order,
        redispatch: true,
      );

      expect(first.delivery.zsqOpenOrderId, 901);
      expect(retry.delivery.zsqOpenOrderId, 902);
      expect(transport.requests.map((request) => request.uri.path), [
        '/admin/takeout/delivery/zsq/dispatch',
        '/admin/takeout/delivery/zsq/redispatch',
      ]);
      expect(jsonDecode(transport.requests.first.body!), {'orderId': 19});
    },
  );

  test(
    'real repository cancels delivery through the status endpoint',
    () async {
      final transport = FakeHttpTransport({
        'POST /admin/takeout/delivery/status': jsonEncode({
          'code': 0,
          'delivery': {
            'dispatch_status': 'cancelled',
            'zsq_dispatch_status': 'cancelled',
            'zsq_phase': 'CANCELLED',
            'zsq_open_order_id': 901,
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
        'id': 19,
      }, type: FulfillmentType.takeout);

      final cancelled = await repository.cancelTakeoutDelivery(order);

      expect(cancelled.receivingStatusLabel, '配送已取消');
      expect(cancelled.canCancel, isFalse);
      expect(cancelled.canRedispatch, isTrue);
      expect(
        transport.requests.single.uri.path,
        '/admin/takeout/delivery/status',
      );
      expect(jsonDecode(transport.requests.single.body!), {
        'orderId': 19,
        'dispatch_status': 'cancelled',
      });
    },
  );

  test(
    'real repository loads persisted delivery then live rider tracking',
    () async {
      final transport = FakeHttpTransport({
        'GET /admin/takeout/delivery/detail': jsonEncode({
          'code': 0,
          'delivery': {
            'zsq_open_order_id': 901,
            'zsq_dispatch_status': 'dispatched',
          },
        }),
        'GET /admin/takeout/delivery/tracking': jsonEncode({
          'code': 0,
          'delivery': {
            'zsq_open_order_id': 901,
            'zsq_dispatch_status': 'dispatched',
            'zsq_phase': 'TO_USER',
          },
          'tracking': {
            'phase': 'TO_USER',
            'rider': {'name': '李师傅', 'lat': 39.9, 'lng': 116.4},
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
        'id': 19,
      }, type: FulfillmentType.takeout);

      final snapshot = await repository.loadTakeoutDelivery(order);

      expect(snapshot?.tracking?.rider?.name, '李师傅');
      expect(transport.requests.map((request) => request.uri.path), [
        '/admin/takeout/delivery/detail',
        '/admin/takeout/delivery/tracking',
      ]);
      expect(transport.requests.last.uri.queryParameters, {'orderId': '19'});
    },
  );

  test(
    'tracking code 4091 reloads the persisted order-missing delivery state',
    () async {
      final transport = _OrderMissingTransport();
      final repository = RealTableRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 't',
          shopId: 2,
        ),
      );
      final order = FulfillmentOrder.fromJson({
        'id': 21,
      }, type: FulfillmentType.takeout);

      final snapshot = await repository.loadTakeoutDelivery(order);

      expect(snapshot?.delivery.zsqDispatchStatus, 'order_missing');
      expect(snapshot?.delivery.zsqOpenOrderId, 0);
      expect(snapshot?.canRedispatch, isTrue);
      expect(transport.detailLoads, 2);
    },
  );

  test(
    'temporary tracking errors preserve the active delivery state',
    () async {
      final transport = FakeHttpTransport({
        'GET /admin/takeout/delivery/detail': jsonEncode({
          'code': 0,
          'delivery': {
            'dispatch_status': 'delivering',
            'zsq_dispatch_status': 'dispatched',
            'zsq_phase': 'TO_USER',
            'zsq_open_order_id': 906,
            'zsq_rider_name': '李师傅',
          },
        }),
        'GET /admin/takeout/delivery/tracking': jsonEncode({
          'code': 5001,
          'msg': '真省钱系统繁忙，请稍后重试',
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
        'id': 23,
      }, type: FulfillmentType.takeout);

      final snapshot = await repository.loadTakeoutDelivery(order);

      expect(snapshot?.delivery.zsqDispatchStatus, 'dispatched');
      expect(snapshot?.delivery.zsqOpenOrderId, 906);
      expect(snapshot?.delivery.riderName, '李师傅');
      expect(snapshot?.isOrderMissing, isFalse);
    },
  );

  testWidgets(
    'takeout detail calls a rider and shows ZSQ tracking on the map',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _TakeoutRepository();
      final order = FulfillmentOrder.fromJson({
        'id': 19,
        'order_no': 'ORD19',
        'pickup_code': 'B2019',
        'transac_status': 'success',
        'receiving_status': 'rec_order',
        'sett_amount': 88,
      }, type: FulfillmentType.takeout);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFulfillmentOrderDetail(
                context: context,
                repository: repository,
                order: order,
                canUpdate: true,
              ),
              child: const Text('打开'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('fulfillment-order-detail-page')),
        findsOneWidget,
      );
      final page = tester.widget<Scaffold>(
        find.byKey(const Key('fulfillment-order-detail-page')),
      );
      expect(page.backgroundColor, Colors.white);
      expect(find.byType(Dialog), findsNothing);
      expect(
        find.byKey(const Key('takeout-dispatch-rider-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('takeout-dispatch-rider-button')));
      await tester.pumpAndSettle();

      expect(repository.dispatchCount, 1);
      expect(find.byKey(const Key('takeout-rider-map')), findsOneWidget);
      expect(
        tester.getSize(find.byKey(const Key('takeout-rider-map'))).height,
        greaterThanOrEqualTo(400),
      );
      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(TileLayer), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.byKey(const Key('takeout-map-zoom-in')), findsNothing);
      expect(find.byKey(const Key('takeout-map-zoom-out')), findsNothing);
      expect(find.byKey(const Key('takeout-map-reset')), findsNothing);
      final tileLayer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect(tileLayer.urlTemplate, amapRoadTileUrlTemplate);
      expect(tileLayer.subdomains, amapRoadTileSubdomains);
      expect(tileLayer.keepBuffer, 3);
      expect(tileLayer.panBuffer, 1);
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      final flags = map.options.interactionOptions.flags;
      expect(flags & InteractiveFlag.scrollWheelZoom, isNot(0));
      expect(flags & InteractiveFlag.pinchZoom, isNot(0));
      expect(flags & InteractiveFlag.rotate, 0);
      expect(find.byKey(const Key('takeout-map-shop-marker')), findsOneWidget);
      expect(find.byKey(const Key('takeout-map-user-marker')), findsOneWidget);
      expect(find.byKey(const Key('takeout-map-rider-marker')), findsOneWidget);
      final mapController = MapController.of(
        tester.element(find.byType(MarkerLayer)),
      );
      final initialZoom = mapController.camera.zoom;
      final mapCenter = tester.getCenter(find.byType(FlutterMap));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: mapCenter,
          scrollDelta: const Offset(0, -120),
          kind: PointerDeviceKind.mouse,
        ),
      );
      await tester.pump();
      expect(mapController.camera.zoom, greaterThan(initialZoom));
      final wheelZoom = mapController.camera.zoom;
      final firstFinger = await tester.startGesture(
        mapCenter - const Offset(24, 0),
        pointer: 1,
      );
      final secondFinger = await tester.startGesture(
        mapCenter + const Offset(24, 0),
        pointer: 2,
      );
      await firstFinger.moveTo(mapCenter - const Offset(80, 0));
      await secondFinger.moveTo(mapCenter + const Offset(80, 0));
      await tester.pump();
      expect(mapController.camera.zoom, greaterThan(wheelZoom));
      await firstFinger.up();
      await secondFinger.up();
      await tester.pump();
      expect(find.text('骑手配送中'), findsWidgets);
      expect(find.text('李师傅  13900139000'), findsOneWidget);
      expect(find.text('8分钟 · 2.1公里'), findsOneWidget);
      expect(find.text('骑手正在配送'), findsOneWidget);
      expect(find.text('配送状态已回传'), findsOneWidget);
      expect(find.text('配送中'), findsWidgets);
      expect(find.text('2026-08-25 18:30:00'), findsOneWidget);
      expect(find.text('完成配送'), findsNothing);
      expect(
        find.byKey(const Key('takeout-cancel-delivery-button')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('takeout-cancel-delivery-button')));
      await tester.pumpAndSettle();
      expect(find.text('取消配送订单'), findsWidgets);
      expect(find.textContaining('责任费用'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-notice-primary')));
      await tester.pumpAndSettle();
      expect(repository.cancelCount, 1);
      expect(find.text('配送已取消'), findsWidgets);
      expect(find.text('重新叫骑手'), findsOneWidget);
      expect(
        find.byKey(const Key('takeout-cancel-delivery-button')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'tracking polling updates in place without reloading the detail page',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _RefreshingTakeoutRepository();
      final order = FulfillmentOrder.fromJson({
        'id': 20,
        'order_no': 'ORD20',
        'pickup_code': 'B2020',
        'transac_status': 'success',
        'receiving_status': 'rec_order',
        'dispatch_status': 'accepted',
        'sett_amount': 66,
      }, type: FulfillmentType.takeout);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFulfillmentOrderDetail(
                context: context,
                repository: repository,
                order: order,
                canUpdate: true,
              ),
              child: const Text('打开追踪'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开追踪'));
      await tester.pumpAndSettle();
      expect(find.text('等待骑手接单'), findsWidgets);

      await tester.pump(const Duration(seconds: 20));
      await tester.pump();

      expect(repository.detailLoadCount, 1);
      expect(find.text('正在加载订单'), findsNothing);
      expect(find.text('骑手配送中'), findsWidgets);
      expect(find.text('ORD20'), findsOneWidget);
    },
  );

  testWidgets('deleted ZSQ order shows an alert and can be redispatched', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _MissingOrderRepository();
    final order = FulfillmentOrder.fromJson({
      'id': 21,
      'order_no': 'ORD21',
      'pickup_code': 'B2021',
      'transac_status': 'success',
      'receiving_status': 'rec_order',
      'sett_amount': 66,
    }, type: FulfillmentType.takeout);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFulfillmentOrderDetail(
              context: context,
              repository: repository,
              order: order,
              canUpdate: true,
            ),
            child: const Text('打开删除订单'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开删除订单'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('takeout-order-missing-alert')),
      findsOneWidget,
    );
    expect(find.text('真省钱配送订单不存在或已删除，可重新下单配送'), findsOneWidget);
    expect(find.text('重新叫骑手'), findsOneWidget);

    await tester.tap(find.text('重新叫骑手'));
    await tester.pumpAndSettle();

    expect(repository.redispatchCount, 1);
    expect(find.byKey(const Key('takeout-order-missing-alert')), findsNothing);
    expect(find.text('等待骑手接单'), findsWidgets);
  });

  testWidgets('delivery WebSocket events refresh the open detail page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _AlertRefreshRepository();
    final alerts = StreamController<TakeoutDispatchAlert>.broadcast();
    addTearDown(alerts.close);
    final order = FulfillmentOrder.fromJson({
      'id': 22,
      'order_no': 'ORD22',
      'pickup_code': 'B2022',
      'transac_status': 'success',
      'receiving_status': 'rec_order',
      'sett_amount': 66,
    }, type: FulfillmentType.takeout);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFulfillmentOrderDetail(
              context: context,
              repository: repository,
              order: order,
              canUpdate: true,
              dispatchAlerts: alerts.stream,
            ),
            child: const Text('打开实时追踪'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开实时追踪'));
    await tester.pumpAndSettle();
    expect(find.text('等待骑手接单'), findsWidgets);

    alerts.add(
      const TakeoutDispatchAlert(
        eventType: 'takeout_dispatch_changed',
        alertType: '',
        orderId: 22,
        shopId: 2,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(repository.trackingLoadCount, 2);

    repository.orderMissing = true;
    alerts.add(
      const TakeoutDispatchAlert(
        alertType: 'order_missing',
        orderId: 22,
        shopId: 2,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('takeout-order-missing-alert')),
      findsOneWidget,
    );
    expect(repository.trackingLoadCount, 3);
    expect(repository.detailLoadCount, 1);
  });

  testWidgets('completed takeout delivery can be dispatched again', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CompletedDeliveryRepository();
    final order = FulfillmentOrder.fromJson({
      'id': 24,
      'order_no': 'ORD24',
      'pickup_code': 'B2024',
      'transac_status': 'success',
      'receiving_status': 'off_order',
      'dispatch_status': 'completed',
      'zsq_dispatch_status': 'completed',
      'zsq_phase': 'DELIVERED',
      'sett_amount': 66,
    }, type: FulfillmentType.takeout);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showFulfillmentOrderDetail(
              context: context,
              repository: repository,
              order: order,
              canUpdate: true,
            ),
            child: const Text('打开已完成配送'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开已完成配送'));
    await tester.pumpAndSettle();

    expect(find.text('再次配送'), findsOneWidget);
    await tester.tap(find.text('再次配送'));
    await tester.pumpAndSettle();

    expect(repository.redispatchCount, 1);
    expect(find.text('等待骑手接单'), findsWidgets);
  });

  testWidgets(
    'balance failure hides cancel and retries through the initial dispatch endpoint',
    (tester) async {
      final repository = _FailedDispatchRepository();
      final order = FulfillmentOrder.fromJson({
        'id': 13602,
        'order_no': 'ORD13602',
        'transac_status': 'success',
        'receiving_status': 'rec_order',
        'dispatch_status': 'dispatch_failed',
      }, type: FulfillmentType.takeout);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFulfillmentOrderDetail(
                context: context,
                repository: repository,
                order: order,
                canUpdate: true,
              ),
              child: const Text('打开余额不足订单'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开余额不足订单'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('takeout-cancel-delivery-button')),
        findsNothing,
      );
      expect(find.text('重新叫骑手'), findsOneWidget);

      await tester.tap(find.text('重新叫骑手'));
      await tester.pumpAndSettle();

      expect(repository.dispatchCount, 1);
      expect(repository.lastRedispatch, isFalse);
    },
  );

  testWidgets(
    'fulfillment dispatch dialog lists all takeout and pickup orders with rider dispatch and pickup reminder buttons',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final takeoutOrder = FulfillmentOrder.fromJson({
        'id': 101,
        'order_no': 'TK-101',
        'pickup_code': '08',
        'order_type': '外卖',
        'payable_amount': 88.0,
        'receiving_status': 'rec_order',
        'dispatch_status': 'pending',
      }, type: FulfillmentType.takeout);

      final pickupOrder = FulfillmentOrder.fromJson({
        'id': 102,
        'order_no': 'PK-102',
        'pickup_code': '03',
        'order_type': '自提',
        'payable_amount': 45.0,
        'receiving_status': 'pending',
      }, type: FulfillmentType.pickup);

      final completedOrder = FulfillmentOrder.fromJson({
        'id': 103,
        'order_no': 'TK-103',
        'pickup_code': '09',
        'order_type': '外卖',
        'payable_amount': 99.0,
        'receiving_status': 'off_order',
        'dispatch_status': 'completed',
      }, type: FulfillmentType.takeout);

      final repository = _DispatchDialogTestRepository(
        takeoutOrders: [takeoutOrder, completedOrder],
        pickupOrders: [pickupOrder],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFulfillmentDispatchDialog(
                  context: context,
                  repository: repository,
                  canUpdate: true,
                ),
                child: const Text('打开履约调度'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开履约调度'));
      await tester.pumpAndSettle();

      // 验证标题中的数量只显示未完成的数量 (2笔未完成，总共3笔)
      expect(find.text('🛵 履约外卖 (2)'), findsOneWidget);
      expect(find.text('共 3 笔订单 · 2 笔未完成'), findsOneWidget);

      // 验证外卖与自提订单均显示在列表中
      expect(find.text('#B08'), findsOneWidget);
      expect(find.text('#A03'), findsOneWidget);
      expect(find.text('#B09'), findsOneWidget);
      expect(find.text('外卖'), findsWidgets);
      expect(find.text('自提'), findsWidgets);

      // 验证一键叫骑手按钮与自提提醒按钮存在
      expect(find.byKey(const Key('btn-dispatch-rider-101')), findsOneWidget);
      expect(find.byKey(const Key('btn-pickup-remind-102')), findsOneWidget);

      // 点击外卖一键叫骑手
      await tester.tap(find.byKey(const Key('btn-dispatch-rider-101')));
      await tester.pumpAndSettle();
      expect(repository.dispatchedOrderIds, contains(101));

      // 点击叫骑手成功后，按钮转为【取消配送】与【完成配送】
      expect(find.byKey(const Key('btn-cancel-delivery-101')), findsOneWidget);
      expect(find.byKey(const Key('btn-complete-delivery-101')), findsOneWidget);
      expect(find.byKey(const Key('btn-dispatch-rider-101')), findsNothing);

      // 点击取消配送，弹出确认框后确认
      await tester.tap(find.byKey(const Key('btn-cancel-delivery-101')));
      await tester.pumpAndSettle();
      expect(find.text('取消配送确认'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-notice-primary')));
      await tester.pumpAndSettle();
      expect(repository.cancelledOrderIds, contains(101));

      // 取消配送后，按钮重新变为【重新叫骑手】
      expect(find.byKey(const Key('btn-dispatch-rider-101')), findsOneWidget);
      expect(find.text('重新叫骑手'), findsOneWidget);
      expect(find.byKey(const Key('btn-cancel-delivery-101')), findsNothing);

      // 点击自提提醒
      await tester.tap(find.byKey(const Key('btn-pickup-remind-102')));
      await tester.pumpAndSettle();
      expect(repository.remindedOrderIds, contains(102));
    },
  );

  testWidgets(
    'takeout order detail opens as drawer, displays remark, and dismisses on tapping blank area',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order = FulfillmentOrder.fromJson({
        'id': 999,
        'order_no': 'ORD-REMARK-001',
        'pickup_code': 'B99',
        'transac_status': 'success',
        'receiving_status': 'rec_order',
        'sett_amount': 88,
        'remark': '微辣，多放葱花，放在门口柜子上',
      }, type: FulfillmentType.takeout);

      final repository = _TakeoutRepository();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFulfillmentOrderDetail(
                  context: context,
                  repository: repository,
                  order: order,
                  canUpdate: true,
                ),
                child: const Text('打开详情抽屉'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开详情抽屉'));
      await tester.pumpAndSettle();

      // 验证抽屉正常打开
      expect(find.byKey(const Key('fulfillment-order-detail-page')), findsOneWidget);
      // 验证订单备注在信息格和高亮备注框中均正确展示
      expect(find.text('微辣，多放葱花，放在门口柜子上'), findsWidgets);
      expect(find.byKey(const Key('fulfillment-order-remark-box')), findsOneWidget);
      expect(find.text('备注说明：'), findsOneWidget);

      // 抽屉位于右侧（left offset 大于 0）
      final drawerRect = tester.getRect(find.byKey(const Key('fulfillment-order-detail-page')));
      expect(drawerRect.left, greaterThan(0));
      expect(drawerRect.right, equals(1280));

      // 点击左侧空白区域（例如 x=50, y=200），抽屉自动收回
      await tester.tapAt(const Offset(50, 200));
      await tester.pumpAndSettle();

      // 验证抽屉已关闭
      expect(find.byKey(const Key('fulfillment-order-detail-page')), findsNothing);
    },
  );

  testWidgets(
    'drawer order detail navigates to bills to operate refund',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final order = FulfillmentOrder.fromJson({
        'id': 888,
        'order_no': 'ORD-REFUND-888',
        'pickup_code': 'B88',
        'transac_status': 'success',
        'receiving_status': 'rec_order',
        'sett_amount': 99,
      }, type: FulfillmentType.takeout);

      final repository = _TakeoutRepository();
      String? navigatedOrderNo;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showFulfillmentOrderDetail(
                  context: context,
                  repository: repository,
                  order: order,
                  canUpdate: true,
                  onNavigateToBillRefund: (orderNo) {
                    navigatedOrderNo = orderNo;
                  },
                ),
                child: const Text('打开详情抽屉'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开详情抽屉'));
      await tester.pumpAndSettle();

      // 验证存在【去账单退款】按钮
      final refundBtn = find.text('去账单退款');
      expect(refundBtn, findsOneWidget);

      // 点击【去账单退款】按钮
      await tester.tap(refundBtn);
      await tester.pumpAndSettle();

      // 验证已回调至账单跳转并关闭抽屉
      expect(navigatedOrderNo, 'ORD-REFUND-888');
      expect(find.byKey(const Key('fulfillment-order-detail-page')), findsNothing);
    },
  );
}

class _DispatchDialogTestRepository
    with _StubTableManagement
    implements TableRepository, TakeoutDeliveryRepository {
  _DispatchDialogTestRepository({
    required this.takeoutOrders,
    required this.pickupOrders,
  });

  final List<FulfillmentOrder> takeoutOrders;
  final List<FulfillmentOrder> pickupOrders;
  final List<int> dispatchedOrderIds = [];
  final List<int> cancelledOrderIds = [];
  final List<int> remindedOrderIds = [];

  @override
  Future<TableOverview> loadTableOverview() async {
    return TableOverview(
      tables: const [],
      takeoutOrders: takeoutOrders,
      pickupOrders: pickupOrders,
    );
  }

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async => FulfillmentOrderDetail(order: order, lines: const []);

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async => null;

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) async {
    dispatchedOrderIds.add(order.id);
    final index = takeoutOrders.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      takeoutOrders[index] = FulfillmentOrder(
        id: order.id,
        type: order.type,
        status: FulfillmentStatus.delivering,
        pickupCode: order.pickupCode,
        orderNo: order.orderNo,
        tableNumber: order.tableNumber,
        amount: order.amount,
        receivingStatus: order.receivingStatus,
        kdsOrderStatus: order.kdsOrderStatus,
        dispatchStatus: 'delivering',
        createdAt: order.createdAt,
      );
    }
    return TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'delivering',
        'zsq_dispatch_status': 'dispatched',
        'zsq_phase': 'TO_USER',
        'zsq_open_order_id': 999,
      },
      'tracking': {'phase': 'TO_USER'},
    });
  }

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) async {
    cancelledOrderIds.add(order.id);
    final index = takeoutOrders.indexWhere((o) => o.id == order.id);
    if (index >= 0) {
      takeoutOrders[index] = FulfillmentOrder(
        id: order.id,
        type: order.type,
        status: FulfillmentStatus.waiting,
        pickupCode: order.pickupCode,
        orderNo: order.orderNo,
        tableNumber: order.tableNumber,
        amount: order.amount,
        receivingStatus: order.receivingStatus,
        kdsOrderStatus: order.kdsOrderStatus,
        dispatchStatus: 'cancelled',
        createdAt: order.createdAt,
      );
    }
    return TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'cancelled',
        'zsq_dispatch_status': 'cancelled',
        'zsq_phase': 'CANCELLED',
      },
    });
  }

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {
    remindedOrderIds.add(order.id);
  }
}

mixin _StubTableManagement {
  Future<void> createTable({
    required String number,
    int peopleCount = 4,
    String? areaCode,
    String? areaName,
  }) async {}
  Future<void> updateTable({
    required int id,
    required String number,
    int? peopleCount,
    String? areaCode,
    String? areaName,
  }) async {}
  Future<void> deleteTable(int id) async {}
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {}
  Future<List<Map<String, dynamic>>> loadTableAreas() async => const [];
  Future<void> batchClearTables({
    List<int>? tableIds,
    List<String>? tableNumbers,
    String? operatorAccount,
  }) async {}
  Future<void> updateTableDiners({
    required String orderNo,
    required String tableNumber,
    required int diners,
    String? operatorAccount,
  }) async {}
  Future<Map<String, dynamic>?> loadTablePulse() async => null;
}

class _FailedDispatchRepository
    with _StubTableManagement
    implements TableRepository, TakeoutDeliveryRepository {
  var dispatchCount = 0;
  bool? lastRedispatch;

  TakeoutDeliverySnapshot get failedSnapshot =>
      TakeoutDeliverySnapshot.fromJson({
        'delivery': {
          'dispatch_status': 'dispatch_failed',
          'zsq_dispatch_status': 'failed',
          'zsq_phase': 'WAITING_RIDER',
          'zsq_open_order_id': 901,
          'zsq_last_error': '余额不足，请充值',
        },
        'tracking': {
          'effectiveState': {
            'phase': 'WAITING_RIDER',
            'source': 'ORDER_DETAIL',
          },
        },
      });

  @override
  Future<TableOverview> loadTableOverview() async =>
      const TableOverview(tables: []);

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async => FulfillmentOrderDetail(order: order, lines: const []);

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async => failedSnapshot;

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) async {
    dispatchCount++;
    lastRedispatch = redispatch;
    return failedSnapshot;
  }

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) => throw StateError('余额不足时不应允许取消配送');

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {}
}

class _OrderMissingTransport implements HttpTransport {
  int detailLoads = 0;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,  }) async {
    if (uri.path == '/admin/takeout/delivery/detail') {
      detailLoads++;
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 0,
          'delivery': detailLoads == 1
              ? {
                  'dispatch_status': 'delivering',
                  'zsq_dispatch_status': 'dispatched',
                  'zsq_phase': 'TO_USER',
                  'zsq_open_order_id': 903,
                }
              : {
                  'dispatch_status': 'dispatch_failed',
                  'zsq_dispatch_status': 'order_missing',
                  'zsq_phase': 'ORDER_MISSING',
                  'zsq_open_order_id': 0,
                },
        }),
      );
    }
    if (uri.path == '/admin/takeout/delivery/tracking') {
      return HttpResponseData(
        statusCode: 200,
        body: jsonEncode({
          'code': 4091,
          'msg': '真省钱配送订单不存在或已删除，可重新下单配送',
          'canRedispatch': true,
        }),
      );
    }
    return const HttpResponseData(statusCode: 404, body: 'missing route');
  }
}

class _TakeoutRepository
    with _StubTableManagement
    implements TableRepository, TakeoutDeliveryRepository {
  var dispatchCount = 0;
  var cancelCount = 0;
  var dispatched = false;

  @override
  Future<TableOverview> loadTableOverview() async =>
      const TableOverview(tables: []);

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async => FulfillmentOrderDetail(
    order: dispatched
        ? FulfillmentOrder.fromJson({
            'id': order.id,
            'order_no': order.orderNo,
            'pickup_code': order.pickupCode,
            'transac_status': 'success',
            'receiving_status': 'rec_order',
            'dispatch_status': 'delivering',
            'sett_amount': order.amount,
          }, type: FulfillmentType.takeout)
        : order,
    lines: const [],
  );

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async => dispatched ? _trackingSnapshot() : null;

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) async {
    dispatchCount++;
    dispatched = true;
    return _trackingSnapshot();
  }

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) async {
    cancelCount++;
    return TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': 'cancelled',
        'zsq_dispatch_status': 'cancelled',
        'zsq_phase': 'CANCELLED',
        'zsq_open_order_id': 901,
      },
      'tracking': {'phase': 'CANCELLED'},
    });
  }

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {}

  TakeoutDeliverySnapshot _trackingSnapshot() =>
      TakeoutDeliverySnapshot.fromJson({
        'delivery': {
          'dispatch_status': 'delivering',
          'zsq_dispatch_status': 'dispatched',
          'zsq_phase': 'TO_USER',
          'zsq_open_order_id': 901,
          'receiver_name': '张三',
          'receiver_phone': '13800138000',
          'address_full': '北京市朝阳区测试路 1 号',
          'lat': 39.91,
          'lng': 116.41,
        },
        'tracking': {
          'phase': 'TO_USER',
          'deliverySendStatus': 40,
          'deliverySendStatusDesc': '骑手正在配送',
          'coordinateType': 'gcj02',
          'rider': {
            'name': '李师傅',
            'phone': '13900139000',
            'lat': 39.905,
            'lng': 116.405,
            'locationLogId': 108,
            'locationUpdatedAt': '2026-08-25 18:30:00',
          },
          'shop': {'lat': 39.9, 'lng': 116.4},
          'user': {'lat': 39.91, 'lng': 116.41},
          'platformEta': {'durationText': '8分钟', 'distanceText': '2.1公里'},
          'trajectoryState': {
            'callbackStatus': '配送状态已回传',
            'orderStatus': '配送中',
            'deliveryStatus': '骑手配送中',
            'latestStatusLogId': 109,
            'statusUpdatedAt': '2026-08-25 18:31:00',
          },
        },
      });
}

class _RefreshingTakeoutRepository
    with _StubTableManagement
    implements TableRepository, TakeoutDeliveryRepository {
  var detailLoadCount = 0;
  var trackingLoadCount = 0;

  @override
  Future<TableOverview> loadTableOverview() async =>
      const TableOverview(tables: []);

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async {
    detailLoadCount++;
    return FulfillmentOrderDetail(order: order, lines: const []);
  }

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async {
    trackingLoadCount++;
    final moving = trackingLoadCount > 1;
    return TakeoutDeliverySnapshot.fromJson({
      'delivery': {
        'dispatch_status': moving ? 'delivering' : 'accepted',
        'zsq_dispatch_status': moving ? 'dispatched' : 'pending',
        'zsq_phase': moving ? 'TO_USER' : 'WAITING_RIDER',
        'zsq_open_order_id': 902,
      },
      'tracking': {
        'phase': moving ? 'TO_USER' : 'WAITING_RIDER',
        if (moving) 'rider': {'name': '王师傅', 'lat': 39.905, 'lng': 116.405},
        'shop': {'lat': 39.9, 'lng': 116.4},
        'user': {'lat': 39.91, 'lng': 116.41},
      },
    });
  }

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) => throw UnimplementedError();

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) => throw UnimplementedError();

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {}
}

class _MissingOrderRepository
    with _StubTableManagement
    implements TableRepository, TakeoutDeliveryRepository {
  var redispatchCount = 0;
  var redispatched = false;

  @override
  Future<TableOverview> loadTableOverview() async =>
      const TableOverview(tables: []);

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async => FulfillmentOrderDetail(order: order, lines: const []);

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async => TakeoutDeliverySnapshot.fromJson({
    'delivery': redispatched
        ? {
            'dispatch_status': 'accepted',
            'zsq_dispatch_status': 'pending',
            'zsq_phase': 'WAITING_RIDER',
            'zsq_open_order_id': 904,
          }
        : {
            'dispatch_status': 'dispatch_failed',
            'zsq_dispatch_status': 'order_missing',
            'zsq_phase': 'ORDER_MISSING',
            'zsq_open_order_id': 0,
            'zsq_last_error': '真省钱配送订单不存在或已删除，可重新下单配送',
          },
    'tracking': {'phase': redispatched ? 'WAITING_RIDER' : 'ORDER_MISSING'},
  });

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) async {
    expect(redispatch, isTrue);
    redispatchCount++;
    redispatched = true;
    return (await loadTakeoutDelivery(order))!;
  }

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) => throw UnimplementedError();

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {}
}

class _AlertRefreshRepository
    with _StubTableManagement
    implements TableRepository, TakeoutDeliveryRepository {
  var detailLoadCount = 0;
  var trackingLoadCount = 0;
  var orderMissing = false;

  @override
  Future<TableOverview> loadTableOverview() async =>
      const TableOverview(tables: []);

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async {
    detailLoadCount++;
    return FulfillmentOrderDetail(order: order, lines: const []);
  }

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async {
    trackingLoadCount++;
    return TakeoutDeliverySnapshot.fromJson({
      'delivery': orderMissing
          ? {
              'dispatch_status': 'dispatch_failed',
              'zsq_dispatch_status': 'order_missing',
              'zsq_phase': 'ORDER_MISSING',
            }
          : {
              'dispatch_status': 'accepted',
              'zsq_dispatch_status': 'pending',
              'zsq_phase': 'WAITING_RIDER',
              'zsq_open_order_id': 905,
            },
      'tracking': {'phase': orderMissing ? 'ORDER_MISSING' : 'WAITING_RIDER'},
    });
  }

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) => throw UnimplementedError();

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) => throw UnimplementedError();

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {}
}

class _CompletedDeliveryRepository
    with _StubTableManagement
    implements TableRepository, TakeoutDeliveryRepository {
  var redispatchCount = 0;
  var redispatched = false;

  @override
  Future<TableOverview> loadTableOverview() async =>
      const TableOverview(tables: []);

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async => FulfillmentOrderDetail(order: order, lines: const []);

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async => TakeoutDeliverySnapshot.fromJson({
    'delivery': redispatched
        ? {
            'dispatch_status': 'accepted',
            'zsq_dispatch_status': 'pending',
            'zsq_phase': 'WAITING_RIDER',
            'zsq_open_order_id': 908,
          }
        : {
            'dispatch_status': 'completed',
            'zsq_dispatch_status': 'completed',
            'zsq_phase': 'DELIVERED',
            'zsq_open_order_id': 907,
            'zsq_rider_name': '旧骑手',
          },
    'tracking': {'phase': redispatched ? 'WAITING_RIDER' : 'DELIVERED'},
  });

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) async {
    expect(redispatch, isTrue);
    redispatchCount++;
    redispatched = true;
    return (await loadTakeoutDelivery(order))!;
  }

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) => throw UnimplementedError();

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {}
}
