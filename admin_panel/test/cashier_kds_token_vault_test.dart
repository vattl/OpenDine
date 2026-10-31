import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_token_vault.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('platform vault caches and reads a token under an opaque key', () async {
    final storage = _MemorySecureStorage();
    final vault = CashierKdsTokenVault(storage);

    await vault.cacheToken(
      shopId: 7,
      deviceCode: 'KDS-PREP-01',
      token: 'cloud-secret-token',
    );

    expect(
      await vault.readToken(shopId: 7, deviceCode: 'KDS-PREP-01'),
      'cloud-secret-token',
    );
    expect(storage.values.keys.single, isNot(contains('KDS-PREP-01')));
  });

  test('platform vault rejects a silently lost secure write', () async {
    final vault = CashierKdsTokenVault(_DroppingSecureStorage());

    await expectLater(
      vault.cacheToken(shopId: 1, deviceCode: 'KDS-01', token: 'token'),
      throwsStateError,
    );
  });

  test('platform vault deletes a cached device token', () async {
    final storage = _MemorySecureStorage();
    final vault = CashierKdsTokenVault(storage);
    await vault.cacheToken(shopId: 1, deviceCode: 'KDS-01', token: 'token');

    await vault.deleteToken(shopId: 1, deviceCode: 'KDS-01');

    expect(await vault.readToken(shopId: 1, deviceCode: 'KDS-01'), isNull);
  });
}

class _MemorySecureStorage implements CashierKdsSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _DroppingSecureStorage implements CashierKdsSecureStorage {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {}
}
