import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/device/device_code_prefs.dart';
import 'package:kds_app/core/device/kds_device_code_resolver.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('KdsDeviceCodeResolver.formatAutoCode', () {
    test('uses deterministic SHA-256 8-char uppercase hex of hardware seed', () {
      final seed = 'WIN_ID:guid-1234|WIN_NAME:DESKTOP-KITCHEN';
      final expectedHash = sha256.convert(utf8.encode(seed)).toString().toUpperCase().substring(0, 8);
      expect(
        KdsDeviceCodeResolver.formatAutoCode(seed),
        'KDS-$expectedHash',
      );
    });

    test('same hardware seed produces identical code every time (immutable)', () {
      const hwSeed = 'NET:eth0,wlan0|AND_ID:android-hw-9988|AND_SN:SN123456';
      final first = KdsDeviceCodeResolver.formatAutoCode(hwSeed);
      final second = KdsDeviceCodeResolver.formatAutoCode(hwSeed);
      expect(first, second);
      expect(first, startsWith('KDS-'));
      expect(first.length, 12); // 'KDS-' + 8 chars
    });

    test('falls back when empty hardware id', () {
      expect(KdsDeviceCodeResolver.formatAutoCode('   '), 'KDS-AUTO');
    });
  });

  group('KdsDeviceCodeResolver.resolve', () {
    test('auto code is stable across multiple resolve calls', () async {
      SharedPreferences.setMockInitialValues({});
      final resolver = KdsDeviceCodeResolver();
      final first = await resolver.resolve();
      expect(first.origin, DeviceCodeOrigin.autoDetected);
      expect(first.code, startsWith('KDS-'));

      final second = await resolver.resolve();
      expect(second.code, first.code);
    });
  });

  group('DeviceCodePrefs', () {
    test('persists hardware binding across load', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await DeviceCodePrefs.load();
      await prefs.saveBinding(deviceCode: 'KDS-E4B97C2A', hardwareId: 'hw-abc');

      final reloaded = await DeviceCodePrefs.load();
      expect(reloaded.lastDeviceCode, 'KDS-E4B97C2A');
      expect(reloaded.lastHardwareId, 'hw-abc');
      expect(reloaded.codeForHardware('hw-abc'), 'KDS-E4B97C2A');
    });
  });
}

