import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionStorage {
  SessionStorage(this._secure, this._prefs);

  final FlutterSecureStorage _secure;
  final SharedPreferences _prefs;

  static const _keyToken = 'kds_device_token';
  static const _keyCloudToken = 'kds_cloud_token';
  static const _keySession = 'kds_session_json';
  static const _keyApiBase = 'kds_api_base';
  static const _keyCloudApiBase = 'kds_cloud_api_base';
  static const _keyConnectionMode = 'kds_connection_mode';
  static const _keyLastShopId = 'kds_last_shop_id';
  static const _keyLastWorkflows = 'kds_last_workflows';
  static const _keyLastDeviceName = 'kds_last_device_name';

  Future<void> saveToken(String token) =>
      _secure.write(key: _keyToken, value: token);

  Future<String?> readToken() => _secure.read(key: _keyToken);

  Future<void> clearToken() => _secure.delete(key: _keyToken);

  /// Removes the duplicate credential persisted by pre cloud-authority builds.
  Future<void> clearCloudToken() => _secure.delete(key: _keyCloudToken);

  Future<void> saveSessionJson(Map<String, dynamic> json) async {
    await _prefs.setString(_keySession, jsonEncode(json));
  }

  Map<String, dynamic>? readSessionJson() {
    final raw = _prefs.getString(_keySession);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSessionJson() => _prefs.remove(_keySession);

  String getApiBase() {
    final raw = _prefs.getString(_keyApiBase);
    return resolveEffectiveApiBase(raw ?? '');
  }

  Future<void> setApiBase(String base) async {
    if (base.trim().isEmpty) {
      await _prefs.remove(_keyApiBase);
      return;
    }
    await _prefs.setString(_keyApiBase, normalizeApiBase(base));
  }

  String getCloudApiBase() {
    final raw = _prefs.getString(_keyCloudApiBase);
    return resolveEffectiveCloudApiBase(raw ?? '');
  }

  Future<void> setCloudApiBase(String base) async {
    if (base.trim().isEmpty) {
      await _prefs.remove(_keyCloudApiBase);
      return;
    }
    await _prefs.setString(_keyCloudApiBase, normalizeApiBase(base));
  }

  String getConnectionModeRaw() {
    return _prefs.getString(_keyConnectionMode) ?? 'cloud_first';
  }

  Future<void> setConnectionModeRaw(String mode) async {
    await _prefs.setString(_keyConnectionMode, mode);
  }

  int? getLastShopId() => _prefs.getInt(_keyLastShopId);

  Future<void> setLastShopId(int shopId) =>
      _prefs.setInt(_keyLastShopId, shopId);

  List<String>? getLastWorkflows() => _prefs.getStringList(_keyLastWorkflows);

  Future<void> setLastWorkflows(List<String> workflows) =>
      _prefs.setStringList(_keyLastWorkflows, workflows);

  String? getLastDeviceName() => _prefs.getString(_keyLastDeviceName);

  Future<void> setLastDeviceName(String name) =>
      _prefs.setString(_keyLastDeviceName, name);

  /// 判定指定 SharedPreferences key 是否属于应当保留的设置项/用户偏好参数
  static bool isPreservedSettingKey(String key) {
    // 明确需要清除的运行时凭证与临时快照缓存
    if (key == _keyToken ||
        key == _keyCloudToken ||
        key == _keySession ||
        key.startsWith('kds_board_snapshot_') ||
        key.startsWith('kds_command_outbox_') ||
        key == 'kds_outbox_migration_meta') {
      return false;
    }
    // 其余关于连接基址、模式、历史参数、后厨偏好设置全部保留
    if (key == _keyApiBase ||
        key == _keyCloudApiBase ||
        key == _keyConnectionMode ||
        key == _keyLastShopId ||
        key == _keyLastWorkflows ||
        key == _keyLastDeviceName ||
        key == 'new_order_sound' ||
        key == 'sync_since_ms' ||
        key.startsWith('kds_')) {
      return true;
    }
    return false;
  }

  Future<void> clearAll() async {
    await clearToken();
    await clearCloudToken();
    await clearSessionJson();
  }
}
