import 'dart:collection';

/// Complete KDS login request received by the cashier LAN listener.
///
/// The class implements [Map] for source compatibility with existing login
/// handlers while keeping authentication material out of the JSON body. The
/// cashier must forward these credentials to the cloud and must not interpret
/// them as a local authorization decision.
class CashierKdsLoginRequest extends MapBase<String, Object?> {
  CashierKdsLoginRequest({
    required Map<String, Object?> body,
    required this.requestId,
    this.deviceToken,
  }) : body = Map<String, Object?>.unmodifiable(body);

  final Map<String, Object?> body;
  final String requestId;
  final String? deviceToken;

  @override
  Object? operator [](Object? key) => body[key];

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('KDS login request is immutable');

  @override
  void clear() => throw UnsupportedError('KDS login request is immutable');

  @override
  Iterable<String> get keys => body.keys;

  @override
  Object? remove(Object? key) =>
      throw UnsupportedError('KDS login request is immutable');
}

class CashierKdsProxyRequest {
  const CashierKdsProxyRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
    required this.deviceToken,
    required this.requestId,
    this.commandId,
    this.deviceCode,
  });

  final String method;
  final String path;
  final Map<String, Object?> query;
  final Map<String, Object?> body;
  final String deviceToken;
  final String requestId;
  final String? commandId;
  final String? deviceCode;
}

class CashierKdsProxyResponse {
  const CashierKdsProxyResponse({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}
