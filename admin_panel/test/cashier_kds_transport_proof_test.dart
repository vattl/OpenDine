import 'package:admin_panel_flutter/src/features/kds_local/server/cashier_kds_transport_proof.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const token = 'cloud-issued-device-token';
  const nowMs = 1790812800000;
  const body = <String, Object?>{
    'type': 'complete_item',
    'target': <String, Object?>{'detail_id': 7, 'quantity': 1},
  };

  Map<String, String> proof({
    String nonce = '0123456789abcdef',
    int timestampMs = nowMs,
    Map<String, Object?> payload = body,
  }) {
    final hash = kdsLanBodySha256(payload);
    return {
      kKdsLanTimestampHeader: '$timestampMs',
      kKdsLanNonceHeader: nonce,
      kKdsLanBodySha256Header: hash,
      kKdsLanSignatureHeader: kdsLanSignature(
        token: token,
        timestampMs: timestampMs,
        nonce: nonce,
        method: 'POST',
        path: '/kds/v2/commands',
        query: const {'after_seq': '4'},
        bodySha256: hash,
      ),
    };
  }

  bool verify(
    CashierKdsTransportProofVerifier verifier,
    Map<String, String> headers, {
    Map<String, Object?> payload = body,
  }) => verifier.verify(
    token: token,
    method: 'POST',
    path: '/kds/v2/commands',
    query: const {'after_seq': '4'},
    body: payload,
    timestamp: headers[kKdsLanTimestampHeader],
    nonce: headers[kKdsLanNonceHeader],
    bodySha256: headers[kKdsLanBodySha256Header],
    signature: headers[kKdsLanSignatureHeader],
  );

  test('accepts one valid proof and rejects nonce replay', () {
    final verifier = CashierKdsTransportProofVerifier(nowMs: () => nowMs);
    final headers = proof();
    expect(
      headers[kKdsLanBodySha256Header],
      'c0de614d4cb8fe06b9ce2a82fa2ae024715a606c3b631ae4824f0728145364d6',
    );
    expect(
      headers[kKdsLanSignatureHeader],
      '2e5cf4041567d7eb7b884973f73062700ec9bbafc8dcadc3aefe907d38128dd0',
    );
    expect(verify(verifier, headers), isTrue);
    expect(verify(verifier, headers), isFalse);
  });

  test('rejects stale proof, changed body, and changed request target', () {
    final verifier = CashierKdsTransportProofVerifier(nowMs: () => nowMs);
    expect(verify(verifier, proof(timestampMs: nowMs - 61000)), isFalse);
    expect(
      verify(
        verifier,
        proof(nonce: 'changed-body-0001'),
        payload: const {'type': 'recall_item'},
      ),
      isFalse,
    );
    final headers = proof(nonce: 'changed-path-0001');
    expect(
      verifier.verify(
        token: token,
        method: 'GET',
        path: '/kds/v2/bootstrap',
        query: const {},
        body: const {},
        timestamp: headers[kKdsLanTimestampHeader],
        nonce: headers[kKdsLanNonceHeader],
        bodySha256: headers[kKdsLanBodySha256Header],
        signature: headers[kKdsLanSignatureHeader],
      ),
      isFalse,
    );
  });
}
