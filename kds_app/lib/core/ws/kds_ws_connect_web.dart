import 'package:web_socket_channel/html.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const String kdsWsConnectorPlatform = 'web';

/// 浏览器 WebSocket 无法设置自定义 Header，token 只能走 query（legacy）。
WebSocketChannel connectKdsWebSocket(
  Uri uri, {
  required String deviceToken,
  bool legacyQueryToken = false,
}) {
  final query = Map<String, String>.from(uri.queryParameters);
  query['token'] = deviceToken.trim();
  return HtmlWebSocketChannel.connect(
    uri.replace(queryParameters: query),
  );
}
