import 'package:admin_panel_flutter/src/core/shop_summary.dart';
import 'package:admin_panel_flutter/src/features/auth/data/cashier_account_storage.dart';
import 'package:admin_panel_flutter/src/features/auth/data/cashier_session_storage.dart';
import 'package:admin_panel_flutter/src/features/auth/domain/auth_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashierSessionStorage', () {
    test(
      'persists only the secure session context needed for restore',
      () async {
        final keyValue = MemoryAccountKeyValueStorage();
        final storage = CashierSessionStorage(keyValue);
        const session = LoginSession(
          token: 'jwt-secret-token',
          scope: 'SHOP',
          permissions: {'cashier:operate'},
          shops: [ShopSummary(id: 2, code: 'S2', name: '南湖店')],
          actorName: 'cashier',
        );

        await storage.save(session, selectedShopId: 2);
        final restored = await storage.read();

        expect(restored?.token, 'jwt-secret-token');
        expect(restored?.actorName, 'cashier');
        expect(restored?.selectedShopId, 2);
        expect(restored.toString(), isNot(contains('jwt-secret-token')));
        final raw = await keyValue.read(CashierSessionStorage.storageKey);
        expect(raw, contains('jwt-secret-token'));
        expect(raw, isNot(contains('cashier:operate')));
        expect(raw, isNot(contains('南湖店')));
        expect(raw?.toLowerCase(), isNot(contains('password')));
      },
    );

    test('updates selected shop without weakening the stored token', () async {
      final storage = CashierSessionStorage(MemoryAccountKeyValueStorage());
      const session = LoginSession(
        token: 'token-1',
        scope: 'HQ',
        permissions: {},
        shops: [],
        actorName: 'manager',
      );
      await storage.save(session, selectedShopId: 1);

      await storage.updateSelectedShop(3);

      final restored = await storage.read();
      expect(restored?.token, 'token-1');
      expect(restored?.selectedShopId, 3);
    });

    test('malformed data fails closed and is removed', () async {
      final keyValue = MemoryAccountKeyValueStorage();
      final storage = CashierSessionStorage(keyValue);
      await keyValue.write(CashierSessionStorage.storageKey, '{bad-json');

      expect(await storage.read(), isNull);
      expect(await keyValue.read(CashierSessionStorage.storageKey), isNull);
    });

    test('clear prevents any later restore', () async {
      final storage = CashierSessionStorage(MemoryAccountKeyValueStorage());
      await storage.save(
        const LoginSession(
          token: 'token-1',
          scope: 'SHOP',
          permissions: {},
          shops: [],
        ),
      );

      await storage.clear();

      expect(await storage.read(), isNull);
    });
  });
}
