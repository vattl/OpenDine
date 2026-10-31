import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_token_vault.dart';
// These registrations intentionally exercise the real Windows FFI plugins.
// ignore: depend_on_referenced_packages
import 'package:flutter_secure_storage_windows/flutter_secure_storage_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_windows/path_provider_windows.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Windows DPAPI vault persists encrypted token and deletes it',
    () async {
      PathProviderWindows.registerWith();
      FlutterSecureStorageWindows.registerWith();
      final random = Random.secure();
      final token = base64UrlEncode(
        List<int>.generate(48, (_) => random.nextInt(256)),
      );
      const deviceCode = 'KDS-VAULT-PLATFORM-PROBE';
      const shopId = 2147483000;
      final vault = CashierKdsTokenVault();
      var cached = false;
      try {
        await vault.cacheToken(
          shopId: shopId,
          deviceCode: deviceCode,
          token: token,
        );
        cached = true;
        expect(
          await vault.readToken(shopId: shopId, deviceCode: deviceCode),
          token,
        );

        final support = await getApplicationSupportDirectory();
        final cipherFile = File(
          p.join(support.path, 'flutter_secure_storage.dat'),
        );
        expect(await cipherFile.exists(), isTrue);
        final cipherBytes = await cipherFile.readAsBytes();
        expect(_containsBytes(cipherBytes, utf8.encode(token)), isFalse);

        await vault.deleteToken(shopId: shopId, deviceCode: deviceCode);
        cached = false;
        expect(
          await vault.readToken(shopId: shopId, deviceCode: deviceCode),
          isNull,
        );
      } finally {
        if (cached) {
          await vault.deleteToken(shopId: shopId, deviceCode: deviceCode);
        }
      }
    },
    skip: Platform.isWindows ? false : 'Windows DPAPI acceptance only',
  );
}

bool _containsBytes(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var offset = 0; offset <= haystack.length - needle.length; offset++) {
    var matches = true;
    for (var index = 0; index < needle.length; index++) {
      if (haystack[offset + index] != needle[index]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
