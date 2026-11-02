import 'dart:async';
import 'dart:typed_data';

// ignore: deprecated_member_use
import 'dart:html' as html;

import 'http_transport.dart';

HttpTransport createPlatformHttpTransport() => WebHttpTransport();

class WebHttpTransport implements CancellableHttpTransport {
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
  }) {
    final completer = Completer<HttpResponseData>();
    final request = html.HttpRequest();

    void fail(Object error) {
      if (completer.isCompleted) return;
      completer.completeError(error);
    }

    cancellation.bindAbort(request.abort);

    request
      ..open(method, uri.toString(), async: true)
      ..onLoadEnd.listen((_) {
        if (completer.isCompleted) return;
        final responseText = request.responseText ?? '';
        if (responseText.length > maxResponseBytes) {
          cancellation.cancel();
          fail(HttpResponseBodyTooLargeException(maxResponseBytes));
          return;
        }
        completer.complete(
          HttpResponseData(
            statusCode: request.status ?? 0,
            body: responseText,
            headers: {
              if (request.getResponseHeader('Retry-After') case final value?)
                'retry-after': value,
            },
          ),
        );
      })
      ..onProgress.listen((event) {
        final loaded = event.loaded;
        if (loaded != null && loaded > maxResponseBytes) {
          cancellation.cancel();
          fail(HttpResponseBodyTooLargeException(maxResponseBytes));
        }
      })
      ..onError.listen((event) {
        if (completer.isCompleted) return;
        completer.complete(
          HttpResponseData(
            statusCode: request.status ?? 0,
            body: request.responseText ?? '$event',
            headers: {
              if (request.getResponseHeader('Retry-After') case final value?)
                'retry-after': value,
            },
          ),
        );
      });

    headers.forEach(request.setRequestHeader);
    request.send(bodyBytes == null ? body : Uint8List.fromList(bodyBytes));
    return completer.future;
  }
}
