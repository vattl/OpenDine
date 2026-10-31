import 'dart:io';
import 'dart:convert';

import 'http_transport.dart';

HttpTransport createPlatformHttpTransport() => IoHttpTransport();

class IoHttpTransport implements HttpTransport {
  final HttpClient _client = HttpClient();

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) async {
    final request = await _client.openUrl(method, uri);
    headers.forEach(request.headers.set);
    if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return HttpResponseData(statusCode: response.statusCode, body: text);
  }
}
