import 'package:shared_preferences/shared_preferences.dart';

/// 设备码持久化（登出后仍保留，便于下次自动识别）
class DeviceCodePrefs {
  DeviceCodePrefs(this._prefs);

  final SharedPreferences _prefs;

  static const _lastCodeKey = 'kds_last_device_code';
  static const _lastHwKey = 'kds_last_device_hw_id';
  static const _hwPrefix = 'kds_device_code_hw_';
  static const _installIdKey = 'kds_install_hardware_id';

  static Future<DeviceCodePrefs> load() async =>
      DeviceCodePrefs(await SharedPreferences.getInstance());

  String? get lastDeviceCode => _prefs.getString(_lastCodeKey)?.trim();

  String? get lastHardwareId => _prefs.getString(_lastHwKey)?.trim();

  String? codeForHardware(String hardwareId) =>
      _prefs.getString('$_hwPrefix$hardwareId')?.trim();

  String? get orCreateInstallId {
    final existing = _prefs.getString(_installIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    return null;
  }

  Future<String> ensureInstallId(String Function() generate) async {
    final existing = orCreateInstallId;
    if (existing != null) return existing;
    final id = generate();
    await _prefs.setString(_installIdKey, id);
    return id;
  }

  Future<void> saveBinding({
    required String deviceCode,
    required String hardwareId,
  }) async {
    final code = deviceCode.trim();
    if (code.isEmpty || hardwareId.isEmpty) return;
    await _prefs.setString(_lastCodeKey, code);
    await _prefs.setString(_lastHwKey, hardwareId);
    await _prefs.setString('$_hwPrefix$hardwareId', code);
  }
}
