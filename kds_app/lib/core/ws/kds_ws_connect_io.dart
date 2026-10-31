import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:kds_app/core/security/kds_lan_transport_proof.dart';
import 'package:kds_app/core/config/api_base_util.dart';

import 'kds_ws_connect_common.dart';

const String kdsWsConnectorPlatform = 'io';

WebSocketChannel connectKdsWebSocket(
  Uri uri, {
  required String deviceToken,
  bool legacyQueryToken = false,
}) {
  final headers = <String, dynamic>{
    kKdsDeviceTokenHeader: deviceToken.trim(),
  };
  final queryParams = Map<String, String>.from(uri.queryParameters);
  if (legacyQueryToken &&
      deviceToken.trim().isNotEmpty &&
      !queryParams.containsKey('token')) {
    queryParams['token'] = deviceToken.trim();
  }
  final connectUri = uri.replace(queryParameters: queryParams);
  final httpsBase = connectUri.replace(scheme: 'https', path: '', query: '');
  if (connectUri.scheme.toLowerCase() == 'wss' &&
      isSecurePrivateLanApiBase(httpsBase.toString()) &&
      deviceToken.trim().isNotEmpty) {
    headers.addAll(
      createKdsLanTransportProof(
        token: deviceToken.trim(),
        method: 'GET',
        path: connectUri.path,
        query: connectUri.queryParameters,
        body: const {},
      ),
    );
  }
  return IOWebSocketChannel.connect(connectUri, headers: headers);
}
