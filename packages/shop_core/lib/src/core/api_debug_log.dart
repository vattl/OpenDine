import 'dart:convert';

import 'package:flutter/foundation.dart';

class ApiDebugLogEntry {
  const ApiDebugLogEntry({
    required this.id,
    required this.startedAt,
    required this.method,
    required this.uri,
    required this.requestHeaders,
    required this.requestBody,
    required this.statusCode,
    required this.responseBody,
    required this.duration,
    required this.succeeded,
    required this.error,
  });

  final String id;
  final DateTime startedAt;
  final String method;
  final Uri uri;
  final Map<String, String> requestHeaders;
  final String requestBody;
  final int? statusCode;
  final String responseBody;
  final Duration duration;
  final bool succeeded;
  final String error;
}

class ApiDebugLogStore extends ChangeNotifier {
  ApiDebugLogStore({this.maxEntries = 300});

  static final ApiDebugLogStore instance = ApiDebugLogStore();
  static const redacted = '<已脱敏>';
  static const _maxBodyCharacters = 200000;
  static int _requestSequence = 0;

  final int maxEntries;
  final List<ApiDebugLogEntry> _entries = [];

  List<ApiDebugLogEntry> get entries => List.unmodifiable(_entries);

  String nextRequestId() =>
      'api-${DateTime.now().microsecondsSinceEpoch}-${_requestSequence++}';

  void add(ApiDebugLogEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries.removeRange(maxEntries, _entries.length);
    }
    notifyListeners();
  }

  void clear() {
    if (_entries.isEmpty) return;
    _entries.clear();
    notifyListeners();
  }

  static Uri sanitizeUri(Uri uri) {
    final sanitizedUserInfo = uri.userInfo.isEmpty ? null : redacted;
    if (uri.queryParametersAll.isEmpty) {
      return sanitizedUserInfo == null
          ? uri
          : uri.replace(userInfo: sanitizedUserInfo);
    }
    final parameters = <String, dynamic>{};
    for (final entry in uri.queryParametersAll.entries) {
      parameters[entry.key] = _isSensitiveKey(entry.key)
          ? redacted
          : entry.value.length == 1
          ? entry.value.single
          : entry.value;
    }
    return uri.replace(
      userInfo: sanitizedUserInfo,
      queryParameters: parameters.map(
        (key, value) =>
            MapEntry(key, value is List ? value.join(',') : '$value'),
      ),
    );
  }

  static Map<String, String> sanitizeHeaders(Map<String, String> headers) => {
    for (final entry in headers.entries)
      entry.key: _isSensitiveKey(entry.key) ? redacted : entry.value,
  };

  static String sanitizeBody(String? body) {
    final source = body?.trim() ?? '';
    if (source.isEmpty) return '';
    String sanitized;
    try {
      sanitized = const JsonEncoder.withIndent(
        '  ',
      ).convert(_sanitizeValue(jsonDecode(source)));
    } on FormatException {
      sanitized = _sanitizePlainText(source);
    }
    if (sanitized.length <= _maxBodyCharacters) return sanitized;
    return '${sanitized.substring(0, _maxBodyCharacters)}\n…内容过长，已截断';
  }

  static Object? _sanitizeValue(Object? value, {String key = ''}) {
    if (_isSensitiveKey(key)) return redacted;
    if (value is Map) {
      return value.map(
        (rawKey, child) =>
            MapEntry('$rawKey', _sanitizeValue(child, key: '$rawKey')),
      );
    }
    if (value is List) {
      return value.map((child) => _sanitizeValue(child)).toList();
    }
    return value;
  }

  static String _sanitizePlainText(String value) {
    var result = value;
    for (final pattern in [
      RegExp(
        r'((?:authorization|password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|certificate|cert)\s*[=:]\s*)[^&\s,;]+',
        caseSensitive: false,
      ),
      RegExp(
        r'("(?:authorization|password|passwd|pwd|secret|token|api[_-]?key|private[_-]?key|certificate|cert)"\s*:\s*")[^"]*"',
        caseSensitive: false,
      ),
    ]) {
      result = result.replaceAllMapped(
        pattern,
        (match) => '${match[1]}$redacted',
      );
    }
    return result;
  }

  static bool _isSensitiveKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized == 'authorization' ||
        normalized == 'cookie' ||
        normalized == 'setcookie' ||
        normalized.contains('password') ||
        normalized.contains('passwd') ||
        normalized == 'pwd' ||
        normalized.contains('secret') ||
        normalized.contains('token') ||
        normalized.contains('apikey') ||
        normalized.endsWith('key') ||
        normalized.contains('privatekey') ||
        normalized.contains('certificate') ||
        normalized == 'cert';
  }
}
