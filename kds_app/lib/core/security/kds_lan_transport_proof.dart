import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

const kKdsLanTimestampHeader = 'X-KDS-LAN-Timestamp';
const kKdsLanNonceHeader = 'X-KDS-LAN-Nonce';
const kKdsLanBodySha256Header = 'X-KDS-LAN-Body-SHA256';
const kKdsLanSignatureHeader = 'X-KDS-LAN-Signature';

Map<String, String> createKdsLanTransportProof({
  required String token,
  required String method,
  required String path,
  required Map<String, String> query,
  required Map<String, Object?> body,
  int? timestampMs,
  String? nonce,
}) {
  final effectiveTimestamp =
      timestampMs ?? DateTime.now().millisecondsSinceEpoch;
  final effectiveNonce = nonce ?? _newNonce();
  final bodyHash = kdsLanBodySha256(body);
  return {
    kKdsLanTimestampHeader: '$effectiveTimestamp',
    kKdsLanNonceHeader: effectiveNonce,
    kKdsLanBodySha256Header: bodyHash,
    kKdsLanSignatureHeader: kdsLanSignature(
      token: token,
      timestampMs: effectiveTimestamp,
      nonce: effectiveNonce,
      method: method,
      path: path,
      query: query,
      bodySha256: bodyHash,
    ),
  };
}

String kdsLanBodySha256(Map<String, Object?> body) =>
    sha256.convert(utf8.encode(jsonEncode(_canonicalJson(body)))).toString();

String kdsLanSignature({
  required String token,
  required int timestampMs,
  required String nonce,
  required String method,
  required String path,
  required Map<String, String> query,
  required String bodySha256,
}) {
  final canonical = [
    'v1',
    '$timestampMs',
    nonce,
    method.toUpperCase(),
    _canonicalTarget(path, query),
    bodySha256.toLowerCase(),
  ].join('\n');
  return Hmac(sha256, utf8.encode(token))
      .convert(utf8.encode(canonical))
      .toString();
}

String _newNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(18, (_) => random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

String _canonicalTarget(String path, Map<String, String> query) {
  final entries = query.entries.toList()
    ..sort((left, right) {
      final keyOrder = left.key.compareTo(right.key);
      return keyOrder != 0 ? keyOrder : left.value.compareTo(right.value);
    });
  final normalized = Uri(
    path: path,
    queryParameters: entries.isEmpty
        ? null
        : {for (final entry in entries) entry.key: entry.value},
  );
  return normalized.hasQuery ? '${normalized.path}?${normalized.query}' : path;
}

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return {for (final key in keys) key: _canonicalJson(value[key])};
  }
  if (value is List) return value.map(_canonicalJson).toList(growable: false);
  return value;
}
