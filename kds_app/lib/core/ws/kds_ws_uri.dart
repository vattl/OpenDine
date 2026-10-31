import 'package:kds_app/core/config/api_base_util.dart';

/// 由 REST API 基址构建 WebSocket 连接 URI（wss/ws，不含错误 :0 端口）。
/// LAN v2 authenticates with [kKdsDeviceTokenHeader].
Uri buildKdsWebSocketUri({
  required String apiBase,
  required int shopId,
  required String screenTag,
}) {
  var base = normalizeApiBase(apiBase);
  if (base.isEmpty) {
    base = platformDefaultApiBase();
  }

  final httpUri = Uri.parse(base);
  final host = httpUri.host;
  if (host.isEmpty) {
    throw ArgumentError('Invalid API base URL: $apiBase');
  }

  final scheme = httpUri.scheme.toLowerCase();
  final wsScheme = (scheme == 'https' || scheme == 'wss') ? 'wss' : 'ws';

  // wss/ws 在 Dart Uri 中默认 port=0，WebSocket 握手会错误连到 :0，须显式 443/80
  final int effectivePort;
  if (httpUri.hasPort &&
      httpUri.port != 0 &&
      httpUri.port != 443 &&
      httpUri.port != 80) {
    effectivePort = httpUri.port;
  } else {
    effectivePort = wsScheme == 'wss' ? 443 : 80;
  }

  final query = <String, String>{
    'shop_id': '$shopId',
    'screen_tag': screenTag,
    'protocol_version': '2',
  };
  return Uri(
    scheme: wsScheme,
    host: host,
    port: effectivePort,
    path: '/ws/kds/v2',
    queryParameters: query,
  );
}
