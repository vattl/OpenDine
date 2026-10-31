import 'dart:convert';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class AccountKeyValueStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureAccountKeyValueStorage implements AccountKeyValueStorage {
  SecureAccountKeyValueStorage([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _android = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  );
  static const _windows = WindowsOptions(useBackwardCompatibility: false);
  final FlutterSecureStorage _storage;
  static final Map<String, String> _memoryStore = {};

  bool get _isTest {
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> read(String key) async {
    if (_isTest) return _memoryStore[key];
    try {
      return await _storage.read(
            key: key,
            aOptions: _android,
            wOptions: _windows,
          ) ??
          _memoryStore[key];
    } catch (_) {
      return _memoryStore[key];
    }
  }

  @override
  Future<void> write(String key, String value) async {
    _memoryStore[key] = value;
    if (_isTest) return;
    try {
      await _storage.write(
        key: key,
        value: value,
        aOptions: _android,
        wOptions: _windows,
      );
    } catch (e) {
      _memoryStore.remove(key);
      rethrow;
    }
  }

  @override
  Future<void> delete(String key) async {
    _memoryStore.remove(key);
    if (_isTest) return;
    try {
      await _storage.delete(
        key: key,
        aOptions: _android,
        wOptions: _windows,
      );
    } catch (e) {
      rethrow;
    }
  }
}

class MemoryAccountKeyValueStorage implements AccountKeyValueStorage {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

class CashierAccountStorage {
  CashierAccountStorage([AccountKeyValueStorage? storage])
      : _storage = storage ?? SecureAccountKeyValueStorage();

  final AccountKeyValueStorage _storage;
  static const _savedAccountsKey = 'saved_cashier_accounts';
  static const _rememberMeKey = 'remember_cashier_account_flag';

  Future<List<String>> getSavedAccounts() async {
    try {
      final raw = await _storage.read(_savedAccountsKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {}
    return const [];
  }

  Future<bool> getRememberMe() async {
    try {
      final raw = await _storage.read(_rememberMeKey);
      if (raw == null) return true;
      return raw == 'true';
    } catch (_) {
      return true;
    }
  }

  Future<void> saveAccount(String username, {required bool remember}) async {
    final clean = username.trim();
    try {
      await _storage.write(
        _rememberMeKey,
        remember ? 'true' : 'false',
      );
      if (!remember || clean.isEmpty) return;
      final existing = await getSavedAccounts();
      final updated = [clean, ...existing.where((e) => e != clean)];
      final capped = updated.length > 5 ? updated.sublist(0, 5) : updated;
      await _storage.write(_savedAccountsKey, jsonEncode(capped));
    } catch (_) {}
  }

  Future<void> removeAccount(String username) async {
    final clean = username.trim();
    try {
      final existing = await getSavedAccounts();
      final updated = existing.where((e) => e != clean).toList(growable: false);
      await _storage.write(_savedAccountsKey, jsonEncode(updated));
    } catch (_) {}
  }
}
