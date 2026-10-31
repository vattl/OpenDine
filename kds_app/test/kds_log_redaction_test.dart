import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/util/kds_log_redaction.dart';

void main() {
  test('redacts ws token query param', () {
    final out = redactSensitiveLog(
      'connect wss://host/ws/kds?shop_id=1&token=abcdef1234567890',
    );
    expect(out.contains('abcdef'), isFalse);
    expect(out.contains('token=***'), isTrue);
  });

  test('redacts device_token json and header', () {
    final out = redactSensitiveLog(
      'X-Kds-Device-Token: secret-token-value {"device_token":"also-secret"}',
    );
    expect(out.contains('secret-token'), isFalse);
    expect(out.contains('also-secret'), isFalse);
  });

  test('redacts client_id in json logs', () {
    final out = redactSensitiveLog('body={"client_id":"uuid-1234"}');
    expect(out.contains('uuid-1234'), isFalse);
    expect(out.contains('"client_id":"***"'), isTrue);
  });

  test('redacts X-Kds-Pairing-Secret header', () {
    final out = redactSensitiveLog(
      'POST /kds/device/login X-Kds-Pairing-Secret: pair-once-123',
    );
    expect(out.contains('pair-once-123'), isFalse);
    expect(out.contains('X-Kds-Pairing-Secret: ***'), isTrue);
  });
}
