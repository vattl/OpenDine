import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const productionApiBaseUrl = 'https://www.laofei.com.cn';
  static const debugApiBaseUrl = 'http://127.0.0.1:18080';
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

  static const version = '2.0.1';
}
