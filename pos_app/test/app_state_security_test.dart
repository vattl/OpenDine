import 'package:admin_panel_flutter/src/core/app_state.dart';
import 'package:admin_panel_flutter/src/core/api_debug_log.dart';
import 'package:admin_panel_flutter/src/core/shop_summary.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shop selection cannot escape the authenticated shop scope', () {
    final state = AppState();
    state.applySession(
      const LoginSession(
        token: 'token',
        scope: 'SHOP',
        permissions: {'order:view'},
        shops: [ShopSummary(id: 1, code: 'S1', name: '一店')],
      ),
    );

    expect(() => state.selectShop(2), throwsArgumentError);
    expect(state.currentShopId, 1);
  });

  test('logout clears interface logs from the previous cashier session', () {
    final store = ApiDebugLogStore.instance;
    store.clear();
    store.add(
      ApiDebugLogEntry(
        id: 'session-request',
        startedAt: DateTime(2026, 8, 8),
        method: 'GET',
        uri: Uri.parse('https://api.test/private'),
        requestHeaders: const {},
        requestBody: '',
        statusCode: 200,
        responseBody: '{}',
        duration: Duration.zero,
        succeeded: true,
        error: '',
      ),
    );

    AppState().logout();

    expect(store.entries, isEmpty);
  });
}
