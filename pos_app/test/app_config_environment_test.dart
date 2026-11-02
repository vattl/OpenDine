import 'package:admin_panel_flutter/src/core/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig API environment isolation', () {
    test('production is the safe default for development builds', () {
      expect(
        AppConfig.resolveApiBaseUrl(releaseMode: false, environment: ''),
        AppConfig.productionApiBaseUrl,
      );
    });

    test('explicit debug environment uses the fixed local backend', () {
      expect(
        AppConfig.resolveApiBaseUrl(releaseMode: false, environment: 'debug'),
        AppConfig.debugApiBaseUrl,
      );
    });

    test('release builds ignore a requested debug environment', () {
      expect(
        AppConfig.resolveApiBaseUrl(releaseMode: true, environment: 'debug'),
        AppConfig.productionApiBaseUrl,
      );
      expect(
        AppConfig.isDebugBackendEnabled(
          releaseMode: true,
          environment: 'debug',
        ),
        isFalse,
      );
    });

    test('unknown environments fail closed to production', () {
      expect(
        AppConfig.resolveApiBaseUrl(releaseMode: false, environment: 'staging'),
        AppConfig.productionApiBaseUrl,
      );
    });
  });
}
