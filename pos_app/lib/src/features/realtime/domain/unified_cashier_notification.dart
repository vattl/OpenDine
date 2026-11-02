/// B 端收银统一实时通知领域模型
class UnifiedCashierNotification {
  UnifiedCashierNotification({
    required this.messageId,
    required this.seqId,
    required this.businessType,
    required this.eventType,
    required this.priority,
    required this.requireAck,
    required this.payload,
    this.displayStrategy = const {},
    this.isRead = false,
  });

  final String messageId;
  final int seqId;
  final String businessType;
  final String eventType;
  final String priority;
  final bool requireAck;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> displayStrategy;
  bool isRead;

  String get title {
    switch (eventType) {
      case 'ORDER_PREP_TIMEOUT':
        final table = payload['table_number']?.toString();
        final orderNo = payload['order_no']?.toString() ?? '';
        final location = (table != null && table.isNotEmpty) ? '桌号 $table' : '订单 $orderNo';
        return '🚨 $location 超时未出餐！';
      case 'NEW_ORDER_PAID':
        final table = payload['table_number']?.toString();
        final location = (table != null && table.isNotEmpty) ? '桌号 $table' : '新订单';
        return '🔔 $location 支付成功';
      case 'REFUND_REQUESTED':
        return '⚠️ 顾客申请整单退款';
      case 'MEAL_PICKUP_READY':
        return '🍲 餐品已制作完成';
      default:
        return '业务通知 ($eventType)';
    }
  }

  String get summary {
    switch (eventType) {
      case 'ORDER_PREP_TIMEOUT':
        final elapsed = payload['elapsed_minutes'] ?? 0;
        final threshold = payload['timeout_threshold_minutes'] ?? 15;
        return '已超出出餐时长 $elapsed 分钟 (阈值: $threshold 分钟)，请及时催促厨房或处理。';
      case 'NEW_ORDER_PAID':
        final amount = payload['paid_amount'] ?? 0.0;
        final diners = payload['dine_in_or_take_out'] ?? '堂食';
        return '$diners 实付 ¥$amount 元，请核对。';
      case 'REFUND_REQUESTED':
        final reason = payload['reason'] ?? '顾客申请退款';
        return '$reason，请在收银台审核。';
      default:
        return payload['message']?.toString() ?? '请注意查看最新业务状态。';
    }
  }

  String get ttsText =>
      displayStrategy['tts_text']?.toString() ??
      displayStrategy['ttsText']?.toString() ??
      summary;

  factory UnifiedCashierNotification.fromJson(Map<String, dynamic> json) {
    final payloadRaw = json['payload'];
    final displayRaw = json['display_strategy'] ?? json['displayStrategy'];

    return UnifiedCashierNotification(
      messageId: json['message_id']?.toString() ?? json['messageId']?.toString() ?? '',
      seqId: (json['seq_id'] as num?)?.toInt() ?? (json['seqId'] as num?)?.toInt() ?? 0,
      businessType: json['business_type']?.toString() ?? json['businessType']?.toString() ?? 'SYSTEM',
      eventType: json['event_type']?.toString() ?? json['eventType']?.toString() ?? 'UNKNOWN',
      priority: json['priority']?.toString() ?? 'P2',
      requireAck: json['require_ack'] == true || json['requireAck'] == true,
      payload: payloadRaw is Map ? payloadRaw.cast<String, dynamic>() : {},
      displayStrategy: displayRaw is Map ? displayRaw.cast<String, dynamic>() : {},
      isRead: json['read_status'] == 1 || json['readStatus'] == 1,
    );
  }
}
