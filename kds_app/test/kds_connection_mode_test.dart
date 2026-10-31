import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';

void main() {
  test('all persisted connection modes migrate to cloud-first policy', () {
    for (final raw in <String?>[
      null,
      'cloud_first',
      'lan_first',
      'cloud_direct',
      'lan_only',
      'unknown',
    ]) {
      expect(
        KdsConnectionMode.fromValue(raw),
        KdsConnectionMode.cloudFirst,
        reason: 'persisted mode $raw must not bypass cloud authority',
      );
    }
  });
}
