import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/admin_api_cashier_kds_proxy_client.dart';
import 'package:admin_panel_flutter/src/features/kds_local/sync/cashier_kds_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  test('transparent HTTP proxy forwards token and request identity', () async {
    final transport = FakeHttpTransport({
      'GET /kds/v2/bootstrap': jsonEncode({
        'code': 0,
        'data': {'event_seq': 12},
      }),
    });
    final client = AdminApiCashierKdsProxyClient(
      AdminApiClient(baseUrl: 'http://api.test', transport: transport),
      cashierDeviceCode: 'CASHIER-LOCAL-1',
    );

    final response = await client.proxyKdsHttp(
      const CashierKdsProxyRequest(
        method: 'GET',
        path: '/kds/v2/bootstrap',
        query: {},
        body: {},
        deviceToken: 'cloud-device-token',
        requestId: 'request-1',
      ),
      shopId: 7,
    );

    expect(response.statusCode, 200);
    final request = transport.requests.single;
    expect(request.headers['X-Shop-Id'], '7');
    expect(request.headers['X-Kds-Device-Token'], 'cloud-device-token');
    expect(request.headers['X-KDS-Proxy-Request-Id'], 'request-1');
    expect(request.headers['Via'], 'cashier-lan/1.0');
  });

  test(
    'proxy login forwards the complete KDS authentication request',
    () async {
      final transport = FakeHttpTransport({
        'POST /kds/device/login': jsonEncode({
          'code': 0,
          'data': {'device_code': 'KDS-1', 'device_token': 'cloud-token'},
        }),
      });
      final client = AdminApiCashierKdsProxyClient(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'cashier-session',
          shopId: 7,
        ),
        cashierDeviceCode: 'CASHIER-LOCAL-1',
      );

      final response = await client.proxyDeviceLogin(
        CashierKdsLoginRequest(
          body: const {
            'device_code': 'KDS-1',
            'screen_tag': 'workflow_board',
            'pairing_code': 'ABCDEFGH',
          },
          deviceToken: 'existing-cloud-token',
          requestId: 'login-request-1',
        ),
      );

      expect(response.statusCode, 200);
      final request = transport.requests.single;
      expect(request.uri.path, '/kds/device/login');
      expect(request.headers['X-Kds-Device-Token'], 'existing-cloud-token');
      expect(request.headers.containsKey('X-Kds-Pairing-Secret'), isFalse);
      expect(request.headers['X-KDS-Proxy-Request-Id'], 'login-request-1');
      expect(request.headers['Via'], 'cashier-lan/1.0');
      expect(jsonDecode(request.body!), {
        'device_code': 'KDS-1',
        'screen_tag': 'workflow_board',
        'pairing_code': 'ABCDEFGH',
      });
    },
  );
}
