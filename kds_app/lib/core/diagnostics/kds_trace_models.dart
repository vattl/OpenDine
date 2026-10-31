import 'package:kds_app/core/config/kds_connection_mode.dart';

/// 追踪阶段枚举：区分「获取、发送、接收、响应、探针、系统」
enum KdsTraceStage {
  fetch('获取 (Fetch)', '从服务端拉取数据/快照/增量'),
  send('发送 (Send)', '向服务端发送操作指令/心跳'),
  receive('接收 (Receive)', '从 WebSocket/通知接收实时事件'),
  response('响应 (Response)', '服务端处理返回结果'),
  probe('探针 (Probe)', '网络链路连通性与延时探测'),
  system('系统 (System)', '通道切换/重连/本地调度');

  const KdsTraceStage(this.label, this.description);
  final String label;
  final String description;
}

/// 结构化追踪条目
class KdsTraceEntry {
  KdsTraceEntry({
    required this.id,
    required this.timestamp,
    required this.stage,
    required this.channel,
    required this.action,
    required this.summary,
    this.durationMs,
    this.statusCode,
    this.isSuccess = true,
    this.endpoint,
    this.requestPayload,
    this.responsePayload,
    this.requestId,
    this.commandId,
    this.deviceCode,
    this.metadata = const {},
  });

  final String id;
  final DateTime timestamp;
  final KdsTraceStage stage;
  final KdsActiveChannel channel;
  final String action;
  final String summary;
  final int? durationMs;
  final int? statusCode;
  final bool isSuccess;
  final String? endpoint;
  final dynamic requestPayload;
  final dynamic responsePayload;
  final String? requestId;
  final String? commandId;
  final String? deviceCode;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'stage': stage.name,
        'stage_label': stage.label,
        'channel': channel.name,
        'channel_label': channel.label,
        'action': action,
        'summary': summary,
        'duration_ms': durationMs,
        'status_code': statusCode,
        'is_success': isSuccess,
        'endpoint': endpoint,
        'request_payload': requestPayload,
        'response_payload': responsePayload,
        if (requestId != null) 'request_id': requestId,
        if (commandId != null) 'command_id': commandId,
        if (deviceCode != null) 'device_code': deviceCode,
        'metadata': metadata,
      };
}
