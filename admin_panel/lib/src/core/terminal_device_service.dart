import 'dart:math';

import '../features/auth/data/cashier_account_storage.dart';

/// 收银终端设备注册与标识服务。
///
/// 为收银终端提供全局稳定、跨应用重启一致的 terminalId。
/// 仅当切换实际设备或显式重新注册时变化。
class TerminalDeviceService {
  TerminalDeviceService([AccountKeyValueStorage? storage])
      : _storage = storage ?? SecureAccountKeyValueStorage();

  static final TerminalDeviceService instance = TerminalDeviceService();

  static const storageKey = 'cashier_terminal_id_v1';
  final AccountKeyValueStorage _storage;

  String? _cachedTerminalId;
  bool _explicitlyDisabled = false;

  /// 当前内存缓存的终端编号（同步获取，若尚未初始化可能为 null）。
  String? get currentTerminalId => _cachedTerminalId;

  /// 设置/注入终端编号（用于测试或显式配置）。
  /// 若显式置 null 或空串，记录显式禁用标记，便于测试模拟未初始化状态。
  void setTerminalId(String? id) {
    final clean = (id == null || id.trim().isEmpty) ? null : id.trim();
    _cachedTerminalId = clean;
    _explicitlyDisabled = (clean == null);
  }

  /// 异步读取已持久化的终端编号，若尚未注册则生成稳定终端编号并持久化保存。
  /// 若已被显式置空禁用，返回 null。
  Future<String?> getOrInitializeTerminalId() async {
    if (_cachedTerminalId != null && _cachedTerminalId!.isNotEmpty) {
      return _cachedTerminalId!;
    }
    if (_explicitlyDisabled) {
      return null;
    }
    try {
      final saved = await _storage.read(storageKey);
      if (saved != null && saved.trim().isNotEmpty) {
        _cachedTerminalId = saved.trim();
        return _cachedTerminalId!;
      }
    } catch (_) {}

    // 未找到持久化标识，生成稳定的终端设备编号并持久化
    final generated = _generateTerminalId();
    await registerTerminalId(generated);
    return generated;
  }

  /// 异步注册/更新终端编号并持久化。
  Future<void> registerTerminalId(String terminalId) async {
    final clean = terminalId.trim();
    if (clean.isEmpty) {
      throw ArgumentError('终端编号不能为空');
    }
    _cachedTerminalId = clean;
    _explicitlyDisabled = false;
    try {
      await _storage.write(storageKey, clean);
    } catch (_) {}
  }

  /// 生成基于时间戳与随机数的稳定终端标识符。
  String _generateTerminalId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'TERM-$now-$rand'.toUpperCase();
  }
}
