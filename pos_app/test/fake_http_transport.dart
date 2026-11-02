import 'package:admin_panel_flutter/src/core/http_transport.dart';

class RecordedRequest {
  const RecordedRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
    this.bodyBytes,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final List<int>? bodyBytes;
}

class FakeHttpTransport implements HttpTransport {
  FakeHttpTransport(this.routes);

  final Map<String, Object> routes;
  final List<RecordedRequest> requests = [];

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    requests.add(
      RecordedRequest(
        method: method,
        uri: uri,
        headers: Map.of(headers),
        body: body,
        bodyBytes: bodyBytes,
      ),
    );
    final key = '$method ${uri.path}';
    final response = routes[key];
    if (response == null) {
      return HttpResponseData(statusCode: 404, body: 'missing route $key');
    }
    if (response is HttpResponseData) {
      return response;
    }
    return HttpResponseData(statusCode: 200, body: response.toString());
  }
}
