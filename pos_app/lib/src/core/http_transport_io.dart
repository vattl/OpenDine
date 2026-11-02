import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'http_transport.dart';

HttpTransport createPlatformHttpTransport() => IoHttpTransport();

class IoHttpTransport implements CancellableHttpTransport {
  final HttpClient _client = HttpClient();

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) => sendCancellable(
    method: method,
    uri: uri,
    headers: headers,
    body: body,
    bodyBytes: bodyBytes,
    cancellation: HttpRequestCancellation(),
    maxResponseBytes: 2 * 1024 * 1024,
  );

  @override
  Future<HttpResponseData> sendCancellable({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
    required HttpRequestCancellation cancellation,
    required int maxResponseBytes,
  }) async {
    final request = await _client.openUrl(method, uri);
    cancellation.bindAbort(request.abort);
    headers.forEach(request.headers.set);
    if (bodyBytes != null) {
      request.add(bodyBytes);
    } else if (body != null) {
      request.write(body);
    }
    final response = await request.close();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response) {
      if (bytes.length + chunk.length > maxResponseBytes) {
        cancellation.cancel();
        throw HttpResponseBodyTooLargeException(maxResponseBytes);
      }
      bytes.add(chunk);
    }
    final responseHeaders = <String, String>{};
    response.headers.forEach(
      (name, values) => responseHeaders[name.toLowerCase()] = values.join(','),
    );
    return HttpResponseData(
      statusCode: response.statusCode,
      body: utf8.decode(bytes.takeBytes(), allowMalformed: true),
      headers: responseHeaders,
    );
  }
}
