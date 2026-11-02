import 'dart:async';

import 'package:admin_panel_flutter/src/core/http_transport.dart';
import 'package:admin_panel_flutter/src/core/network_status_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('any HTTP response (even 404) means online', () async {
    final transport = _FakeTransport(
      behavior: () async => const HttpResponseData(statusCode: 404, body: ''),
    );
    final monitor = NetworkStatusMonitor(
      baseUrl: 'https://example.test',
      transport: transport,
    );
    await monitor.probeNow();
    expect(monitor.online, isTrue);
  });

  test('offline only after consecutive failures reach the threshold', () async {
    final transport = _FakeTransport(
      behavior: () async => throw TimeoutException('no route'),
    );
    final monitor = NetworkStatusMonitor(
      baseUrl: 'https://example.test',
      transport: transport,
    );
    await monitor.probeNow();
    expect(monitor.online, isTrue, reason: '单次抖动不应误报断网');
    await monitor.probeNow();
    expect(monitor.online, isFalse);
  });

  test('one success recovers immediately from offline', () async {
    var fail = true;
    final transport = _FakeTransport(
      behavior: () async {
        if (fail) throw TimeoutException('no route');
        return const HttpResponseData(statusCode: 200, body: '{}');
      },
    );
    final monitor = NetworkStatusMonitor(
      baseUrl: 'https://example.test',
      transport: transport,
    );
    await monitor.probeNow();
    await monitor.probeNow();
    expect(monitor.online, isFalse);
    fail = false;
    await monitor.probeNow();
    expect(monitor.online, isTrue);
  });

  test('offline transition notifies listeners exactly once', () async {
    final transport = _FakeTransport(
      behavior: () async => throw TimeoutException('no route'),
    );
    final monitor = NetworkStatusMonitor(
      baseUrl: 'https://example.test',
      transport: transport,
    );
    var notifications = 0;
    monitor.addListener(() => notifications++);
    await monitor.probeNow();
    expect(notifications, 0);
    await monitor.probeNow();
    expect(notifications, 1);
    await monitor.probeNow();
    expect(notifications, 1, reason: '持续断网不应重复通知');
  });
}

class _FakeTransport extends HttpTransport {
  _FakeTransport({required this.behavior});

  final Future<HttpResponseData> Function() behavior;

  @override
  Future<HttpResponseData> send({
    required String method,
    required Uri uri,
    required Map<String, String> headers,
    String? body,
    List<int>? bodyBytes,  }) =>
      behavior();
}
