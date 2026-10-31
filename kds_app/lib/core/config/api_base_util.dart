import 'package:kds_app/core/config/kds_app_config.dart';

/// 规范化 REST API 基址（去空格、hash、尾斜杠，修正常见拼写错误）
String normalizeApiBase(String raw) {
  var base = raw.trim().replaceAll(RegExp(r'\s+'), '');
  if (base.isEmpty) return '';

  final hashIdx = base.indexOf('#');
  if (hashIdx >= 0) base = base.substring(0, hashIdx);

  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }

  // 常见手误
  if (base.startsWith('htps://')) {
    base = 'https://${base.substring(7)}';
  }
  if (base.startsWith('htp://')) {
    base = 'http://${base.substring(6)}';
  }
  base = base.replaceFirst(RegExp(r'^http:/([^/])'), r'http://$1');
  base = base.replaceFirst(RegExp(r'^https:/([^/])'), r'https://$1');
  base = base.replaceFirst('://ww.', '://www.');

  // 去掉无效端口 :0（历史错误配置会导致 WebSocket 连到 host:0）
  base = base.replaceFirst(RegExp(r':0(?=/|$)'), '');

  if (!base.contains('://')) {
    base = 'https://$base';
  }

  return base;
}

/// LAN-only has no inferred endpoint; the cashier address must be explicit.
String platformDefaultApiBase() => KdsAppConfig.defaultApiBase;

/// 默认云端 API 基址
String platformDefaultCloudApiBase() => KdsAppConfig.defaultCloudApiBase;

/// 会话/API 实际使用的基址。空配置保持为空，不回退到云端。
String resolveEffectiveApiBase(String stored) {
  final trimmed = stored.trim();
  if (trimmed.isNotEmpty) return normalizeApiBase(trimmed);
  return platformDefaultApiBase();
}

/// 云端 API 实际使用的基址。
String resolveEffectiveCloudApiBase(String stored) {
  final trimmed = stored.trim();
  if (trimmed.isNotEmpty && trimmed != 'https://bbq.example.com') {
    return normalizeApiBase(trimmed);
  }
  return platformDefaultCloudApiBase();
}

bool isValidApiBase(String raw) {
  if (raw.trim().isEmpty) return false;
  try {
    final uri = Uri.parse(normalizeApiBase(raw));
    if (uri.host.isEmpty) return false;
    if (uri.hasPort && uri.port == 0) return false;
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  } catch (_) {
    return false;
  }
}

/// LAN v2 accepts only explicit private cashier endpoints.
bool isPrivateLanApiBase(String raw) {
  if (!isValidApiBase(raw)) return false;
  final host = Uri.parse(normalizeApiBase(raw)).host.toLowerCase();
  if (host == 'localhost' || host == '::1' || host.endsWith('.local')) {
    return true;
  }
  final parts = host.split('.').map(int.tryParse).toList(growable: false);
  if (parts.length != 4 || parts.any((part) => part == null)) return false;
  final first = parts[0]!;
  final second = parts[1]!;
  return first == 10 ||
      first == 127 ||
      (first == 192 && second == 168) ||
      (first == 172 && second >= 16 && second <= 31);
}

bool isLoopbackApiBase(String raw) {
  if (!isValidApiBase(raw)) return false;
  final host = Uri.parse(normalizeApiBase(raw)).host.toLowerCase();
  if (host == 'localhost' || host == '::1') return true;
  final parts = host.split('.').map(int.tryParse).toList(growable: false);
  return parts.length == 4 && parts[0] == 127;
}

/// Production LAN endpoints must protect the cloud-issued device token in
/// transit. Loopback HTTP is permitted only when a caller explicitly opts in.
bool isSecurePrivateLanApiBase(String raw, {bool allowLoopbackHttp = false}) {
  if (!isPrivateLanApiBase(raw)) return false;
  final scheme = Uri.parse(normalizeApiBase(raw)).scheme.toLowerCase();
  return scheme == 'https' || (allowLoopbackHttp && isLoopbackApiBase(raw));
}

/// HTTP 明文基址（生产环境应使用 HTTPS）
bool isInsecureApiBase(String raw) {
  if (raw.trim().isEmpty) return false;
  try {
    return Uri.parse(normalizeApiBase(raw)).scheme.toLowerCase() == 'http';
  } catch (_) {
    return false;
  }
}

/// 预览 WebSocket 连接地址（token 脱敏）
String previewKdsWebSocketUrl({
  required String apiBase,
  int shopId = 1,
  String screenTag = 'workflow_board',
}) {
  try {
    final resolved = resolveEffectiveApiBase(apiBase);
    final httpUri = Uri.parse(resolved);
    if (httpUri.host.isEmpty) return '(无效 API 基址)';
    final scheme = httpUri.scheme.toLowerCase();
    final wsScheme = (scheme == 'https' || scheme == 'wss') ? 'wss' : 'ws';
    final int effectivePort;
    if (httpUri.hasPort &&
        httpUri.port != 0 &&
        httpUri.port != 443 &&
        httpUri.port != 80) {
      effectivePort = httpUri.port;
    } else {
      effectivePort = wsScheme == 'wss' ? 443 : 80;
    }
    return '${Uri(
      scheme: wsScheme,
      host: httpUri.host,
      port: effectivePort,
      path: '/ws/kds/v2',
      queryParameters: {
        'shop_id': '$shopId',
        'screen_tag': screenTag,
      },
    )} · Header: X-Kds-Device-Token=***';
  } catch (_) {
    return '(无效 API 基址)';
  }
}
