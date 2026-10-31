import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:kds_app/core/api/api_response.dart';
import 'package:kds_app/core/config/api_base_util.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/diagnostics/kds_trace_hub.dart';
import 'package:kds_app/core/ws/kds_ws_logger.dart';
import 'package:kds_app/core/ws/kds_ws_uri.dart';
import 'package:kds_app/core/ws/kds_ws_connect_io.dart'
    if (dart.library.js_interop) 'package:kds_app/core/ws/kds_ws_connect_web.dart'
    if (dart.library.html) 'package:kds_app/core/ws/kds_ws_connect_web.dart'
    as kds_ws_connect;
import 'package:web_socket_channel/web_socket_channel.dart';

class KdsWsEvent {
  KdsWsEvent({
    required this.type,
    this.raw = const {},
    this.screenTag,
    this.payload,
  });

  final String type;
  final String? screenTag;
  final Map<String, dynamic>? payload;
  final Map<String, dynamic> raw;

  factory KdsWsEvent.fromJson(Map<String, dynamic> json) {
    return KdsWsEvent(
      type: json['type'] as String? ?? '',
      raw: Map.unmodifiable(json),
      screenTag: json['screen_tag'] as String?,
      payload: asJsonMap(json['payload']),
    );
  }
}

class KdsWebSocketService {
  KdsWebSocketService({
    required this.getBaseUrl,
    required this.getShopId,
    required this.getScreenTag,
    required this.getToken,
    this.getWorkflows,
    this.pingInterval = const Duration(seconds: 15),
    this.pongTimeout = const Duration(seconds: 10),
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.reconnectMaxDelay = const Duration(seconds: 30),
    this.reconnectJitterMax = const Duration(milliseconds: 500),
    this.onUnauthorized,
  });

  final String Function() getBaseUrl;
  final int? Function() getShopId;
  final String? Function() getScreenTag;
  final String? Function() getToken;
  final List<String> Function()? getWorkflows;
  final Duration pingInterval;
  final Duration pongTimeout;
  final Duration reconnectBaseDelay;
  final Duration reconnectMaxDelay;
  final Duration reconnectJitterMax;
  final void Function()? onUnauthorized;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _pingTimer;
  Timer? _pongTimer;
  Timer? _reconnectTimer;

  int _reconnectAttempt = 0;
  bool _disposed = false;

  final _connectedCtrl = StreamController<bool>.broadcast();
  final _eventCtrl = StreamController<KdsWsEvent>.broadcast();
  final List<KdsWsEvent> _bufferedEvents = [];
  static const int _maxBufferedEvents = 512;

  Stream<bool> get connectedStream => _connectedCtrl.stream;
  Stream<KdsWsEvent> get eventStream => _eventCtrl.stream;

  List<KdsWsEvent> drainBufferedEvents() {
    final result = List<KdsWsEvent>.unmodifiable(_bufferedEvents);
    _bufferedEvents.clear();
    return result;
  }

  bool get isConnected => _channel != null;

  void connect() {
    _startConnection(resetBackoff: true);
  }

  void _startConnection({required bool resetBackoff}) {
    disconnect(reconnect: !resetBackoff);
    unawaited(_connectInternal());
  }

  Future<void> _connectInternal() async {
    final base = getBaseUrl();
    final shopId = getShopId();
    final screenTag = getScreenTag();
    final token = getToken();
    if (shopId == null) {
      KdsWsLogger.skipConnect('shop_id is null');
      _emitConnected(false);
      return;
    }
    if (screenTag == null || screenTag.isEmpty) {
      KdsWsLogger.skipConnect('screen_tag is null');
      _emitConnected(false);
      return;
    }
    if (token == null || token.isEmpty) {
      KdsWsLogger.skipConnect('token is empty');
      _emitConnected(false);
      return;
    }

    Uri uri;
    try {
      uri = buildKdsWebSocketUri(
        apiBase: base,
        shopId: shopId,
        screenTag: screenTag,
      );
    } on ArgumentError catch (e) {
      KdsWsLogger.skipConnect(e.message?.toString() ?? 'invalid api base');
      _emitConnected(false);
      return;
    }
    KdsWsLogger.connecting(uri);
    KdsWsLogger.connectorSelected(kds_ws_connect.kdsWsConnectorPlatform);

    try {
      final channel = kds_ws_connect.connectKdsWebSocket(
        uri,
        deviceToken: token,
        legacyQueryToken: false,
      );
      await channel.ready.timeout(const Duration(seconds: 15));
      if (_disposed) {
        KdsWsLogger.disconnected(reason: 'disposed during handshake');
        await channel.sink.close();
        return;
      }

      _channel = channel;
      _emitConnected(true);
      KdsWsLogger.connected(uri);

      _pingTimer = Timer.periodic(pingInterval, (_) {
        KdsWsLogger.ping();
        _channel?.sink.add('ping');
        _pongTimer ??= Timer(pongTimeout, _handlePongTimeout);
      });

      _sub = _channel!.stream.listen(
        _onMessage,
        onDone: () {
          final code = _channel?.closeCode;
          final reason = _channel?.closeReason;
          final detail = [
            if (code != null) 'code: $code',
            if (reason != null && reason.isNotEmpty) 'reason: $reason',
          ].join(', ');
          KdsWsLogger.disconnected(
              reason:
                  detail.isNotEmpty ? 'stream done ($detail)' : 'stream done');
          _emitConnected(false);
          final isPolicyViolation = code == 1008 ||
              (reason != null &&
                  (reason.contains('invalid token') ||
                      reason.contains('missing token') ||
                      reason.contains('mismatch')));
          if (isPolicyViolation) {
            KdsWsLogger.disconnected(reason: 'WS 凭据失效或鉴权被拒，触发重新登录');
            onUnauthorized?.call();
          } else {
            _scheduleReconnect();
          }
        },
        onError: (err) {
          KdsWsLogger.streamError(err);
          _emitConnected(false);
          _scheduleReconnect();
        },
      );
    } catch (err, stack) {
      KdsWsLogger.connectError(err, stack, uri);
      _emitConnected(false);
      _scheduleReconnect();
    }
  }

  void _emitConnected(bool value) {
    if (_disposed) return;
    _connectedCtrl.add(value);
    KdsWsLogger.stateChanged(connected: value);
    final base = getBaseUrl();
    final channel = isPrivateLanApiBase(base)
        ? KdsActiveChannel.lan
        : KdsActiveChannel.cloud;
    KdsTraceHub.recordSystem(
      channel: channel,
      action: value ? 'WS_CONNECTED' : 'WS_DISCONNECTED',
      summary: value ? 'WebSocket 连接已建立 ($base)' : 'WebSocket 连接已断开',
      metadata: {'url': base},
    );
  }

  void _onMessage(dynamic raw) {
    final text = raw.toString();
    if (text == 'pong' || text.trim() == 'pong') {
      _reconnectAttempt = 0;
      _pongTimer?.cancel();
      _pongTimer = null;
      KdsWsLogger.pong();
      return;
    }

    KdsWsLogger.rxRaw(text);

    Map<String, dynamic>? json;
    try {
      json = jsonDecode(text) as Map<String, dynamic>;
    } catch (err) {
      KdsWsLogger.parseError(text, err);
      return;
    }

    final event = KdsWsEvent.fromJson(json);
    if (event.type == 'pong') {
      _reconnectAttempt = 0;
      _pongTimer?.cancel();
      _pongTimer = null;
      KdsWsLogger.pong();
      return;
    }

    final base = getBaseUrl();
    final channel = isPrivateLanApiBase(base)
        ? KdsActiveChannel.lan
        : KdsActiveChannel.cloud;
    KdsTraceHub.recordReceive(
      channel: channel,
      action: 'WS_${event.type}',
      summary: '收到实时事件: ${event.type}',
      payload: json,
      metadata: {
        'event_seq': json['event_seq'] ?? json['eventSeq'],
        'event_id': json['event_id'] ?? json['eventId'],
        'shop_id': json['shop_id'] ?? json['shopId'],
      },
    );

    KdsWsLogger.eventAccepted(event,
        boundTag: getScreenTag(), workflows: getWorkflows?.call() ?? const []);
    _reconnectAttempt = 0;
    if (!_eventCtrl.hasListener) {
      _bufferedEvents.add(event);
      if (_bufferedEvents.length > _maxBufferedEvents) {
        _bufferedEvents.removeAt(0);
      }
    }
    _eventCtrl.add(event);
    _acknowledge(event);
  }

  void _acknowledge(KdsWsEvent event) {
    final eventSeq = event.raw['event_seq'] ?? event.raw['eventSeq'];
    final eventId = event.raw['event_id'] ?? event.raw['eventId'];
    if (eventSeq is! int ||
        eventSeq <= 0 ||
        eventId is! String ||
        eventId.isEmpty) {
      return;
    }
    try {
      _channel?.sink.add(jsonEncode({
        'protocol_version': 2,
        'type': 'ack',
        'event_seq': eventSeq,
        'event_id': eventId,
      }));
    } catch (error) {
      KdsWsLogger.streamError(error);
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_reconnectTimer?.isActive ?? false) return;
    _reconnectAttempt++;
    final baseMs = (reconnectBaseDelay.inMilliseconds *
            (1 << _reconnectAttempt.clamp(0, 20)))
        .clamp(
      reconnectBaseDelay.inMilliseconds,
      reconnectMaxDelay.inMilliseconds,
    );
    final jitterLimit = reconnectJitterMax.inMilliseconds;
    final jitterMs =
        jitterLimit <= 0 ? 0 : Random.secure().nextInt(jitterLimit);
    final delayMs = baseMs + jitterMs;
    KdsWsLogger.reconnectScheduled(
        attempt: _reconnectAttempt, delayMs: delayMs);
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _reconnectTimer = null;
      _startConnection(resetBackoff: false);
    });
  }

  void _handlePongTimeout() {
    if (_disposed || _channel == null) return;
    KdsWsLogger.disconnected(reason: 'pong timeout');
    _emitConnected(false);
    disconnect();
    _scheduleReconnect();
  }

  void disconnect({bool reconnect = true}) {
    if (_channel != null) {
      KdsWsLogger.disconnected(reason: reconnect ? 'reconnecting' : 'manual');
    }
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!reconnect) _reconnectAttempt = 0;
  }

  void dispose() {
    KdsWsLogger.sessionDetach();
    _disposed = true;
    _bufferedEvents.clear();
    disconnect(reconnect: false);
    _connectedCtrl.close();
    _eventCtrl.close();
  }
}
