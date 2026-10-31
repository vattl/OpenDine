import 'http_transport_stub.dart'
    if (dart.library.html) 'http_transport_web.dart'
    if (dart.library.io) 'http_transport_io.dart';

class HttpResponseData {
  const HttpResponseData({required this.statusCode, required this.body});

  final int statusCode;
  final String body;
}

abstract class HttpTransport {
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  });
}

HttpTransport createHttpTransport() => createPlatformHttpTransport();
