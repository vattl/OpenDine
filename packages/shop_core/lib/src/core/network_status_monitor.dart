import 'dart:async';

import 'package:flutter/foundation.dart';

import 'http_transport.dart';

/// 轻量网络连通性监测：周期性探测云端 API 基础地址。
///
/// 语义：只要服务器给出**任何 HTTP 响应**（含 404）即视为在线；
/// 超时或传输层异常（SocketException 等）累计 [failureThreshold] 次才判定
/// 断网，避免单次抖动误报；一次成功立即恢复在线。
class NetworkStatusMonitor extends ChangeNotifier {
  NetworkStatusMonitor({
    required this.baseUrl,
    HttpTransport? transport,
    this.interval = const Duration(seconds: 5),
    this.probeTimeout = const Duration(seconds: 4),
    this.failureThreshold = 2,
  }) : _transport = transport ?? createHttpTransport();

  final String baseUrl;
  final HttpTransport _transport;
  final Duration interval;
  final Duration probeTimeout;
  final int failureThreshold;

  Timer? _timer;
  bool _online = true;
  bool _probing = false;
  int _consecutiveFailures = 0;

  bool get online => _online;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(probeNow()));
    unawaited(probeNow());
  }

  /// 立即探测一次（横幅“立即重试”入口）。
  Future<void> probeNow() async {
    if (_probing) return;
    _probing = true;
    try {
      final uri = Uri.parse(baseUrl.trim().replaceFirst(RegExp(r'/$'), ''));
      await _transport
          .send(method: 'GET', uri: uri, headers: const {'Accept': '*/*'})
          .timeout(probeTimeout);
      _consecutiveFailures = 0;
      _setOnline(true);
    } catch (_) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= failureThreshold) _setOnline(false);
    } finally {
      _probing = false;
    }
  }

  void _setOnline(bool value) {
    if (_online == value) return;
    _online = value;
    notifyListeners();
  }

  void disposeMonitor() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    disposeMonitor();
    super.dispose();
  }
}
