import 'dart:async';

import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/diagnostics/kds_trace_models.dart';
import 'package:uuid/uuid.dart';

/// 全链路全景追踪中心：维护内存环形缓冲，记录 KDS 每一个获取、发送、接收与响应动作
class KdsTraceHub {
  KdsTraceHub._();

  static const int maxEntries = 500;
  static const _uuid = Uuid();

  static final List<KdsTraceEntry> _entries = [];
  static final _controller = StreamController<KdsTraceEntry>.broadcast();

  static Stream<KdsTraceEntry> get stream => _controller.stream;
  static List<KdsTraceEntry> get entries => List.unmodifiable(_entries);
  static int get count => _entries.length;

  /// 添加追踪记录
  static void record({
    required KdsTraceStage stage,
    required KdsActiveChannel channel,
    required String action,
    required String summary,
    int? durationMs,
    int? statusCode,
    bool isSuccess = true,
    String? endpoint,
    dynamic requestPayload,
    dynamic responsePayload,
    String? requestId,
    String? commandId,
    String? deviceCode,
    Map<String, dynamic> metadata = const {},
  }) {
    try {
      final entry = KdsTraceEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        stage: stage,
        channel: channel,
        action: action,
        summary: summary,
        durationMs: durationMs,
        statusCode: statusCode,
        isSuccess: isSuccess,
        endpoint: endpoint,
        requestPayload: requestPayload,
        responsePayload: responsePayload,
        requestId: requestId,
        commandId: commandId,
        deviceCode: deviceCode,
        metadata: metadata,
      );

      _entries.add(entry);
      while (_entries.length > maxEntries) {
        _entries.removeAt(0);
      }

      if (!_controller.isClosed) {
        _controller.add(entry);
      }
    } catch (_) {
      // 保证诊断引擎任何异常均不影响业务执行
    }
  }

  /// 记录获取 (Fetch)
  static void recordFetch({
    required KdsActiveChannel channel,
    required String action,
    required String summary,
    required String endpoint,
    int? durationMs,
    int? statusCode,
    bool isSuccess = true,
    dynamic responsePayload,
    String? requestId,
    String? commandId,
    String? deviceCode,
    Map<String, dynamic> metadata = const {},
  }) {
    record(
      stage: KdsTraceStage.fetch,
      channel: channel,
      action: action,
      summary: summary,
      endpoint: endpoint,
      durationMs: durationMs,
      statusCode: statusCode,
      isSuccess: isSuccess,
      responsePayload: responsePayload,
      requestId: requestId,
      commandId: commandId,
      deviceCode: deviceCode,
      metadata: metadata,
    );
  }

  /// 记录发送 (Send)
  static void recordSend({
    required KdsActiveChannel channel,
    required String action,
    required String summary,
    required String endpoint,
    int? durationMs,
    int? statusCode,
    bool isSuccess = true,
    dynamic requestPayload,
    dynamic responsePayload,
    String? requestId,
    String? commandId,
    String? deviceCode,
    Map<String, dynamic> metadata = const {},
  }) {
    record(
      stage: KdsTraceStage.send,
      channel: channel,
      action: action,
      summary: summary,
      endpoint: endpoint,
      durationMs: durationMs,
      statusCode: statusCode,
      isSuccess: isSuccess,
      requestPayload: requestPayload,
      responsePayload: responsePayload,
      requestId: requestId,
      commandId: commandId,
      deviceCode: deviceCode,
      metadata: metadata,
    );
  }

  /// 记录接收 (Receive: 如 WebSocket 消息推送)
  static void recordReceive({
    required KdsActiveChannel channel,
    required String action,
    required String summary,
    dynamic payload,
    String? requestId,
    String? commandId,
    String? deviceCode,
    Map<String, dynamic> metadata = const {},
  }) {
    record(
      stage: KdsTraceStage.receive,
      channel: channel,
      action: action,
      summary: summary,
      responsePayload: payload,
      requestId: requestId,
      commandId: commandId,
      deviceCode: deviceCode,
      metadata: metadata,
    );
  }

  /// 记录响应 (Response)
  static void recordResponse({
    required KdsActiveChannel channel,
    required String action,
    required String summary,
    required String endpoint,
    int? durationMs,
    int? statusCode,
    bool isSuccess = true,
    dynamic responsePayload,
    String? requestId,
    String? commandId,
    String? deviceCode,
    Map<String, dynamic> metadata = const {},
  }) {
    record(
      stage: KdsTraceStage.response,
      channel: channel,
      action: action,
      summary: summary,
      endpoint: endpoint,
      durationMs: durationMs,
      statusCode: statusCode,
      isSuccess: isSuccess,
      responsePayload: responsePayload,
      requestId: requestId,
      commandId: commandId,
      deviceCode: deviceCode,
      metadata: metadata,
    );
  }

  /// 记录探针 (Probe)
  static void recordProbe({
    required KdsActiveChannel channel,
    required String target,
    required String summary,
    required bool isSuccess,
    int? durationMs,
    String? requestId,
    String? commandId,
    String? deviceCode,
    Map<String, dynamic> metadata = const {},
  }) {
    record(
      stage: KdsTraceStage.probe,
      channel: channel,
      action: 'PROBE_$target',
      summary: summary,
      isSuccess: isSuccess,
      durationMs: durationMs,
      requestId: requestId,
      commandId: commandId,
      deviceCode: deviceCode,
      metadata: metadata,
    );
  }

  /// 记录系统/调度事件 (System)
  static void recordSystem({
    required KdsActiveChannel channel,
    required String action,
    required String summary,
    String? requestId,
    String? commandId,
    String? deviceCode,
    Map<String, dynamic> metadata = const {},
  }) {
    record(
      stage: KdsTraceStage.system,
      channel: channel,
      action: action,
      summary: summary,
      requestId: requestId,
      commandId: commandId,
      deviceCode: deviceCode,
      metadata: metadata,
    );
  }

  /// 清空追踪缓冲
  static void clear() {
    _entries.clear();
    record(
      stage: KdsTraceStage.system,
      channel: KdsActiveChannel.lan,
      action: 'CLEAR',
      summary: '追踪缓冲已清空',
    );
  }
}
