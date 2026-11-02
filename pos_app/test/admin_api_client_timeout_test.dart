import 'dart:async';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a stalled request becomes a recoverable timeout error', () async {
    final client = AdminApiClient(
      baseUrl: 'http://api.test',
      transport: _StalledHttpTransport(),
      token: 'token',
      shopId: 2,
      requestTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      client.get(categoryListAllEndpoint),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('/admin/category/listAll'),
        ),
      ),
    );
  });

  test('timeout aborts a cancellable platform request', () async {
    final transport = _CancelableStalledHttpTransport();
    final client = AdminApiClient(
      baseUrl: 'http://api.test',
      transport: transport,
      token: 'token',
      shopId: 2,
      requestTimeout: const Duration(milliseconds: 20),
      requestBudget: HttpRequestBudget(maxConcurrent: 1, maxQueued: 0),
    );

    await expectLater(
      client.get(categoryListAllEndpoint),
      throwsA(isA<ApiException>()),
    );

    expect(transport.cancelled, isTrue);
  });

  test(
    'full request budget rejects immediately instead of growing a queue',
    () async {
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: _StalledHttpTransport(),
        token: 'token',
        shopId: 2,
        requestTimeout: const Duration(milliseconds: 30),
        requestBudget: HttpRequestBudget(maxConcurrent: 1, maxQueued: 0),
      );

      final first = client.get(categoryListAllEndpoint);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        client.get(categoryListAllEndpoint),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            '请求过多，请稍后重试',
          ),
        ),
      );
      await expectLater(first, throwsA(isA<ApiException>()));
    },
  );

  test(
    'request bodies over the configured budget are rejected before transport',
    () async {
      final transport = _RecordingTransport();
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        maxRequestBodyBytes: 16,
        requestBudget: HttpRequestBudget(maxConcurrent: 1, maxQueued: 0),
      );

      await expectLater(
        client.post(adminLoginEndpoint, body: {'value': 'x' * 32}),
        throwsA(isA<ApiException>()),
      );
      expect(transport.calls, 0);
    },
  );

  test(
    'small receipt image uploads remain compatible with the multipart budget',
    () async {
      final transport = _RecordingTransport();
      final client = AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token',
        shopId: 2,
        maxMultipartBodyBytes: 1024,
        requestBudget: HttpRequestBudget(maxConcurrent: 1, maxQueued: 0),
      );

      await client.postMultipart(
        offlineCollectUploadEndpoint,
        files: {
          'wechatQr': (
            bytes: <int>[1, 2, 3],
            filename: 'qr.png',
            contentType: 'image/png',
          ),
        },
      );

      expect(transport.calls, 1);
    },
  );

  test('oversized responses become a recoverable API error', () async {
    final client = AdminApiClient(
      baseUrl: 'http://api.test',
      transport: _OversizedResponseTransport(),
      maxResponseBodyBytes: 1024,
      requestBudget: HttpRequestBudget(maxConcurrent: 1, maxQueued: 0),
    );

    await expectLater(
      client.get(categoryListAllEndpoint),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          contains('响应内容超过 1 KiB 上限'),
        ),
      ),
    );
  });
}

class _StalledHttpTransport implements HttpTransport {
  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) => Completer<HttpResponseData>().future;
}

class _CancelableStalledHttpTransport implements CancellableHttpTransport {
  bool cancelled = false;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) => Completer<HttpResponseData>().future;

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
    cancellation.bindAbort(() => cancelled = true);
    return Completer<HttpResponseData>().future;
  }
}

class _RecordingTransport implements HttpTransport {
  int calls = 0;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) async {
    calls++;
    return const HttpResponseData(statusCode: 200, body: '{"code":0}');
  }
}

class _OversizedResponseTransport implements CancellableHttpTransport {
  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
  }) => throw UnimplementedError();

  @override
  Future<HttpResponseData> sendCancellable({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,
    required HttpRequestCancellation cancellation,
    required int maxResponseBytes,
  }) => Future<HttpResponseData>.error(
    HttpResponseBodyTooLargeException(maxResponseBytes),
  );
}
