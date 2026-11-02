import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_command_service.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_lan_server.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test(
    '500 active orders keep command bootstrap and localhost WS within budgets',
    () async {
      final database = CashierKdsDatabase.inMemory();
      final receipts = <CashierOrderReceipt>[];
      final seedWatch = Stopwatch()..start();
      for (var index = 0; index < 500; index++) {
        receipts.add(_create(database, 'order-$index', 1000 + index));
      }
      seedWatch.stop();
      final commands = LocalKdsCommandService(database);
      final revisions = {
        for (final line
            in database
                .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
                .lines)
          line.orderId: line.orderRevision,
      };
      final commandSamples = <int>[];
      for (var index = 0; index < 30; index++) {
        final stopwatch = Stopwatch()..start();
        commands.execute(
          LocalKdsCommand(
            commandId: 'benchmark-rush-$index',
            type: LocalKdsCommandType.rushOrder,
            shopId: 1,
            target: LocalKdsCommandTarget(orderId: receipts[index].orderId),
            expectedRevision: revisions[receipts[index].orderId],
            occurredAtMs: 5000 + index,
          ),
        );
        stopwatch.stop();
        commandSamples.add(stopwatch.elapsedMicroseconds);
      }
      expect(_p95Ms(commandSamples), lessThanOrEqualTo(100));

      final server = CashierKdsLanServer(
        database,
        cloudAuthorityMode: false,
      );
      await server.start(address: InternetAddress.loopbackIPv4, port: 0);
      server.setActiveShop(1);
      server.upsertBoundDevice(
        shopId: 1,
        deviceCode: 'BENCH-KDS',
        deviceName: 'BENCH-KDS',
        screenTag: 'workflow_board',
      );
      server.upsertBoundDevice(
        shopId: 1,
        deviceCode: 'BENCH-KDS-2',
        deviceName: 'BENCH-KDS-2',
        screenTag: 'workflow_board',
      );
      final client = HttpClient();
      final login = await _request(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {'device_code': 'BENCH-KDS'},
      );
      final token = (login['data'] as Map)['device_token'] as String;
      final secondLogin = await _request(
        client,
        server,
        'POST',
        '/kds/device/login',
        body: {
          'device_code': 'BENCH-KDS-2',
        },
      );
      final secondToken =
          (secondLogin['data'] as Map)['device_token'] as String;
      final bootstrapSamples = <int>[];
      for (var index = 0; index < 10; index++) {
        final stopwatch = Stopwatch()..start();
        final response = await _request(
          client,
          server,
          'GET',
          '/kds/v2/bootstrap',
          token: token,
        );
        stopwatch.stop();
        expect(((response['data'] as Map)['patches'] as List), hasLength(500));
        bootstrapSamples.add(stopwatch.elapsedMicroseconds);
      }
      expect(_p95Ms(bootstrapSamples), lessThanOrEqualTo(1000));

      final ws = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$token',
      );
      final secondWs = await WebSocket.connect(
        'ws://127.0.0.1:${server.port}/ws/kds/v2?token=$secondToken',
      );
      final iterator = StreamIterator<dynamic>(ws);
      final secondIterator = StreamIterator<dynamic>(secondWs);
      ws.add('ping');
      secondWs.add('ping');
      expect(
        await iterator.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect(
        await secondIterator.moveNext().timeout(const Duration(seconds: 2)),
        isTrue,
      );
      expect('${iterator.current}', contains('"type":"pong"'));
      expect('${secondIterator.current}', contains('"type":"pong"'));
      expect(server.connectedDeviceCount, 2);
      final wsSamples = <int>[];
      for (var index = 0; index < 20; index++) {
        final next = iterator.moveNext();
        final secondNext = secondIterator.moveNext();
        final stopwatch = Stopwatch()..start();
        server.broadcastNewOrder(1, receipts[index]);
        final received = await Future.wait([next, secondNext]);
        expect(received, everyElement(isTrue));
        stopwatch.stop();
        wsSamples.add(stopwatch.elapsedMicroseconds);
      }
      expect(_p95Ms(wsSamples), lessThanOrEqualTo(200));
      debugPrint(
        'seed=${seedWatch.elapsedMilliseconds}ms '
        'commandP95=${_p95Ms(commandSamples)}ms '
        'bootstrapP95=${_p95Ms(bootstrapSamples)}ms '
        'wsP95=${_p95Ms(wsSamples)}ms',
      );
      await iterator.cancel();
      await secondIterator.cancel();
      client.close(force: true);
      await server.close();
      database.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    '10k outbox recovery and selection do not block a command',
    () async {
      final root = await Directory.systemTemp.createTemp('kds-outbox-bench-');
      addTearDown(() => root.delete(recursive: true));
      final path = '${root.path}${Platform.pathSeparator}bench.sqlite';
      final database = CashierKdsDatabase.open(path);
      final order = _create(database, 'real-order', 1000);
      final orderRevision = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single
          .orderRevision;
      final raw = sqlite3.open(path);
      raw.execute('BEGIN IMMEDIATE');
      for (var index = 0; index < 10000; index++) {
        raw.execute(
          'INSERT INTO cloud_outbox '
          '(event_id, shop_id, event_type, aggregate_key, aggregate_sequence, '
          'payload_json, state, attempt_count, next_attempt_at_ms, created_at_ms, updated_at_ms) '
          'VALUES (?, 1, ?, ?, 1, ?, ?, 1, 0, ?, ?)',
          [
            'bulk-$index',
            'kds_state_changed',
            'bulk:$index',
            '{}',
            index.isEven ? 'retry_wait' : 'pending',
            2000 + index,
            2000 + index,
          ],
        );
      }
      raw.execute('COMMIT');
      raw.close();

      final selectWatch = Stopwatch()..start();
      final batches = database.readDueCloudEventBatches(nowMs: 20000);
      selectWatch.stop();
      expect(batches, hasLength(4));
      database.retryAllUndeliveredCloudEvents(nowMs: 20000);
      final commandWatch = Stopwatch()..start();
      LocalKdsCommandService(database).execute(
        LocalKdsCommand(
          commandId: 'after-10k',
          type: LocalKdsCommandType.rushOrder,
          shopId: 1,
          target: LocalKdsCommandTarget(orderId: order.orderId),
          expectedRevision: orderRevision,
          occurredAtMs: 21000,
        ),
      );
      commandWatch.stop();
      expect(selectWatch.elapsedMilliseconds, lessThanOrEqualTo(1000));
      expect(commandWatch.elapsedMilliseconds, lessThanOrEqualTo(100));
      database.close();
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

CashierOrderReceipt _create(CashierKdsDatabase database, String id, int at) =>
    database.createOrder(
      CashierOrderDraft(
        shopId: 1,
        tableNumber: '$at',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: at,
        lines: const [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: id,
    );

double _p95Ms(List<int> microseconds) {
  final sorted = [...microseconds]..sort();
  final index = ((sorted.length * .95).ceil() - 1).clamp(0, sorted.length - 1);
  return sorted[index] / 1000;
}

Future<Map<String, Object?>> _request(
  HttpClient client,
  CashierKdsLanServer server,
  String method,
  String path, {
  Map<String, Object?>? body,
  String? token,
}) async {
  final request = await client.openUrl(
    method,
    Uri.parse('http://127.0.0.1:${server.port}$path'),
  );
  request.headers.contentType = ContentType.json;
  if (token != null) request.headers.set('X-Kds-Device-Token', token);
  if (body != null) request.write(jsonEncode(body));
  final response = await request.close();
  final text = await utf8.decoder.bind(response).join();
  expect(response.statusCode, 200, reason: text);
  return (jsonDecode(text) as Map).cast<String, Object?>();
}
