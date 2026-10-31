import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/api/kds_api.dart';
import 'package:kds_app/core/api/kds_api_client.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';

void main() {
  test('health validates protocol sqlite and authoritative primary node',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'code': 0,
        'data': {
          'protocol_version': 2,
          'shop_id': 7,
          'server_time_ms': 1786608000000,
          'sqlite': {'status': 'ok'},
          'primary_node': {'role': 'primary', 'authoritative': true},
        },
      }));
      await request.response.close();
    });
    final api = KdsApi(KdsApiClient(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getToken: () => null,
    ));

    final health = await api.health();

    expect(health.shopId, 7);
    expect(health.ready, isTrue);
  });

  test('health rejects a degraded local database', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'code': 0,
        'data': {
          'protocol_version': 2,
          'shop_id': 7,
          'sqlite': {'status': 'degraded'},
          'primary_node': {'role': 'primary', 'authoritative': true},
        },
      }));
      await request.response.close();
    });
    final api = KdsApi(KdsApiClient(
      getBaseUrl: () => 'http://127.0.0.1:${server.port}',
      getToken: () => null,
    ));

    await expectLater(api.health(), throwsA(isA<ApiException>()));
  });

  test('LAN device login sends the cashier one-time pairing code', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Map<String, dynamic> requestBody;
    server.listen((request) async {
      requestBody = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {
            'protocol_version': 2,
            'id': 1,
            'shop_id': 7,
            'device_code': 'KDS-E2E-01',
            'device_name': '后厨屏',
            'device_token': 'lan-device-token',
            'screen_tag': 'workflow_board',
            'workflows': ['prep', 'cook', 'serve'],
          },
        }),
      );
      await request.response.close();
    });
    final api = KdsApi(
      KdsApiClient(
        getBaseUrl: () => 'http://127.0.0.1:${server.port}',
        getToken: () => null,
      ),
    );

    final device = await api.login(
      deviceCode: 'KDS-E2E-01',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.prep, KdsWorkflow.cook, KdsWorkflow.serve],
      pairingCode: '123456',
    );

    expect(requestBody['pairing_code'], '123456');
    expect(requestBody, isNot(contains('shop_id')));
    expect(device.shopId, 7);
    expect(device.deviceToken, 'lan-device-token');
  });

  test('LAN device login succeeds without pairing_code when pre-bound',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    late Map<String, dynamic> requestBody;
    server.listen((request) async {
      requestBody = Map<String, dynamic>.from(
        jsonDecode(await utf8.decoder.bind(request).join()) as Map,
      );
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {
            'protocol_version': 2,
            'id': 1,
            'shop_id': 7,
            'device_code': 'KDS-E4B97C2A',
            'device_name': '后厨主屏',
            'device_token': 'lan-device-token-bound',
            'screen_tag': 'workflow_board',
            'workflows': ['prep', 'cook', 'serve'],
          },
        }),
      );
      await request.response.close();
    });
    final api = KdsApi(
      KdsApiClient(
        getBaseUrl: () => 'http://127.0.0.1:${server.port}',
        getToken: () => null,
      ),
    );

    final device = await api.login(
      deviceCode: 'KDS-E4B97C2A',
      screenTag: KdsScreenTag.workflowBoard,
      workflows: const [KdsWorkflow.prep, KdsWorkflow.cook, KdsWorkflow.serve],
    );

    expect(requestBody, isNot(contains('pairing_code')));
    expect(requestBody['device_code'], 'KDS-E4B97C2A');
    expect(device.deviceToken, 'lan-device-token-bound');
  });

  test('LAN login throws friendly ApiException when device is unbound (403)',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.statusCode = 403;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 403,
          'msg': '设备未绑定，请先在收银端绑定此设备编码',
        }),
      );
      await request.response.close();
    });
    final api = KdsApi(
      KdsApiClient(
        getBaseUrl: () => 'http://127.0.0.1:${server.port}',
        getToken: () => null,
      ),
    );

    expect(
      () => api.login(
        deviceCode: 'KDS-UNBOUND-99',
        screenTag: KdsScreenTag.workflowBoard,
      ),
      throwsA(isA<ApiException>().having(
        (e) => e.message,
        'message',
        contains('设备未绑定'),
      )),
    );
  });

  test('LAN login accepts cashier device response without numeric id',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {
            'protocol_version': 2,
            'shop_id': 1,
            'device_code': 'KDS-LAN-01',
            'device_name': 'KDS-LAN-01',
            'device_token': 'cashier-token',
            'screen_tag': 'workflow_board',
            'workflows': ['prep', 'cook', 'serve'],
          },
        }),
      );
      await request.response.close();
    });
    final api = KdsApi(
      KdsApiClient(
        getBaseUrl: () => 'http://127.0.0.1:${server.port}',
        getToken: () => null,
      ),
    );

    final device = await api.login(
      deviceCode: 'KDS-LAN-01',
      screenTag: KdsScreenTag.workflowBoard,
    );

    expect(device.id, 0);
    expect(device.deviceCode, 'KDS-LAN-01');
    expect(device.deviceToken, 'cashier-token');
  });

  test('device login sends one-time pairing_code in original request body',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, dynamic>? requestBody;
    server.listen((request) async {
      requestBody = jsonDecode(await utf8.decoder.bind(request).join())
          as Map<String, dynamic>;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {
            'protocol_version': 2,
            'shop_id': 7,
            'device_code': 'KDS-E2E-01',
            'device_token': 'lan-device-token',
            'screen_tag': 'workflow_board',
          },
        }),
      );
      await request.response.close();
    });
    final api = KdsApi(
      KdsApiClient(
        getBaseUrl: () => 'http://127.0.0.1:${server.port}',
        getToken: () => null,
      ),
    );

    await api.login(
      deviceCode: 'KDS-E2E-01',
      screenTag: KdsScreenTag.workflowBoard,
      pairingCode: 'ABCDEFGH',
    );

    expect(requestBody?['pairing_code'], 'ABCDEFGH');
  });

  test('device login never sends retired X-Kds-Pairing-Secret header',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var headerSeen = false;
    server.listen((request) async {
      headerSeen = request.headers.value('X-Kds-Pairing-Secret') != null;
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {
            'protocol_version': 2,
            'shop_id': 7,
            'device_code': 'KDS-E2E-01',
            'device_token': 'lan-device-token',
            'screen_tag': 'workflow_board',
          },
        }),
      );
      await request.response.close();
    });
    final api = KdsApi(
      KdsApiClient(
        getBaseUrl: () => 'http://127.0.0.1:${server.port}',
        getToken: () => null,
      ),
    );

    await api.login(
      deviceCode: 'KDS-E2E-01',
      screenTag: KdsScreenTag.workflowBoard,
    );

    expect(headerSeen, isFalse);
  });

  test('heartbeat carries X-Kds-Device-Token header', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    String? deviceTokenHeader;
    server.listen((request) async {
      deviceTokenHeader = request.headers.value('X-Kds-Device-Token');
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'code': 0,
          'data': {'protocol_version': 2},
        }),
      );
      await request.response.close();
    });
    final api = KdsApi(
      KdsApiClient(
        getBaseUrl: () => 'http://127.0.0.1:${server.port}',
        getToken: () => 'bound-device-token',
      ),
    );

    await api.heartbeat('KDS-E2E-01');

    expect(deviceTokenHeader, 'bound-device-token');
  });
}
