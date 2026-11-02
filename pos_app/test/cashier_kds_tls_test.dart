import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_tls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TLS config is optional only when neither path is configured', () {
    expect(CashierKdsTlsConfiguration.fromEnvironment(const {}), isNull);
  });

  test('TLS config rejects partial certificate configuration', () {
    expect(
      () => CashierKdsTlsConfiguration.fromEnvironment(const {
        'CASHIER_KDS_TLS_CERT_PATH': 'only-cert.pem',
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('TLS config reports a missing certificate before listener startup', () {
    expect(
      () => CashierKdsTlsConfiguration.fromEnvironment(const {
        'CASHIER_KDS_TLS_CERT_PATH': 'missing-cert.pem',
        'CASHIER_KDS_TLS_KEY_PATH': 'missing-key.pem',
      }),
      throwsA(isA<FileSystemException>()),
    );
  });
}
