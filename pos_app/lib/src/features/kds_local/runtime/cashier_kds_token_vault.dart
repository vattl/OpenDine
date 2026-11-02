import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CashierKdsSecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformCashierKdsSecureStorage implements CashierKdsSecureStorage {
  PlatformCashierKdsSecureStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _android = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: false,
  );
  static const _windows = WindowsOptions(useBackwardCompatibility: false);
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) =>
      _storage.read(key: key, aOptions: _android, wOptions: _windows);

  @override
  Future<void> write(String key, String value) => _storage.write(
    key: key,
    value: value,
    aOptions: _android,
    wOptions: _windows,
  );

  @override
  Future<void> delete(String key) =>
      _storage.delete(key: key, aOptions: _android, wOptions: _windows);
}

class CashierKdsTokenVault {
  CashierKdsTokenVault([CashierKdsSecureStorage? storage])
    : _storage = storage ?? PlatformCashierKdsSecureStorage();

  final CashierKdsSecureStorage _storage;

  Future<void> cacheToken({
    required int shopId,
    required String deviceCode,
    required String token,
  }) async {
    final key = _key(shopId, deviceCode);
    if (token.isEmpty || token.length > 4096) {
      throw ArgumentError.value(token.length, 'token', 'invalid token length');
    }
    await _storage.write(key, token);
    final persisted = await _storage.read(key);
    if (persisted == null || !_constantTimeEquals(persisted, token)) {
      throw StateError('KDS device token was not persisted securely');
    }
  }

  Future<String?> readToken({
    required int shopId,
    required String deviceCode,
  }) => _storage.read(_key(shopId, deviceCode));

  Future<void> deleteToken({required int shopId, required String deviceCode}) =>
      _storage.delete(_key(shopId, deviceCode));

  String _key(int shopId, String deviceCode) {
    final normalized = deviceCode.trim();
    if (shopId <= 0 || normalized.isEmpty || normalized.length > 64) {
      throw ArgumentError('invalid KDS device identity');
    }
    final identityHash = sha256
        .convert(utf8.encode('$shopId:$normalized'))
        .toString();
    return 'cashier_kds_device_token_v1_$identityHash';
  }

  bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var difference = leftBytes.length ^ rightBytes.length;
    final maxLength = leftBytes.length > rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var index = 0; index < maxLength; index++) {
      final leftByte = index < leftBytes.length ? leftBytes[index] : 0;
      final rightByte = index < rightBytes.length ? rightBytes[index] : 0;
      difference |= leftByte ^ rightByte;
    }
    return difference == 0;
  }
}
