import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/security/kds_lan_transport_proof.dart';

void main() {
  test('creates deterministic proof over canonical body and request target',
      () {
    final proof = createKdsLanTransportProof(
      token: 'cloud-issued-device-token',
      timestampMs: 1790812800000,
      nonce: '0123456789abcdef',
      method: 'POST',
      path: '/kds/v2/commands',
      query: const {'after_seq': '4'},
      body: const {
        'target': {'quantity': 1, 'detail_id': 7},
        'type': 'complete_item',
      },
    );

    expect(proof[kKdsLanTimestampHeader], '1790812800000');
    expect(proof[kKdsLanNonceHeader], '0123456789abcdef');
    expect(
      proof[kKdsLanBodySha256Header],
      'c0de614d4cb8fe06b9ce2a82fa2ae024715a606c3b631ae4824f0728145364d6',
    );
    expect(
      proof[kKdsLanSignatureHeader],
      '2e5cf4041567d7eb7b884973f73062700ec9bbafc8dcadc3aefe907d38128dd0',
    );
    expect(
      proof[kKdsLanBodySha256Header],
      kdsLanBodySha256(const {
        'type': 'complete_item',
        'target': {'detail_id': 7, 'quantity': 1},
      }),
    );
  });
}
