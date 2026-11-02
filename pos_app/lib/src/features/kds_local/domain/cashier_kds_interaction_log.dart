enum KdsInteractionSide {
  kds('kds', 'KDS'),
  cashier('cashier', '收银端'),
  cloud('cloud', '云端');

  const KdsInteractionSide(this.wireName, this.label);
  final String wireName;
  final String label;

  static KdsInteractionSide parse(Object? value) => values.firstWhere(
    (item) => item.wireName == '$value',
    orElse: () => KdsInteractionSide.cashier,
  );
}

enum KdsInteractionDirection {
  inbound('inbound'),
  outbound('outbound'),
  internal('internal');

  const KdsInteractionDirection(this.wireName);
  final String wireName;

  static KdsInteractionDirection parse(Object? value) => values.firstWhere(
    (item) => item.wireName == '$value',
    orElse: () => KdsInteractionDirection.internal,
  );
}

enum KdsInteractionStage {
  proxyHttpForward('proxy_http_forward', 'HTTP 代理转发'),
  proxyWebSocketForward('proxy_websocket_forward', 'WebSocket 代理转发'),
  kdsCommandReceived('kds_command_received', '接收 KDS 指令'),
  kdsCommandAuthorized('kds_command_authorized', '鉴权与校验'),
  localProjectionApply('local_projection_apply', '应用本地投影'),
  cloudEventQueued('cloud_event_queued', '进入云端队列'),
  cloudEventSend('cloud_event_send', '提交云端'),
  cloudEventAck('cloud_event_ack', '云端确认'),
  kdsCommandResponse('kds_command_response', '响应 KDS'),
  cloudDeliveryReceived('cloud_delivery_received', '接收云端事件'),
  cloudDeliveryApply('cloud_delivery_apply', '应用云端事件'),
  cloudCursorCommit('cloud_cursor_commit', '提交同步游标'),
  cloudDeliveryAck('cloud_delivery_ack', '确认云端下发'),
  kdsEventPush('kds_event_push', '推送 KDS');

  const KdsInteractionStage(this.wireName, this.label);
  final String wireName;
  final String label;

  static KdsInteractionStage parse(Object? value) => values.firstWhere(
    (item) => item.wireName == '$value',
    orElse: () => KdsInteractionStage.localProjectionApply,
  );
}

enum KdsInteractionStatus {
  received('received', '已接收'),
  processing('processing', '处理中'),
  queued('queued', '已排队'),
  sent('sent', '已推送'),
  responded('responded', '已响应'),
  succeeded('succeeded', '成功'),
  duplicate('duplicate', '重复事件'),
  retrying('retrying', '等待重试'),
  rejected('rejected', '已拒绝'),
  failed('failed', '失败'),
  noRecipient('no_recipient', '无在线 KDS'),
  deadLetter('dead_letter', '死信隔离');

  const KdsInteractionStatus(this.wireName, this.label);
  final String wireName;
  final String label;

  bool get isProblem => const {
    KdsInteractionStatus.retrying,
    KdsInteractionStatus.rejected,
    KdsInteractionStatus.failed,
    KdsInteractionStatus.noRecipient,
    KdsInteractionStatus.deadLetter,
  }.contains(this);

  static KdsInteractionStatus parse(Object? value) => values.firstWhere(
    (item) => item.wireName == '$value',
    orElse: () => KdsInteractionStatus.failed,
  );
}

class CashierKdsInteractionLogDraft {
  const CashierKdsInteractionLogDraft({
    required this.traceId,
    required this.shopId,
    required this.source,
    required this.target,
    required this.direction,
    required this.stage,
    required this.action,
    required this.status,
    required this.occurredAtMs,
    this.orderId,
    this.orderNo,
    this.eventId,
    this.operationId,
    this.cursor,
    this.attempt = 1,
    this.httpStatus,
    this.businessCode,
    this.durationMs,
    this.deviceCode,
    this.errorType,
    this.errorSummary,
    this.metadata = const {},
  });

  final String traceId;
  final int shopId;
  final int? orderId;
  final String? orderNo;
  final String? eventId;
  final String? operationId;
  final int? cursor;
  final KdsInteractionSide source;
  final KdsInteractionSide target;
  final KdsInteractionDirection direction;
  final KdsInteractionStage stage;
  final String action;
  final KdsInteractionStatus status;
  final int attempt;
  final int? httpStatus;
  final String? businessCode;
  final int? durationMs;
  final String? deviceCode;
  final String? errorType;
  final String? errorSummary;
  final Map<String, Object?> metadata;
  final int occurredAtMs;
}

class CashierKdsInteractionLog {
  const CashierKdsInteractionLog({
    required this.id,
    required this.traceId,
    required this.shopId,
    required this.source,
    required this.target,
    required this.direction,
    required this.stage,
    required this.action,
    required this.status,
    required this.attempt,
    required this.metadata,
    required this.occurredAtMs,
    required this.createdAtMs,
    this.orderId,
    this.orderNo,
    this.eventId,
    this.operationId,
    this.cursor,
    this.httpStatus,
    this.businessCode,
    this.durationMs,
    this.deviceCode,
    this.errorType,
    this.errorSummary,
  });

  final int id;
  final String traceId;
  final int shopId;
  final int? orderId;
  final String? orderNo;
  final String? eventId;
  final String? operationId;
  final int? cursor;
  final KdsInteractionSide source;
  final KdsInteractionSide target;
  final KdsInteractionDirection direction;
  final KdsInteractionStage stage;
  final String action;
  final KdsInteractionStatus status;
  final int attempt;
  final int? httpStatus;
  final String? businessCode;
  final int? durationMs;
  final String? deviceCode;
  final String? errorType;
  final String? errorSummary;
  final Map<String, Object?> metadata;
  final int occurredAtMs;
  final int createdAtMs;

  String get pathLabel => '${source.label} → ${target.label}';

  String get faultLabel {
    if (!status.isProblem) return '—';
    if (stage == KdsInteractionStage.proxyHttpForward ||
        stage == KdsInteractionStage.proxyWebSocketForward) {
      return httpStatus == null ? '收银到云端网络' : '云端接口/业务处理';
    }
    if (stage == KdsInteractionStage.cloudEventSend) {
      return httpStatus == null ? '收银到云端网络' : '云端接口/业务处理';
    }
    if (stage == KdsInteractionStage.cloudDeliveryReceived ||
        stage == KdsInteractionStage.cloudDeliveryAck) {
      return '云端下发链路';
    }
    if (stage == KdsInteractionStage.kdsEventPush ||
        stage == KdsInteractionStage.kdsCommandResponse) {
      return 'KDS 离线或局域网';
    }
    if (stage == KdsInteractionStage.kdsCommandReceived) {
      return 'KDS 请求或设备配置';
    }
    return '收银端本地处理';
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'trace_id': traceId,
    'shop_id': shopId,
    'order_id': orderId,
    'order_no': orderNo,
    'event_id': eventId,
    'operation_id': operationId,
    'cursor': cursor,
    'source': source.wireName,
    'target': target.wireName,
    'direction': direction.wireName,
    'stage': stage.wireName,
    'stage_label': stage.label,
    'action': action,
    'status': status.wireName,
    'status_label': status.label,
    'attempt': attempt,
    'http_status': httpStatus,
    'business_code': businessCode,
    'duration_ms': durationMs,
    'device_code': deviceCode,
    'error_type': errorType,
    'error_summary': errorSummary,
    'metadata': metadata,
    'occurred_at_ms': occurredAtMs,
    'created_at_ms': createdAtMs,
    'path_label': pathLabel,
    'fault_label': faultLabel,
  };
}

class CashierKdsInteractionLogFilter {
  const CashierKdsInteractionLogFilter({
    required this.shopId,
    this.traceId,
    this.keyword,
    this.fromMs,
    this.toMs,
    this.statuses = const {},
    this.stages = const {},
    this.limit = 100,
    this.offset = 0,
  });

  final int shopId;
  final String? traceId;
  final String? keyword;
  final int? fromMs;
  final int? toMs;
  final Set<KdsInteractionStatus> statuses;
  final Set<KdsInteractionStage> stages;
  final int limit;
  final int offset;
}
