import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 收银云端事件 WebSocket 唤醒通道客户端（openapi v1.2.189 `GET /ws/cashier-events`）。
///
/// 服务端建连后仅推送 `kds_delivery_available` 与 `headCursor` 两种信号；
/// 客户端收到后应调用 `/cashier/kds/delivery/events`（按 headCursor 拉取投递事件），
/// **不得**直接用 WS payload 创建本地订单。WS 断开不影响可靠性，客户端继续长轮询。
class CashierCloudEventsClient {
  CashierCloudEventsClient({
    required this.wsUrl,
    required this.token,
    required this.shopId,
    required this.onWake,
    this.deviceCode = '',
    this.authorityEpoch = '',
    this.leaseToken = '',
    this.reconnectBaseDelay = const Duration(seconds: 2),
    this.reconnectMaxDelay = const Duration(seconds: 30),
    CashierCloudWebSocketConnector? connector,
  }) : _connector = connector ?? WebSocket.connect;

  final String wsUrl;
  final String token;
  final int shopId;

  /// 收银设备标识（X-Cashier-Device-Code）；为空时不发送该头。
  final String deviceCode;

  /// 收银权威纪元（X-Cashier-Authority-Epoch）；为空时不发送该头。
  final String authorityEpoch;

  /// 收银租约令牌（X-Cashier-Lease-Token）；为空时不发送该头。
  final String leaseToken;

  final ValueChanged<CashierCloudWakeEvent> onWake;
  final Duration reconnectBaseDelay;
  final Duration reconnectMaxDelay;
  final CashierCloudWebSocketConnector _connector;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connected = false;
  int _attempt = 0;

  /// 当前是否保持连接（未释放且握手成功）。
  bool get isConnected => _connected && !_disposed;

  /// 建立连接；失败/断开后自动指数退避重连，直到 [dispose]。
  Future<void> connect() async {
    if (_disposed) return;
    try {
      final headers = <String, String>{
        'Authorization': 'Bearer $token',
        'X-Shop-Id': '$shopId',
        if (deviceCode.isNotEmpty) 'X-Cashier-Device-Code': deviceCode,
        if (authorityEpoch.isNotEmpty) 'X-Cashier-Authority-Epoch': authorityEpoch,
        if (leaseToken.isNotEmpty) 'X-Cashier-Lease-Token': leaseToken,
      };
      final socket = await _connector(wsUrl, headers: headers);
      if (_disposed) {
        await socket.close(WebSocketStatus.goingAway, 'disposed');
        return;
      }
      _socket = socket;
      _connected = true;
      _attempt = 0;
      _subscription = socket.listen(
        _onFrame,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic frame) {
    if (frame is! String) return;
    final event = CashierCloudWakeEvent.tryParse(frame);
    if (event == null) return;
    try {
      onWake(event);
    } catch (_) {
      // 回调异常不中断唤醒通道。
    }
  }

  void _scheduleReconnect([dynamic _]) {
    if (_disposed) return;
    _connected = false;
    _subscription?.cancel();
    _subscription = null;
    _socket = null;
    final delay = _nextDelay();
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_disposed) unawaited(connect());
    });
  }

  Duration _nextDelay() {
    final shifted = reconnectBaseDelay.inMilliseconds * (1 << _attempt.clamp(0, 8));
    final capped = shifted.clamp(0, reconnectMaxDelay.inMilliseconds);
    _attempt = (_attempt + 1).clamp(1, 16);
    return Duration(milliseconds: capped);
  }

  /// 释放连接并停止重连；释放后不可再 [connect]。
  Future<void> dispose() async {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    final socket = _socket;
    _socket = null;
    _connected = false;
    if (socket != null) {
      try {
        await socket.close(WebSocketStatus.goingAway, 'disposed');
      } catch (_) {
        // Socket 已断开时静默。
      }
    }
  }
}

typedef CashierCloudWebSocketConnector =
    Future<WebSocket> Function(String url, {Map<String, String>? headers});

/// 收银云端唤醒事件（`/ws/cashier-events` 帧）。
///
/// 服务端推送两种信号：`kds_delivery_available`（有投递事件可拉取）与
/// `headCursor`（当前事件游标）。帧内统一含 `ts`（毫秒时间戳）。
class CashierCloudWakeEvent {
  const CashierCloudWakeEvent({
    required this.type,
    this.headCursor,
    this.ts,
  });

  /// 事件类型：`kds_delivery_available` / `headCursor`。
  final String type;

  /// 事件游标（headCursor/head_cursor/cursor）；缺失时为 null。
  final int? headCursor;

  /// 服务端毫秒时间戳（ts）；缺失时为 null。
  final int? ts;

  bool get isDeliveryAvailable => type == 'kds_delivery_available';
  bool get isHeadCursor => type == 'headCursor';

  /// 解析 WS 文本帧；非 JSON 对象或缺少有效 type 时返回 null。
  static CashierCloudWakeEvent? tryParse(String frame) {
    Object? decoded;
    try {
      decoded = jsonDecode(frame);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;
    final type = decoded['type'];
    if (type is! String || type.trim().isEmpty) return null;
    final cursor = decoded['headCursor'] ?? decoded['head_cursor'] ?? decoded['cursor'];
    final tsValue = decoded['ts'];
    return CashierCloudWakeEvent(
      type: type.trim(),
      headCursor: cursor is num ? cursor.toInt() : int.tryParse('$cursor'),
      ts: tsValue is num ? tsValue.toInt() : int.tryParse('$tsValue'),
    );
  }
}
