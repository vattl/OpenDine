import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/takeout_dispatch_alert.dart';
import 'takeout_dispatch_alert_source_base.dart';

TakeoutDispatchAlertSource createTakeoutDispatchAlertSource(String baseUrl) =>
    _IoTakeoutDispatchAlertSource(baseUrl);

class _IoTakeoutDispatchAlertSource implements TakeoutDispatchAlertSource {
  _IoTakeoutDispatchAlertSource(this.baseUrl);

  final String baseUrl;
  final StreamController<TakeoutDispatchAlert> _controller =
      StreamController<TakeoutDispatchAlert>.broadcast();
  WebSocket? _socket;
  Timer? _reconnectTimer;
  bool _started = false;
  bool _connecting = false;
  bool _closed = false;

  @override
  Stream<TakeoutDispatchAlert> get alerts => _controller.stream;

  @override
  void start() {
    if (_started || _closed) return;
    _started = true;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_closed || _connecting || _socket != null) return;
    _connecting = true;
    try {
      final base = Uri.parse(baseUrl.trim());
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws/menu',
        query: null,
        fragment: null,
      );
      final socket = await WebSocket.connect(
        uri.toString(),
      ).timeout(const Duration(seconds: 8));
      if (_closed) {
        await socket.close();
        return;
      }
      _socket = socket;
      socket.pingInterval = const Duration(seconds: 20);
      socket.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _onMessage(Object? raw) {
    if (raw is! String) return;
    try {
      final alert = TakeoutDispatchAlert.tryParse(jsonDecode(raw));
      if (alert != null) _controller.add(alert);
    } on FormatException {
      // Ignore unrelated or malformed frames; the socket remains healthy.
    }
  }

  void _onDisconnected() {
    _socket = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      unawaited(_connect());
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final socket = _socket;
    _socket = null;
    await socket?.close();
    await _controller.close();
  }
}
