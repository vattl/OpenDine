import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/diagnostics/kds_trace_hub.dart';
import 'package:kds_app/core/diagnostics/kds_trace_models.dart';

void main() {
  setUp(() {
    KdsTraceHub.clear();
  });

  group('KdsTraceHub', () {
    test('records fetch, send, receive and response events', () {
      KdsTraceHub.recordFetch(
        channel: KdsActiveChannel.lan,
        action: 'GET /kds/v2/bootstrap',
        summary: '获取启动数据',
        endpoint: '/kds/v2/bootstrap',
        durationMs: 18,
        statusCode: 200,
        responsePayload: {'code': 0, 'data': {'shop_id': 1}},
      );

      KdsTraceHub.recordSend(
        channel: KdsActiveChannel.lan,
        action: 'POST /kds/v2/commands',
        summary: '发送划菜指令',
        endpoint: '/kds/v2/commands',
        requestPayload: {'command_id': 'cmd-1', 'type': 'item_advance'},
      );

      KdsTraceHub.recordReceive(
        channel: KdsActiveChannel.lan,
        action: 'WS_order_created',
        summary: '收到新订单',
        payload: {'type': 'order_created', 'order_id': 100},
      );

      KdsTraceHub.recordResponse(
        channel: KdsActiveChannel.lan,
        action: 'POST /kds/v2/commands',
        summary: '划菜指令已确认',
        endpoint: '/kds/v2/commands',
        durationMs: 25,
        statusCode: 200,
        responsePayload: {'code': 0},
      );

      // 加上 clear() 插入的系统条目，共有 5 条记录
      final list = KdsTraceHub.entries;
      expect(list.length, greaterThanOrEqualTo(4));

      final fetchEntry = list.firstWhere((e) => e.stage == KdsTraceStage.fetch);
      expect(fetchEntry.action, 'GET /kds/v2/bootstrap');
      expect(fetchEntry.durationMs, 18);
      expect(fetchEntry.isSuccess, isTrue);

      final sendEntry = list.firstWhere((e) => e.stage == KdsTraceStage.send);
      expect(sendEntry.action, 'POST /kds/v2/commands');
      expect(sendEntry.requestPayload, isNotNull);

      final rxEntry = list.firstWhere((e) => e.stage == KdsTraceStage.receive);
      expect(rxEntry.action, 'WS_order_created');
      expect(rxEntry.summary, contains('新订单'));

      final respEntry = list.firstWhere((e) => e.stage == KdsTraceStage.response);
      expect(respEntry.durationMs, 25);
    });

    test('ring buffer does not exceed maxEntries', () {
      for (int i = 0; i < 600; i++) {
        KdsTraceHub.recordSend(
          channel: KdsActiveChannel.cloud,
          action: 'PING_$i',
          summary: 'Send ping $i',
          endpoint: '/ping',
        );
      }
      expect(KdsTraceHub.entries.length, KdsTraceHub.maxEntries);
    });

    test('toJson serializes all fields properly', () {
      final entry = KdsTraceEntry(
        id: 'test-id',
        timestamp: DateTime(2026, 9, 13, 12, 0, 0),
        stage: KdsTraceStage.fetch,
        channel: KdsActiveChannel.lan,
        action: 'BOOTSTRAP',
        summary: 'Test summary',
        durationMs: 12,
        statusCode: 200,
        isSuccess: true,
        endpoint: '/test',
        requestPayload: {'foo': 'bar'},
        responsePayload: {'baz': 123},
        requestId: 'req-abc',
        commandId: 'cmd-xyz',
        deviceCode: 'DEV-99',
        metadata: {'meta': 'data'},
      );

      final json = entry.toJson();
      expect(json['id'], 'test-id');
      expect(json['stage'], 'fetch');
      expect(json['channel'], 'lan');
      expect(json['duration_ms'], 12);
      expect(json['is_success'], isTrue);
      expect(json['request_id'], 'req-abc');
      expect(json['command_id'], 'cmd-xyz');
      expect(json['device_code'], 'DEV-99');
    });
  });
}
