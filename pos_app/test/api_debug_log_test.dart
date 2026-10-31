import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/core/api_debug_log.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  late ApiDebugLogStore store;

  setUp(() {
    store = ApiDebugLogStore(maxEntries: 10);
  });

  test('records successful requests and redacts sensitive values', () async {
    final transport = FakeHttpTransport({
      'POST /admin/modifyPassword': jsonEncode({
        'code': 200,
        'data': {'accessToken': 'response-secret', 'updated': true},
      }),
    });
    final client = AdminApiClient(
      baseUrl: 'https://api.example.com',
      transport: transport,
      token: 'bearer-secret',
      shopId: 7,
      debugLog: store,
    );

    await client.post(
      adminModifyPasswordEndpoint,
      body: const {
        'userName': 'cashier',
        'newPassword': 'password-secret',
        'apiV3Key': 'merchant-api-v3-secret',
      },
    );

    expect(store.entries, hasLength(1));
    final entry = store.entries.single;
    expect(entry.method, 'POST');
    expect(entry.uri.path, '/admin/modifyPassword');
    expect(entry.statusCode, 200);
    expect(entry.succeeded, isTrue);
    expect(entry.duration, isNotNull);
    expect(entry.requestHeaders['Authorization'], ApiDebugLogStore.redacted);
    expect(entry.requestBody, contains('cashier'));
    expect(entry.requestBody, isNot(contains('password-secret')));
    expect(entry.requestBody, isNot(contains('merchant-api-v3-secret')));
    expect(entry.responseBody, isNot(contains('response-secret')));
  });

  test('records business errors with the original response envelope', () async {
    final transport = FakeHttpTransport({
      'GET /admin/category/listAll': jsonEncode({
        'code': 40021,
        'msg': '支付渠道配置错误',
      }),
    });
    final client = AdminApiClient(
      baseUrl: 'https://api.example.com',
      transport: transport,
      token: 'token',
      shopId: 7,
      debugLog: store,
    );

    await expectLater(
      client.get(categoryListAllEndpoint),
      throwsA(isA<ApiException>()),
    );

    final entry = store.entries.single;
    expect(entry.statusCode, 200);
    expect(entry.succeeded, isFalse);
    expect(entry.responseBody, contains('支付渠道配置错误'));
    expect(entry.error, contains('支付渠道配置错误'));
  });

  test('keeps only the configured number of newest entries', () async {
    final limitedStore = ApiDebugLogStore(maxEntries: 2);
    final transport = FakeHttpTransport({
      'GET /admin/category/listAll': jsonEncode({'code': 200, 'data': {}}),
    });
    final client = AdminApiClient(
      baseUrl: 'https://api.example.com',
      transport: transport,
      shopId: 7,
      debugLog: limitedStore,
    );

    await client.get(categoryListAllEndpoint, query: const {'attempt': 1});
    await client.get(categoryListAllEndpoint, query: const {'attempt': 2});
    await client.get(categoryListAllEndpoint, query: const {'attempt': 3});

    expect(limitedStore.entries, hasLength(2));
    expect(limitedStore.entries.first.uri.queryParameters['attempt'], '3');
    expect(limitedStore.entries.last.uri.queryParameters['attempt'], '2');
  });
}
