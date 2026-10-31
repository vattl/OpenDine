import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/unified_cashier_notification.dart';

/// B 端收银统一实时通知与告警中枢管理器 (/ws/v1/notify)
class UnifiedCashierNotifyCenter extends ChangeNotifier {
  UnifiedCashierNotifyCenter({
    required this.baseUrl,
    required this.client,
    this.shopId = 1,
    this.deviceId = 'POS-01',
  });

  final String baseUrl;
  final AdminApiClient client;
  int shopId;
  String deviceId;

  WebSocket? _socket;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  bool _started = false;
  bool _connected = false;
  int _lastSeqId = 0;

  // 待处理 P0 告警列表（如出餐超时、退款审批）
  final List<UnifiedCashierNotification> _activeP0Alerts = [];
  // 最近通知收件箱（前 50 条）
  final List<UnifiedCashierNotification> _inbox = [];

  bool get isConnected => _connected;
  List<UnifiedCashierNotification> get activeP0Alerts =>
      List.unmodifiable(_activeP0Alerts);
  List<UnifiedCashierNotification> get inbox => List.unmodifiable(_inbox);
  int get unreadCount => _inbox.where((n) => !n.isRead).length;

  /// 单独回调，供收银台触发独占语音/TTS 播报与右侧滑入通知卡片
  ValueChanged<UnifiedCashierNotification>? onNotificationReceived;

  void start() {
    if (_started) return;
    _started = true;
    _connect();
  }

  void updateShopId(int newShopId) {
    if (shopId == newShopId) return;
    shopId = newShopId;
    _activeP0Alerts.clear();
    _inbox.clear();
    _lastSeqId = 0;
    notifyListeners();
    _reconnect();
  }

  Future<void> _connect() async {
    if (!_started || _socket != null) return;

    try {
      final base = Uri.parse(baseUrl.trim());
      final token = client.token ?? '';
      final uri = base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws/v1/notify',
        queryParameters: {
          'client_type': 'CASHIER',
          'shop_id': '$shopId',
          if (token.isNotEmpty) 'token': token,
          'device_id': deviceId,
          'last_seq_id': '$_lastSeqId',
        },
      );

      final socket =
          await WebSocket.connect(uri.toString()).timeout(const Duration(seconds: 8));
      _socket = socket;
      _connected = true;
      notifyListeners();

      socket.listen(
        _onMessage,
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: true,
      );

      _startHeartbeat();
      // 连接成功后，触发一次增量同步补漏
      await syncIncremental();
    } catch (_) {
      _onDisconnected();
    }
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;

      final frameType = json['frame_type'] as String? ?? 'EVENT';
      if (frameType == 'PONG') return;

      final envelope = UnifiedCashierNotification.fromJson(json);
      if (envelope.seqId > _lastSeqId) {
        _lastSeqId = envelope.seqId;
      }

      _handleIncomingNotification(envelope);
    } catch (_) {}
  }

  void _handleIncomingNotification(UnifiedCashierNotification item) {
    // 跨机协同消警事件处理
    if (item.eventType == 'ALERT_DISMISSED') {
      final dismissedIds = item.payload['dismissed_message_ids'];
      if (dismissedIds is List) {
        final idsSet = dismissedIds.map((e) => '$e').toSet();
        _activeP0Alerts.removeWhere((a) => idsSet.contains(a.messageId));
        for (final m in _inbox) {
          if (idsSet.contains(m.messageId)) {
            m.isRead = true;
          }
        }
        notifyListeners();
      }
      return;
    }

    // 加入收件箱
    _inbox.insert(0, item);
    if (_inbox.length > 50) {
      _inbox.removeLast();
    }

    // P0 紧急告警（出餐超时/退单强提醒）放入常驻待办
    if (item.priority == 'P0') {
      _activeP0Alerts.removeWhere((a) => a.messageId == item.messageId);
      _activeP0Alerts.insert(0, item);
    }

    notifyListeners();
    onNotificationReceived?.call(item);
  }

  /// 断线重连或手动拉取增量通知 (GET /cashier/notifications/sync)
  Future<void> syncIncremental() async {
    try {
      final res = await client.get(
        cashierNotificationsSyncEndpoint,
        query: {
          'shop_id': shopId,
          'client_type': 'CASHIER',
          'last_seq_id': _lastSeqId,
          'limit': 50,
        },
      );
      if (res is Map) {
        final data = res['data'] as Map<String, dynamic>? ?? res.cast<String, dynamic>();
        final items = data['items'];
        if (items is List) {
          for (final raw in items) {
            if (raw is Map<String, dynamic>) {
              final ntf = UnifiedCashierNotification.fromJson(raw);
              if (ntf.seqId > _lastSeqId) {
                _lastSeqId = ntf.seqId;
              }
              _handleIncomingNotification(ntf);
            }
          }
        }
      }
    } catch (_) {}
  }

  /// 一键已知晓消警并触发同店所有 POS 广播消警 (POST /cashier/notifications/ack)
  Future<void> acknowledge(String messageId) async {
    _activeP0Alerts.removeWhere((a) => a.messageId == messageId);
    for (final m in _inbox) {
      if (m.messageId == messageId) {
        m.isRead = true;
      }
    }
    notifyListeners();

    try {
      await client.post(
        cashierNotificationsAckEndpoint,
        body: {
          'shop_id': shopId,
          'message_ids': [messageId],
        },
      );
    } catch (_) {}
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_socket != null && _connected) {
        try {
          _socket!.add(jsonEncode({'frame_type': 'PING', 'timestamp': DateTime.now().millisecondsSinceEpoch}));
        } catch (_) {
          _onDisconnected();
        }
      }
    });
  }

  void _onDisconnected() {
    _connected = false;
    _socket = null;
    _heartbeatTimer?.cancel();
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_started || _reconnectTimer != null) return;
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      _reconnectTimer = null;
      _connect();
    });
  }

  void _reconnect() {
    _socket?.close();
    _socket = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connect();
  }

  @override
  void dispose() {
    _started = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
