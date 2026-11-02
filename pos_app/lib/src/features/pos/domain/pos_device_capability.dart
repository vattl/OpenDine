import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 设备与硬件能力环境检测器
/// 负责识别当前设备是否为安卓平板、是否自带摄像头等，为免扫码枪直接使用摄像头扫码提供硬件判断依据。
class PosDeviceEnvironment {
  const PosDeviceEnvironment._();

  /// 测试与自定义环境覆盖开关
  @visibleForTesting
  static bool? debugOverrideIsAndroid;

  @visibleForTesting
  static bool? debugOverrideHasCamera;

  /// 检测当前运行系统是否为 Android
  static bool isAndroid({bool? override}) {
    if (override != null) return override;
    if (debugOverrideIsAndroid != null) return debugOverrideIsAndroid!;
    if (kIsWeb) return false;
    try {
      return defaultTargetPlatform == TargetPlatform.android || Platform.isAndroid;
    } catch (_) {
      return defaultTargetPlatform == TargetPlatform.android;
    }
  }

  /// 检测当前设备是否具备内置摄像头硬件能力
  static bool hasBuiltInCamera({bool? override}) {
    if (override != null) return override;
    if (debugOverrideHasCamera != null) return debugOverrideHasCamera!;
    // Android 设备与大部分平板电脑均配备有内置摄像头（前置或后置）
    return isAndroid();
  }

  /// 检测当前是否为安卓平板设备（Android 系统 且 屏幕视口尺寸达到平板级别）
  /// 标准平板判定：屏幕最短边 (shortestSide) >= 600 dp 或 宽度 >= 600 dp
  static bool isAndroidTablet(
    BuildContext context, {
    bool? overrideIsAndroid,
    double? overrideWidth,
    double? overrideShortestSide,
  }) {
    final isAndroidDevice = isAndroid(override: overrideIsAndroid);
    if (!isAndroidDevice) return false;

    final mediaQuery = MediaQuery.maybeOf(context);
    final width = overrideWidth ?? mediaQuery?.size.width ?? 0;
    final shortestSide = overrideShortestSide ?? mediaQuery?.size.shortestSide ?? width;

    return shortestSide >= 600 || width >= 600;
  }

  /// 综合检测：当前设备是否为安卓平板且自带摄像头
  static bool isAndroidTabletWithCamera(
    BuildContext context, {
    bool? overrideIsAndroid,
    bool? overrideHasCamera,
    double? overrideWidth,
    double? overrideShortestSide,
  }) {
    final isTablet = isAndroidTablet(
      context,
      overrideIsAndroid: overrideIsAndroid,
      overrideWidth: overrideWidth,
      overrideShortestSide: overrideShortestSide,
    );
    final hasCam = hasBuiltInCamera(override: overrideHasCamera);
    return isTablet && hasCam;
  }
}
