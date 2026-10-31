import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/kds_api_client.dart';
import 'package:kds_app/core/lan_v2/kds_v2_client.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';

void main() {
  test('STALE proxy headers reach bootstrap and force non-realtime state',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers
        ..set('X-KDS-Cache', 'STALE')
        ..set('X-KDS-Served-Via', 'lan-cache')
        ..set('X-KDS-Authority-Cursor', '88')
        ..set('X-KDS-Cached-At', '1700000000000')
        ..set('Age', '37');
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'code': 0,
        'msg': 'ok',
        'data': {
          'protocol_version': 2,
          'shop_id': 1,
          'event_seq': 88,
          'queues': {
            'pending_cook': [
              {
                'detail_id': 11,
                'order_id': 21,
                'dish_id': 31,
                'dish_name': '真实缓存菜品',
                'line_quantity': 1,
                'refunded_quantity': 0,
                'prep_remaining': 0,
                'cook_remaining': 1,
                'ready_remaining': 1,
                'local_revision': 4,
                'order_revision': 6,
                'fulfillment_bucket': 'dine_in',
                'table_number': 'A1',
                'order_no': 'DEBUG-21',
                'specification': '',
                'unit': '份',
                'remark': '',
                'created_at_ms': 1699999999000,
                'held': false,
                'rushed': false,
                'lacked': false,
                'removed': false,
                'workflow_queue': 'pending_cook',
              },
            ],
          },
          'queue_counts': {'pending_cook': 1},
          'stats': {},
          'fixed_catalog': [],
          'config': {},
        },
      }));
      await request.response.close();
    });
    final api = KdsApiClient(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getToken: () => 'cloud-issued-token',
    );
    final client = KdsV2Client(KdsV2HttpAdapter(api));

    final bootstrap = await client.bootstrap();
    expect(bootstrap.isStale, isTrue);
    expect(bootstrap.servedVia, 'lan-cache');
    expect(bootstrap.cacheAgeSeconds, 37);
    expect(bootstrap.cachedAtMs, 1700000000000);
    expect(bootstrap.authorityCursor, 88);

    final controller = KdsV2Controller(client, expectedShopId: 1);
    controller.setConnected(true);
    await controller.start();
    expect(controller.state.isStale, isTrue);
    expect(controller.state.connected, isFalse);
    expect(controller.state.realtimeReady, isFalse);
    expect(controller.state.canMutate, isTrue,
        reason: '缓存看板允许操作落入 outbox，但不得作为实时成功发送');
  });
}
