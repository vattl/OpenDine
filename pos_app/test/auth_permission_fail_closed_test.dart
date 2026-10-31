import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/shop_summary.dart';
import 'package:admin_panel_flutter/src/features/auth/data/auth_repository.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  test('empty authorization responses clear login payload privileges', () {
    const login = LoginSession(
      token: 'jwt',
      scope: 'SHOP',
      permissions: {'cashier:operate', 'admin:manage'},
      shops: [ShopSummary(id: 1, code: 'S1', name: '一店')],
    );

    final merged = login.merge(
      permissionData: const {'scope': 'SHOP', 'permissions': <String>[]},
      shopData: const {'shops': <Object>[]},
    );

    expect(merged.permissions, isEmpty);
    expect(merged.shops, isEmpty);
  });

  test(
    'permission lookup failure aborts login instead of trusting payload',
    () async {
      final transport = FakeHttpTransport({
        'POST /adminLogin': jsonEncode({
          'code': 200,
          'data': {
            'token': 'jwt',
            'scope': 'SHOP',
            'permissions': ['cashier:operate'],
          },
        }),
        'GET /admin/me/shops': jsonEncode({
          'code': 200,
          'data': {
            'shops': [
              {'id': 1, 'code': 'S1', 'name': '一店'},
            ],
          },
        }),
      });
      final repository = AuthRepository(
        AdminApiClient(baseUrl: 'https://example.test', transport: transport),
      );

      await expectLater(
        repository.login(username: 'cashier', password: 'secret'),
        throwsA(isA<ApiException>()),
      );
    },
  );
}
