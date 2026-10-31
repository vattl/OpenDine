import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

// Opt-in, read-only business drill. Authentication metadata is restored by the
// runner; no order, ticket, command, or event rows are created by this test.
void main() {
  final enabled = Platform.environment['RUN_REAL_KDS_WS_FAILOVER'] == 'true';
  test(
    'real WS keeps one token and cursor across failover and isolates stalled LAN delivery',
    () async {
      final cloud = Uri.parse(
        Platform.environment['KDS_DEBUG_CLOUD_URL'] ?? 'http://127.0.0.1:18080',
      );
      final deviceCode = Platform.environment['KDS_DEBUG_DEVICE_CODE']!;
      final currentToken = Platform.environment['KDS_DEBUG_CURRENT_TOKEN']!;
      final temp = await Directory.systemTemp.createTemp('kds-real-ws-');
      final database = CashierKdsDatabase.open('${temp.path}/cashier.db');
      final client = HttpClient()..findProxy = (_) => 'DIRECT';
      final server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: (body) async {
          final response = await _request(
            client,
            cloud.resolve('/kds/device/login'),
            'POST',
            token: currentToken,
            body: body,
          );
          expect(response.statusCode, HttpStatus.ok, reason: response.body);
          return (jsonDecode(response.body) as Map).cast<String, Object?>();
        },
        onProxyHttp: (request) async {
          final response = await _request(
            client,
            cloud
                .resolve(request.path)
                .replace(
                  queryParameters: request.query.map(
                    (key, value) => MapEntry(key, '$value'),
                  ),
                ),
            request.method,
            token: request.deviceToken,
          );
          return CashierKdsProxyResponse(
            statusCode: response.statusCode,
            body: response.body,
            headers: const {},
          );
        },
        onProxyWebSocket: (token, query) => WebSocket.connect(
          cloud
              .replace(scheme: 'ws', path: '/ws/kds/v2', queryParameters: query)
              .toString(),
          headers: {'X-Kds-Device-Token': token},
        ),
      );
      try {
        server.setActiveShop(1);
        await server.start(address: InternetAddress.loopbackIPv4, port: 0);
        final lan = Uri.parse('http://127.0.0.1:${server.port}');
        final login = await _request(
          client,
          lan.resolve('/kds/device/login'),
          'POST',
          body: {'device_code': deviceCode},
        );
        expect(login.statusCode, HttpStatus.ok, reason: login.body);
        final token =
            (jsonDecode(login.body) as Map)['data']['device_token'] as String;

        final before = await _changes(client, cloud, token);
        await _expectPong(lan, token, afterSeq: before.cursor);

        final port = server.port;
        await server.close();
        await _expectPong(cloud, token, afterSeq: before.cursor);
        final duringLoss = await _changes(client, cloud, token);
        expect(duringLoss.cursor, greaterThanOrEqualTo(before.cursor));

        await server.start(address: InternetAddress.loopbackIPv4, port: port);
        await _expectPong(lan, token, afterSeq: duringLoss.cursor);
        final afterRecovery = await _changes(client, lan, token);
        expect(afterRecovery.cursor, duringLoss.cursor);
        expect(afterRecovery.events, duringLoss.events);

        await _expectLanBackpressureWithRealEvents(
          database: database,
          token: token,
          events: afterRecovery.events,
        );
      } finally {
        await server.close();
        client.close(force: true);
        database.close();
        await temp.delete(recursive: true);
      }
    },
    skip: enabled ? false : 'Set RUN_REAL_KDS_WS_FAILOVER=true',
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

Future<void> _cacheCloudToken({
  required int shopId,
  required String deviceCode,
  required String token,
}) async {}

Future<void> _expectLanBackpressureWithRealEvents({
  required CashierKdsDatabase database,
  required String token,
  required List<Object?> events,
}) async {
  expect(
    events.length,
    greaterThanOrEqualTo(34),
    reason: '真实 debug 事件窗口至少需要 34 个保留信封',
  );
  final envelopes = events.take(34).map(jsonEncode).toList(growable: false);
  final upstreamServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final upstreamConnections = [Completer<WebSocket>(), Completer<WebSocket>()];
  var upstreamIndex = 0;
  upstreamServer.listen((request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    if (upstreamIndex >= upstreamConnections.length) {
      await socket.close(WebSocketStatus.policyViolation, 'unexpected client');
      return;
    }
    upstreamConnections[upstreamIndex++].complete(socket);
  });

  final relay = CashierKdsLanServer(
    database,
    cloudAuthorityMode: true,
    onProxyWebSocket: (_, __) =>
        WebSocket.connect('ws://127.0.0.1:${upstreamServer.port}/ws/kds/v2'),
  );
  WebSocket? slow;
  WebSocket? healthy;
  WebSocket? slowUpstream;
  WebSocket? healthyUpstream;
  StreamIterator<dynamic>? healthyEvents;
  StreamIterator<dynamic>? relayedAcks;
  try {
    relay.setActiveShop(1);
    await relay.start(address: InternetAddress.loopbackIPv4, port: 0);
    final relayUri = Uri.parse('ws://127.0.0.1:${relay.port}/ws/kds/v2');

    slow = await WebSocket.connect(
      relayUri.toString(),
      headers: {'X-Kds-Device-Token': token},
    );
    final slowClosed = Completer<void>();
    slow.listen((_) {}, onDone: slowClosed.complete);
    slowUpstream = await upstreamConnections[0].future;
    for (final envelope in envelopes.take(33)) {
      slowUpstream.add(envelope);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (slowClosed.isCompleted) break;
    }
    await slowClosed.future.timeout(const Duration(seconds: 10));
    expect(slow.closeCode, WebSocketStatus.policyViolation);
    expect(slow.closeReason, 'ack window overflow');

    healthy = await WebSocket.connect(
      relayUri.toString(),
      headers: {'X-Kds-Device-Token': token},
    );
    final healthyEventStream = StreamIterator<dynamic>(healthy);
    healthyEvents = healthyEventStream;
    healthyUpstream = await upstreamConnections[1].future;
    final relayedAckStream = StreamIterator<dynamic>(healthyUpstream);
    relayedAcks = relayedAckStream;
    for (final envelope in envelopes.take(2)) {
      healthyUpstream.add(envelope);
      expect(
        await healthyEventStream.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      final event = (jsonDecode('${healthyEventStream.current}') as Map)
          .cast<String, Object?>();
      final ack = <String, Object?>{
        'protocol_version': 2,
        'type': 'ack',
        'event_seq': event['event_seq'],
        'event_id': event['event_id'],
      };
      healthy.add(jsonEncode(ack));
      expect(
        await relayedAckStream.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect(jsonDecode('${relayedAckStream.current}'), ack);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(healthy.readyState, WebSocket.open);
    expect(relay.connectedDeviceCount, 1);
  } finally {
    await healthyEvents?.cancel();
    await relayedAcks?.cancel();
    await slow?.close();
    await healthy?.close();
    await slowUpstream?.close();
    await healthyUpstream?.close();
    await relay.close();
    await upstreamServer.close(force: true);
  }
}

Future<void> _expectPong(
  Uri base,
  String token, {
  required int afterSeq,
}) async {
  final socket = await WebSocket.connect(
    base
        .replace(
          scheme: 'ws',
          path: '/ws/kds/v2',
          queryParameters: {'shop_id': '1', 'after_seq': '$afterSeq'},
        )
        .toString(),
    headers: {'X-Kds-Device-Token': token},
  );
  try {
    socket.add('ping');
    expect(
      await socket.first.timeout(const Duration(seconds: 10)),
      '{"type":"pong"}',
    );
  } finally {
    await socket.close();
  }
}

Future<({int cursor, List<Object?> events})> _changes(
  HttpClient client,
  Uri base,
  String token,
) async {
  final response = await _request(
    client,
    base.resolve('/kds/v2/changes?after_seq=0'),
    'GET',
    token: token,
  );
  expect(response.statusCode, HttpStatus.ok, reason: response.body);
  final body = jsonDecode(response.body) as Map;
  final cursor = (body['latest_event_seq'] ?? body['event_seq']) as num;
  return (
    cursor: cursor.toInt(),
    events: List<Object?>.from(body['events'] as List? ?? const []),
  );
}

Future<({int statusCode, String body})> _request(
  HttpClient client,
  Uri uri,
  String method, {
  String? token,
  Map<String, Object?>? body,
}) async {
  final request = await client.openUrl(method, uri);
  if (token != null) request.headers.set('X-Kds-Device-Token', token);
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close();
  return (
    statusCode: response.statusCode,
    body: await utf8.decoder.bind(response).join(),
  );
}
