import 'http_transport_stub.dart'
    if (dart.library.html) 'http_transport_web.dart'
    if (dart.library.io) 'http_transport_io.dart';

class HttpResponseData {
  const HttpResponseData({
    required this.statusCode,
    required this.body,
    this.headers = const {},
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

class HttpResponseBodyTooLargeException implements Exception {
  const HttpResponseBodyTooLargeException(this.maxBytes);

  final int maxBytes;
}

class HttpRequestCancellation {
  bool _cancelled = false;
  void Function()? _abort;

  bool get isCancelled => _cancelled;

  void bindAbort(void Function() abort) {
    _abort = abort;
    if (_cancelled) abort();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _abort?.call();
  }
}

abstract class HttpTransport {
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  });
}

abstract class CancellableHttpTransport implements HttpTransport {
  Future<HttpResponseData> sendCancellable({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
    required HttpRequestCancellation cancellation,
    required int maxResponseBytes,
  });
}

HttpTransport createHttpTransport() => createPlatformHttpTransport();
