import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_cert_generator.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_tls.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CashierKdsCertGenerator and automated TLS resolution', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('kds_cert_gen_test_');
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('generate and load certificates with no BOM into SecurityContext', () async {
      final certsDir = Directory(p.join(tempDir.path, 'certs'));

      final paths = await CashierKdsCertGenerator.generate(
        certsDirectory: certsDir,
        ipAddresses: const ['127.0.0.1', '192.168.2.100'],
        dnsNames: const ['localhost', 'lan-cashier.local'],
      );

      final caFile = File(paths.caCertPath);
      final serverCertFile = File(paths.serverCertPath);
      final serverKeyFile = File(paths.serverKeyPath);

      expect(caFile.existsSync(), isTrue);
      expect(serverCertFile.existsSync(), isTrue);
      expect(serverKeyFile.existsSync(), isTrue);

      // Verify no UTF-8 BOM
      final certBytes = serverCertFile.readAsBytesSync();
      expect(certBytes.length, greaterThan(3));
      final hasBom = certBytes[0] == 0xEF && certBytes[1] == 0xBB && certBytes[2] == 0xBF;
      expect(hasBom, isFalse, reason: 'PEM certificate must not contain UTF-8 BOM');

      // Verify can be loaded by CashierKdsTlsConfiguration
      final tlsConfig = CashierKdsTlsConfiguration.fromDirectory(certsDir);
      expect(tlsConfig.certificateSha256.isNotEmpty, isTrue);
      expect(tlsConfig.caCertificatePath, equals(caFile.path));
      expect(tlsConfig.certificatePath, equals(serverCertFile.path));

      // Test auto-resolve with autoGenerateIfMissing
      final resolved = await CashierKdsTlsConfiguration.resolve(
        applicationDataRoot: tempDir,
        environment: const {},
        autoGenerateIfMissing: false,
      );
      expect(resolved, isNotNull);
      expect(resolved!.certificateSha256, equals(tlsConfig.certificateSha256));
    });

    test('generateAndroidForTesting dispatches to com.laofei.cashier/kds_cert MethodChannel', () async {
      final certsDir = Directory(p.join(tempDir.path, 'android_certs'));
      MethodCall? recordedCall;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.laofei.cashier/kds_cert'),
        (call) async {
          recordedCall = call;
          if (call.method == 'generateCerts') {
            final dir = Directory(call.arguments['certsDir'] as String);
            dir.createSync(recursive: true);
            File(p.join(dir.path, CashierKdsCertGenerator.caCertFileName)).writeAsStringSync('CA');
            File(p.join(dir.path, CashierKdsCertGenerator.caKeyFileName)).writeAsStringSync('CA_KEY');
            File(p.join(dir.path, CashierKdsCertGenerator.serverCertFileName)).writeAsStringSync('SERVER');
            File(p.join(dir.path, CashierKdsCertGenerator.serverKeyFileName)).writeAsStringSync('SERVER_KEY');
            return true;
          }
          return null;
        },
      );

      await CashierKdsCertGenerator.generateAndroidForTesting(
        certsDir: certsDir,
        ips: const ['192.168.1.100'],
        dnsNames: const ['lan.local'],
      );

      expect(recordedCall, isNotNull);
      expect(recordedCall!.method, equals('generateCerts'));
      expect(recordedCall!.arguments['certsDir'], equals(certsDir.path));
      expect(recordedCall!.arguments['ipAddresses'], equals(['192.168.1.100']));
      expect(recordedCall!.arguments['dnsNames'], equals(['lan.local']));

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.laofei.cashier/kds_cert'),
        null,
      );
    });
  });
}
