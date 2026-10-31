import 'dart:convert';

import '../domain/auth_models.dart';
import 'cashier_account_storage.dart';

class PersistedCashierSession {
  const PersistedCashierSession({
    required this.token,
    this.actorName = '',
    this.selectedShopId,
  });

  final String token;
  final String actorName;
  final int? selectedShopId;

  @override
  String toString() =>
      'PersistedCashierSession(actorName: $actorName, selectedShopId: $selectedShopId, token: <redacted>)';
}

/// Stores only the credential and non-authoritative UI context required to
/// restore a cashier session. Permissions and shops are always reloaded from
/// the server before the session becomes authenticated.
class CashierSessionStorage {
  CashierSessionStorage([AccountKeyValueStorage? storage])
    : _storage = storage ?? SecureAccountKeyValueStorage();

  static const storageKey = 'cashier_session_v1';
  static const _version = 1;

  final AccountKeyValueStorage _storage;

  Future<PersistedCashierSession?> read() async {
    final raw = await _storage.read(storageKey);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('not an object');
      final map = decoded.cast<String, Object?>();
      final version = _int(map['version']);
      final token = '${map['token'] ?? ''}'.trim();
      if (version != _version || token.isEmpty || token.length > 8192) {
        throw const FormatException('invalid session');
      }
      final selectedShopId = _positiveInt(map['selected_shop_id']);
      return PersistedCashierSession(
        token: token,
        actorName: '${map['actor_name'] ?? ''}'.trim(),
        selectedShopId: selectedShopId,
      );
    } catch (_) {
      await clear();
      return null;
    }
  }

  Future<void> save(LoginSession session, {int? selectedShopId}) async {
    final token = session.token.trim();
    if (token.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(
      storageKey,
      jsonEncode({
        'version': _version,
        'token': token,
        if (session.actorName.trim().isNotEmpty)
          'actor_name': session.actorName.trim(),
        if (selectedShopId != null && selectedShopId > 0)
          'selected_shop_id': selectedShopId,
      }),
    );
  }

  Future<void> updateSelectedShop(int shopId) async {
    if (shopId <= 0) return;
    final current = await read();
    if (current == null) return;
    await _storage.write(
      storageKey,
      jsonEncode({
        'version': _version,
        'token': current.token,
        if (current.actorName.isNotEmpty) 'actor_name': current.actorName,
        'selected_shop_id': shopId,
      }),
    );
  }

  Future<void> clear() async {
    await _storage.delete(storageKey);
    final lingering = await _storage.read(storageKey);
    if (lingering != null && lingering.trim().isNotEmpty) {
      throw StateError('安全凭据清除失败: 令牌残留');
    }
  }
}

int? _positiveInt(Object? value) {
  final parsed = _int(value);
  return parsed != null && parsed > 0 ? parsed : null;
}

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}
