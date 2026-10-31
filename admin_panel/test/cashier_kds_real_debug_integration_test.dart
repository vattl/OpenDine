import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

// Explicit opt-in: uses the running debug Spring server and its real MySQL data.
void main() {
  final enabled = Platform.environment['RUN_REAL_KDS_DEBUG'] == 'true';
  test(
    'LAN HTTP and WS proxy the real debug cloud device',
    () async {
      final cloud = Uri.parse(
        Platform.environment['KDS_DEBUG_CLOUD_URL'] ?? 'http://127.0.0.1:18080',
      );
      final deviceCode = Platform.environment['KDS_DEBUG_DEVICE_CODE']!;
      final currentDeviceToken =
          Platform.environment['KDS_DEBUG_CURRENT_TOKEN']!;
      final temp = await Directory.systemTemp.createTemp('kds-real-debug-');
      final database = CashierKdsDatabase.open('${temp.path}/cashier.db');
      final client = HttpClient();
      final server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: true,
        onCacheCloudDeviceToken: _cacheCloudToken,
        onProxyLogin: (body) async {
          final response = await _request(
            client,
            cloud.resolve('/kds/device/login'),
            'POST',
            token: currentDeviceToken,
            body: body,
          );
          expect(response.statusCode, HttpStatus.ok);
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
            body: request.method == 'GET' ? null : request.body,
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
        expect(login.statusCode, HttpStatus.ok);
        final token =
            (jsonDecode(login.body) as Map)['data']['device_token'] as String;
        expect(token, isNotEmpty);
        final direct = await _request(
          client,
          cloud.resolve('/kds/v2/bootstrap'),
          'GET',
          token: token,
        );
        final proxied = await _request(
          client,
          lan.resolve('/kds/v2/bootstrap'),
          'GET',
          token: token,
        );
        expect(proxied.statusCode, direct.statusCode);
        expect(jsonDecode(proxied.body), jsonDecode(direct.body));

        // Real cashier-process loss/recovery drill. The cloud-issued token must
        // remain valid while the LAN listener is absent, and restarting the
        // proxy must expose the exact same authoritative snapshot again.
        final interruptedLanPort = server.port;
        await server.close();
        final lossProbeClient = HttpClient();
        lossProbeClient.findProxy = (_) => 'DIRECT';
        lossProbeClient.connectionTimeout = const Duration(seconds: 2);
        try {
          await expectLater(
            _request(
              lossProbeClient,
              lan.resolve('/kds/v2/bootstrap'),
              'GET',
              token: token,
            ),
            throwsA(anyOf(isA<SocketException>(), isA<HttpException>())),
          );
        } finally {
          lossProbeClient.close(force: true);
        }
        final cloudDuringCashierLoss = await _request(
          client,
          cloud.resolve('/kds/v2/bootstrap'),
          'GET',
          token: token,
        );
        expect(cloudDuringCashierLoss.statusCode, HttpStatus.ok);
        expect(
          jsonDecode(cloudDuringCashierLoss.body),
          jsonDecode(direct.body),
          reason: '收银代理停机不得改变云端权威快照或 KDS token',
        );
        await server.start(
          address: InternetAddress.loopbackIPv4,
          port: interruptedLanPort,
        );
        final lanAfterCashierRecovery = await _request(
          client,
          lan.resolve('/kds/v2/bootstrap'),
          'GET',
          token: token,
        );
        expect(lanAfterCashierRecovery.statusCode, HttpStatus.ok);
        expect(
          jsonDecode(lanAfterCashierRecovery.body),
          jsonDecode(cloudDuringCashierLoss.body),
          reason: '收银代理恢复后必须继续透传同一云端快照',
        );
        final snapshot = jsonDecode(proxied.body) as Map;
        final queues = snapshot['queues'] as Map;
        final cooking = queues['pending_cook'] as List? ?? const [];
        final config = snapshot['config'] as Map;
        final prepEnabled =
            config['enable_prep_workflow'] ?? config['prep_enabled'];
        final configWrite = await _request(
          client,
          lan.resolve('/kds/v2/config'),
          'POST',
          token: token,
          body: {
            'enable_prep_workflow': prepEnabled,
            'prep_enabled': prepEnabled,
          },
        );
        expect(configWrite.statusCode, HttpStatus.ok);
        expect((jsonDecode(configWrite.body) as Map)['code'], 0);
        final afterConfig = await _request(
          client,
          cloud.resolve('/kds/v2/bootstrap'),
          'GET',
          token: token,
        );
        final afterConfigBody = jsonDecode(afterConfig.body) as Map;
        expect(
          (afterConfigBody['config'] as Map)['enable_prep_workflow'],
          prepEnabled,
        );
        final changes = await _request(
          client,
          lan.resolve('/kds/v2/changes?after_seq=0'),
          'GET',
          token: token,
        );
        expect(changes.statusCode, HttpStatus.ok);
        final changesBody = jsonDecode(changes.body) as Map;
        expect(changesBody['code'], 0);
        final events = changesBody['events'] as List? ?? const [];
        expect(events, isNotEmpty, reason: 'debug 库需有真实云端 KDS 事件');

        if (cooking.isNotEmpty) {
          final line = cooking.first as Map;
          final commandId = 'lan-real-${DateTime.now().microsecondsSinceEpoch}';
          final command = <String, Object?>{
            'command_id': commandId,
            'type': 'advance_item',
            'target': {
              'detail_id': line['detail_id'],
              'from_queue': 'pending_cook',
            },
            'quantity': 1,
            'expected_revision': line['local_revision'],
          };
          final first = await _request(
            client,
            lan.resolve('/kds/v2/commands'),
            'POST',
            token: token,
            body: command,
          );
          expect(first.statusCode, HttpStatus.ok);
          expect((jsonDecode(first.body) as Map)['code'], 0);
          final replay = await _request(
            client,
            lan.resolve('/kds/v2/commands'),
            'POST',
            token: token,
            body: command,
          );
          expect(replay.statusCode, HttpStatus.ok);
          expect((jsonDecode(replay.body) as Map)['code'], 0);
          final resolved = await _request(
            client,
            cloud.resolve('/kds/v2/commands/$commandId'),
            'GET',
            token: token,
          );
          expect((jsonDecode(resolved.body) as Map)['status'], 'APPLIED');
        } else {
          final recordedCommand = events.whereType<Map>().firstWhere(
            (event) =>
                '${event['event_id'] ?? ''}'.startsWith('cmd:') &&
                '${event['command_id'] ?? ''}'.isNotEmpty,
            orElse: () => const {},
          );
          expect(
            recordedCommand,
            isNotEmpty,
            reason: '无可推进明细时，debug 库需保留真实已执行命令供解析验证',
          );
          final commandId = recordedCommand['command_id'];
          final cloudResolved = await _request(
            client,
            cloud.resolve('/kds/v2/commands/$commandId'),
            'GET',
            token: token,
          );
          final lanResolved = await _request(
            client,
            lan.resolve('/kds/v2/commands/$commandId'),
            'GET',
            token: token,
          );
          expect(lanResolved.statusCode, cloudResolved.statusCode);
          expect(jsonDecode(lanResolved.body), jsonDecode(cloudResolved.body));
          expect((jsonDecode(lanResolved.body) as Map)['status'], 'APPLIED');
        }

        final socket = await WebSocket.connect(
          lan
              .replace(
                scheme: 'ws',
                path: '/ws/kds/v2',
                queryParameters: {'shop_id': '1'},
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
      } finally {
        await server.close();
        client.close(force: true);
        database.close();
        await temp.delete(recursive: true);
      }
    },
    skip: enabled
        ? false
        : 'Set RUN_REAL_KDS_DEBUG=true with a real device code',
  );
}

Future<void> _cacheCloudToken({
  required int shopId,
  required String deviceCode,
  required String token,
}) async {}

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
