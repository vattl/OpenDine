import 'dart:async';

// ignore: deprecated_member_use
import 'dart:html' as html;

import 'http_transport.dart';

HttpTransport createPlatformHttpTransport() => WebHttpTransport();

class WebHttpTransport implements HttpTransport {
  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
  }) {
    final completer = Completer<HttpResponseData>();
    final request = html.HttpRequest();

    request
      ..open(method, uri.toString(), async: true)
      ..onLoadEnd.listen((_) {
        if (completer.isCompleted) return;
        completer.complete(
          HttpResponseData(
            statusCode: request.status ?? 0,
            body: request.responseText ?? '',
          ),
        );
      })
      ..onError.listen((event) {
        if (completer.isCompleted) return;
        completer.complete(
          HttpResponseData(
            statusCode: request.status ?? 0,
            body: request.responseText ?? '$event',
          ),
        );
      });

    headers.forEach(request.setRequestHeader);
    request.send(body);
    return completer.future;
  }
}
