import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:kds_app/core/device/device_code_prefs.dart';
import 'package:uuid/uuid.dart';

enum DeviceCodeOrigin {
  none,
  savedSession,
  hardwareBinding,
  autoDetected,
}

class DeviceCodeResolution {
  const DeviceCodeResolution({
    required this.code,
    required this.origin,
    this.hardwareId,
  });

  final String code;
  final DeviceCodeOrigin origin;
  final String? hardwareId;

  bool get hasCode => code.isNotEmpty;

  String get originLabel => switch (origin) {
        DeviceCodeOrigin.savedSession => '已识别（本机硬件设备码）',
        DeviceCodeOrigin.hardwareBinding => '已识别（本机硬件设备码）',
        DeviceCodeOrigin.autoDetected => '已识别（本机硬件唯一设备码）',
        DeviceCodeOrigin.none => '硬件识别中',
      };

  static const empty =
      DeviceCodeResolution(code: '', origin: DeviceCodeOrigin.none);
}

class KdsDeviceCodeResolver {
  KdsDeviceCodeResolver({DeviceInfoPlugin? deviceInfo})
      : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;
  static const _uuid = Uuid();

  /// 提取不可变的物理硬件与网卡指纹特征（重启设备/重启电脑完全不变）
  Future<String> hardwareId(DeviceCodePrefs prefs) async {
    final parts = <String>[];

    // 1. 网络接口网卡特征（MAC / 物理网卡名）
    try {
      if (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST')) {
        final interfaces = await NetworkInterface.list(
          includeLoopback: false,
          includeLinkLocal: false,
        ).timeout(const Duration(milliseconds: 500), onTimeout: () => []);
        final interfaceNames = interfaces.map((i) => i.name.trim()).toList()
          ..sort();
        if (interfaceNames.isNotEmpty) {
          parts.add('NET:${interfaceNames.join(",")}');
        }
      }
    } catch (_) {}

    // 2. 操作系统与主板/固件硬件指纹
    try {
      if (!kIsWeb && !Platform.environment.containsKey('FLUTTER_TEST')) {
        if (defaultTargetPlatform == TargetPlatform.windows) {
          final win = await _deviceInfo.windowsInfo;
          final devId = win.deviceId.trim();
          if (devId.isNotEmpty) parts.add('WIN_ID:$devId');
          parts.add('WIN_NAME:${win.computerName}');
          parts.add('WIN_CORES:${win.numberOfCores}');
        } else if (defaultTargetPlatform == TargetPlatform.android) {
          final info = await _deviceInfo.androidInfo;
          final id = info.id.trim();
          if (id.isNotEmpty && id.toLowerCase() != 'unknown') {
            parts.add('AND_ID:$id');
          }
          final fingerprint = info.fingerprint.trim();
          if (fingerprint.isNotEmpty && fingerprint.toLowerCase() != 'unknown') {
            parts.add('AND_FP:$fingerprint');
          }
          final hardware = info.hardware.trim();
          if (hardware.isNotEmpty && hardware.toLowerCase() != 'unknown') {
            parts.add('AND_HW:$hardware');
          }
          final model = info.model.trim();
          if (model.isNotEmpty && model.toLowerCase() != 'unknown') {
            parts.add('AND_MODEL:$model');
          }
          final brand = info.brand.trim();
          if (brand.isNotEmpty && brand.toLowerCase() != 'unknown') {
            parts.add('AND_BRAND:$brand');
          }
          final board = info.board.trim();
          if (board.isNotEmpty && board.toLowerCase() != 'unknown') {
            parts.add('AND_BOARD:$board');
          }
        } else if (defaultTargetPlatform == TargetPlatform.linux) {
          final linux = await _deviceInfo.linuxInfo;
          final machineId = linux.machineId?.trim();
          if (machineId != null && machineId.isNotEmpty) {
            parts.add('LINUX_ID:$machineId');
          }
        } else if (defaultTargetPlatform == TargetPlatform.macOS) {
          final mac = await _deviceInfo.macOsInfo;
          final sysGuid = mac.systemGUID?.trim();
          if (sysGuid != null && sysGuid.isNotEmpty) {
            parts.add('MAC_GUID:$sysGuid');
          }
        }
      }
    } catch (_) {}

    // 3. 若提取到了不可变硬件特征，直接返回组合特征
    if (parts.isNotEmpty) {
      return parts.join('|');
    }

    // 4. 极端兜底：本地安装唯一持久化 ID
    return prefs.ensureInstallId(() => _uuid.v4());
  }

  /// 使用 SHA-256 特殊确定性算法将硬件特征转换为固定唯一的设备码
  static String formatAutoCode(String hardwareId) {
    if (hardwareId.trim().isEmpty) return 'KDS-AUTO';
    // 使用 SHA-256 计算硬件指纹的高熵哈希
    final bytes = utf8.encode(hardwareId.trim());
    final digest = sha256.convert(bytes).toString().toUpperCase();
    final suffix = digest.length >= 8 ? digest.substring(0, 8) : digest;
    return 'KDS-$suffix';
  }

  /// 解析本机唯一设备码：基于硬件特征计算，不可人工篡改，重启电脑/设备保持一致
  Future<DeviceCodeResolution> resolve({String? sessionDeviceCode}) async {
    final prefs = await DeviceCodePrefs.load();
    final hwId = await hardwareId(prefs);
    final autoCode = formatAutoCode(hwId);

    // 自动缓存硬件绑定记录
    await prefs.saveBinding(deviceCode: autoCode, hardwareId: hwId);

    return DeviceCodeResolution(
      code: autoCode,
      origin: DeviceCodeOrigin.autoDetected,
      hardwareId: hwId,
    );
  }

  Future<void> persistSuccessfulLogin(String deviceCode) async {
    final prefs = await DeviceCodePrefs.load();
    final hwId = await hardwareId(prefs);
    await prefs.saveBinding(deviceCode: deviceCode, hardwareId: hwId);
  }
}

