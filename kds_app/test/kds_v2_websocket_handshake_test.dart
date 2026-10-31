import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/ws/kds_websocket.dart';

void main() {
  test('valid v2 events are acknowledged with the cloud event identity',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final acknowledgement = Completer<Map<String, dynamic>>();
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.listen((raw) {
        final decoded = jsonDecode('$raw');
        if (decoded is Map && decoded['type'] == 'ack') {
          acknowledgement.complete(decoded.cast<String, dynamic>());
        }
      });
      socket.add(jsonEncode({
        'protocol_version': 2,
        'event_seq': 41,
        'event_id': 'event-41',
        'type': 'order_updated',
        'shop_id': 7,
        'patches': const [],
        'queue_counts': const {},
      }));
    });
    final service = KdsWebSocketService(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getShopId: () => 7,
      getScreenTag: () => 'workflow_board',
      getToken: () => 'token',
      pingInterval: const Duration(hours: 1),
    );
    addTearDown(service.dispose);
    final events = service.eventStream.listen((_) {});
    addTearDown(events.cancel);

    service.connect();

    expect(
      await acknowledgement.future.timeout(const Duration(seconds: 2)),
      {
        'protocol_version': 2,
        'type': 'ack',
        'event_seq': 41,
        'event_id': 'event-41',
      },
    );
  });

  test('events received before a listener are buffered for cold start',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.transform(WebSocketTransformer()).listen((socket) {
      socket.add(jsonEncode({
        'protocol_version': 2,
        'event_seq': 3,
        'event_id': 'early-3',
        'type': 'order_created',
        'shop_id': 7,
        'patches': const [],
        'queue_counts': const {},
      }));
      socket.close();
    });
    final service = KdsWebSocketService(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getShopId: () => 7,
      getScreenTag: () => 'workflow_board',
      getToken: () => 'token',
      pingInterval: const Duration(hours: 1),
    );
    addTearDown(service.dispose);

    service.connect();
    await service.connectedStream.firstWhere((connected) => connected);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final buffered = service.drainBufferedEvents();
    expect(buffered.map((event) => event.raw['event_seq']), [3]);
    expect(service.drainBufferedEvents(), isEmpty);
  });

  test('LAN websocket handshake uses v2 path and device token header',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final requestSeen = Completer<(String, String?, String?)>();
    server.listen((request) async {
      requestSeen.complete((
        request.uri.path,
        request.headers.value('X-Kds-Device-Token'),
        request.uri.queryParameters['token'],
      ));
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {});
    });
    final service = KdsWebSocketService(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getShopId: () => 7,
      getScreenTag: () => 'workflow_board',
      getToken: () => 'device-token',
    );
    addTearDown(service.dispose);
    service.connect();

    expect(await requestSeen.future.timeout(const Duration(seconds: 5)),
        ('/ws/kds/v2', 'device-token', null));
  });

  test('missing pong marks the socket disconnected', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.listen((_) {}); // Intentionally never reply with pong.
    });
    final service = KdsWebSocketService(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getShopId: () => 7,
      getScreenTag: () => 'workflow_board',
      getToken: () => 'device-token',
      pingInterval: const Duration(milliseconds: 20),
      pongTimeout: const Duration(milliseconds: 10),
    );
    addTearDown(service.dispose);
    final states = <bool>[];
    final subscription = service.connectedStream.listen(states.add);
    addTearDown(subscription.cancel);

    service.connect();
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(states, containsAllInOrder([true, false]));
  });

  test('repeated websocket failures retain exponential reconnect backoff',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final connectedAt = <DateTime>[];
    final fourConnections = Completer<void>();
    server.transform(WebSocketTransformer()).listen((socket) async {
      connectedAt.add(DateTime.now());
      if (connectedAt.length == 4 && !fourConnections.isCompleted) {
        fourConnections.complete();
      }
      await socket.close();
    });
    final service = KdsWebSocketService(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getShopId: () => 7,
      getScreenTag: () => 'workflow_board',
      getToken: () => 'device-token',
      pingInterval: const Duration(hours: 1),
      reconnectBaseDelay: const Duration(milliseconds: 50),
      reconnectMaxDelay: const Duration(milliseconds: 400),
      reconnectJitterMax: Duration.zero,
    );
    addTearDown(service.dispose);

    service.connect();
    await fourConnections.future.timeout(const Duration(seconds: 3));

    final intervals = <int>[
      for (var index = 1; index < connectedAt.length; index++)
        connectedAt[index].difference(connectedAt[index - 1]).inMilliseconds,
    ];
    expect(intervals[0], greaterThanOrEqualTo(80));
    expect(intervals[1], greaterThanOrEqualTo(170));
    expect(intervals[2], greaterThanOrEqualTo(350));
  });
}
