import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const productionApiBaseUrl = 'http://localhost:8080';
  static const debugApiBaseUrl = String.fromEnvironment(
    'DEBUG_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:18080',
  );
  static const environment = String.fromEnvironment(
    'APP_ENV',
    defaultValue: 'production',
  );

  /// Release binaries are permanently pinned to production. Debug backend
  /// access is opt-in and only available to non-release builds.
  static const apiBaseUrl = kReleaseMode
      ? productionApiBaseUrl
      : environment == 'debug'
      ? debugApiBaseUrl
      : productionApiBaseUrl;

  static const debugBackendEnabled = !kReleaseMode && environment == 'debug';

  /// 高德 Web 服务 Key，用于 Windows 收银端静态道路地图。
  static const amapWebServiceKey = String.fromEnvironment('AMAP_WEB_KEY');

  static String resolveApiBaseUrl({
    required bool releaseMode,
    required String environment,
  }) =>
      isDebugBackendEnabled(releaseMode: releaseMode, environment: environment)
      ? debugApiBaseUrl
      : productionApiBaseUrl;

  static bool isDebugBackendEnabled({
    required bool releaseMode,
    required String environment,
  }) => !releaseMode && environment.trim().toLowerCase() == 'debug';

  static const version = '2.1.16';
  static const buildNumber = 223;
}
