import 'dart:convert';

import 'package:crypto/crypto.dart';

const kKdsLanTimestampHeader = 'X-KDS-LAN-Timestamp';
const kKdsLanNonceHeader = 'X-KDS-LAN-Nonce';
const kKdsLanBodySha256Header = 'X-KDS-LAN-Body-SHA256';
const kKdsLanSignatureHeader = 'X-KDS-LAN-Signature';

class CashierKdsTransportProofVerifier {
  CashierKdsTransportProofVerifier({
    this.allowedClockSkew = const Duration(seconds: 60),
    this.nonceRetention = const Duration(minutes: 5),
    this.maxRetainedNonces = 4096,
    int Function()? nowMs,
  }) : _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Duration allowedClockSkew;
  final Duration nonceRetention;
  final int maxRetainedNonces;
  final int Function() _nowMs;
  final Map<String, int> _seenNonces = {};

  bool verify({
    required String token,
    required String method,
    required String path,
    required Map<String, String> query,
    required Map<String, Object?> body,
    required String? timestamp,
    required String? nonce,
    required String? bodySha256,
    required String? signature,
  }) {
    final timestampMs = int.tryParse(timestamp ?? '');
    final normalizedNonce = nonce?.trim() ?? '';
    final normalizedBodyHash = bodySha256?.trim().toLowerCase() ?? '';
    final normalizedSignature = signature?.trim().toLowerCase() ?? '';
    if (token.trim().isEmpty ||
        timestampMs == null ||
        normalizedNonce.length < 16 ||
        normalizedNonce.length > 128 ||
        normalizedBodyHash.length != 64 ||
        normalizedSignature.length != 64) {
      return false;
    }

    final now = _nowMs();
    if ((now - timestampMs).abs() > allowedClockSkew.inMilliseconds) {
      return false;
    }
    _prune(now);
    final nonceKey = '${sha256.convert(utf8.encode(token))}:$normalizedNonce';
    if (_seenNonces.containsKey(nonceKey)) return false;

    final expectedBodyHash = kdsLanBodySha256(body);
    if (!_constantTimeEquals(normalizedBodyHash, expectedBodyHash)) {
      return false;
    }
    final expectedSignature = kdsLanSignature(
      token: token,
      timestampMs: timestampMs,
      nonce: normalizedNonce,
      method: method,
      path: path,
      query: query,
      bodySha256: expectedBodyHash,
    );
    if (!_constantTimeEquals(normalizedSignature, expectedSignature)) {
      return false;
    }

    if (_seenNonces.length >= maxRetainedNonces) {
      final oldest = _seenNonces.entries.reduce(
        (left, right) => left.value <= right.value ? left : right,
      );
      _seenNonces.remove(oldest.key);
    }
    _seenNonces[nonceKey] = now;
    return true;
  }

  void _prune(int nowMs) {
    final cutoff = nowMs - nonceRetention.inMilliseconds;
    _seenNonces.removeWhere((_, seenAtMs) => seenAtMs < cutoff);
  }
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
  final target = _canonicalTarget(path, query);
  final canonical = [
    'v1',
    '$timestampMs',
    nonce,
    method.toUpperCase(),
    target,
    bodySha256.toLowerCase(),
  ].join('\n');
  return Hmac(
    sha256,
    utf8.encode(token),
  ).convert(utf8.encode(canonical)).toString();
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

bool _constantTimeEquals(String left, String right) {
  var difference = left.length ^ right.length;
  final count = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < count; index += 1) {
    difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
  }
  return difference == 0;
}
