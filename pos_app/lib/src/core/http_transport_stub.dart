import 'http_transport.dart';

HttpTransport createPlatformHttpTransport() => _UnsupportedHttpTransport();

class _UnsupportedHttpTransport implements HttpTransport {
  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) {
    throw UnsupportedError('No HTTP transport is available on this platform.');
  }
}
