class CashierOrderLineDraft {
  const CashierOrderLineDraft({
    required this.dishId,
    required this.dishName,
    required this.specification,
    required this.unit,
    required this.quantity,
    this.isCombo = false,
    this.comboName,
    this.comboId,
    this.cloudDetailId,
    this.cloudPayload = const {},
    this.servingDurationMinutes = 10,
  });

  final int dishId;
  final String dishName;
  final String specification;
  final String unit;
  final int quantity;
  final bool isCombo;
  final String? comboName;
  final int? comboId;
  final int? cloudDetailId;
  final Map<String, Object?> cloudPayload;
  final int servingDurationMinutes;

  Map<String, Object?> toJson() => {
    'dish_id': dishId,
    'dish_name': dishName,
    'specification': specification,
    'unit': unit,
    'quantity': quantity,
    'is_combo': isCombo,
    'combo': isCombo,
    'set_meal': isCombo,
    if (comboName != null && comboName!.isNotEmpty) 'combo_name': comboName,
    if (comboId != null && comboId! > 0) 'combo_id': comboId,
    if (cloudDetailId != null) 'cloud_detail_id': cloudDetailId,
    if (cloudPayload.isNotEmpty) 'cloud_payload': cloudPayload,
    'serving_duration_minutes': servingDurationMinutes,
  };
}

class CashierOrderDraft {
  const CashierOrderDraft({
    required this.shopId,
    required this.tableNumber,
    required this.fulfillmentType,
    required this.remark,
    required this.createdAtMs,
    required this.lines,
    this.numberOfDiners = 1,
  });

  final int shopId;
  final String tableNumber;
  final String fulfillmentType;
  final String remark;
  final int createdAtMs;
  final List<CashierOrderLineDraft> lines;
  final int numberOfDiners;
}

class CashierOrderReceipt {
  const CashierOrderReceipt({
    required this.orderId,
    required this.orderNo,
    this.duplicate = false,
    this.eventSeq = 0,
    this.eventId = '',
  });

  final int orderId;
  final String orderNo;
  final bool duplicate;
  final int eventSeq;
  final String eventId;
}

const cashierServeTicketPrintEventType = 'serve_ticket_print_requested';

enum LocalKdsCommandType {
  advanceItem('advance_item'),
  advanceOrder('advance_order'),
  revokeItem('revoke_item'),
  lackItem('lack_item'),
  refundItem('refund_item'),
  rushItem('rush_item'),
  rushOrder('rush_order'),
  holdItem('hold_item'),
  releaseItem('release_item'),
  completeOrder('complete_order'),
  archiveOrder('archive_order'),
  archiveClear('archive_clear');

  const LocalKdsCommandType(this.wireName);
  final String wireName;

  static LocalKdsCommandType parse(String value) => values.firstWhere(
    (type) => type.wireName == value,
    orElse: () => throw const CashierKdsValidation('unsupported command type'),
  );
}

class LocalKdsCommandTarget {
  const LocalKdsCommandTarget({
    this.orderId,
    this.detailId,
    this.detailIds = const [],
    this.fromQueue,
  });

  final int? orderId;
  final int? detailId;
  final List<int> detailIds;
  final String? fromQueue;

  Map<String, Object?> toJson() => {
    if (orderId != null) 'order_id': orderId,
    if (detailId != null) 'detail_id': detailId,
    if (detailIds.isNotEmpty) 'detail_ids': detailIds,
    if (fromQueue != null) 'from_queue': fromQueue,
  };
}

class LocalKdsCommand {
  const LocalKdsCommand({
    required this.commandId,
    required this.type,
    required this.shopId,
    required this.target,
    required this.occurredAtMs,
    this.quantity,
    this.expectedRevision,
    this.payload = const {},
    this.actorDeviceCode,
  });

  final String commandId;
  final LocalKdsCommandType type;
  final int shopId;
  final LocalKdsCommandTarget target;
  final int occurredAtMs;
  final int? quantity;
  final int? expectedRevision;
  final Map<String, Object?> payload;
  final String? actorDeviceCode;

  LocalKdsCommand copyWith({
    LocalKdsCommandTarget? target,
    int? occurredAtMs,
    int? expectedRevision,
    String? actorDeviceCode,
  }) => LocalKdsCommand(
    commandId: commandId,
    type: type,
    shopId: shopId,
    target: target ?? this.target,
    occurredAtMs: occurredAtMs ?? this.occurredAtMs,
    quantity: quantity,
    expectedRevision: expectedRevision ?? this.expectedRevision,
    payload: payload,
    actorDeviceCode: actorDeviceCode ?? this.actorDeviceCode,
  );

  Map<String, Object?> fingerprintJson() => {
    'shop_id': shopId,
    'type': type.wireName,
    'target': target.toJson(),
    if (quantity != null) 'quantity': quantity,
    if (expectedRevision != null) 'expected_revision': expectedRevision,
    if (payload.isNotEmpty) 'payload': payload,
    if (actorDeviceCode != null) 'actor_device_code': actorDeviceCode,
  };
}

class LocalKdsCommandResult {
  const LocalKdsCommandResult({
    required this.commandId,
    required this.eventSeq,
    required this.patches,
    required this.queueCounts,
    this.orderSummary,
    this.duplicate = false,
    this.actorDeviceCode,
  });

  final String commandId;
  final int eventSeq;
  final List<Map<String, Object?>> patches;
  final Map<String, int> queueCounts;
  final Map<String, Object?>? orderSummary;
  final bool duplicate;
  final String? actorDeviceCode;

  Map<String, Object?> toJson() => {
    'command_id': commandId,
    'duplicate': duplicate,
    'event_seq': eventSeq,
    'patches': patches,
    'queue_counts': queueCounts,
    if (orderSummary != null) 'order_summary': orderSummary,
    if (actorDeviceCode != null) 'actor_device_code': actorDeviceCode,
  };

  LocalKdsCommandResult asDuplicate() => LocalKdsCommandResult(
    commandId: commandId,
    eventSeq: eventSeq,
    patches: patches,
    queueCounts: queueCounts,
    orderSummary: orderSummary,
    duplicate: true,
    actorDeviceCode: actorDeviceCode,
  );

  factory LocalKdsCommandResult.fromJson(Map<String, Object?> json) {
    final rawPatches = json['patches'];
    final rawCounts = json['queue_counts'];
    return LocalKdsCommandResult(
      commandId: '${json['command_id'] ?? ''}',
      eventSeq: (json['event_seq'] as num?)?.toInt() ?? 0,
      patches: rawPatches is List
          ? rawPatches
                .whereType<Map>()
                .map((value) => value.cast<String, Object?>())
                .toList(growable: false)
          : const [],
      queueCounts: rawCounts is Map
          ? rawCounts.map(
              (key, value) => MapEntry('$key', (value as num?)?.toInt() ?? 0),
            )
          : const {},
      orderSummary: json['order_summary'] is Map
          ? (json['order_summary'] as Map).cast<String, Object?>()
          : null,
      duplicate: json['duplicate'] == true,
      actorDeviceCode: json['actor_device_code'] == null
          ? null
          : '${json['actor_device_code']}',
    );
  }
}

class CashierKdsChange {
  const CashierKdsChange({
    required this.eventSeq,
    required this.eventId,
    required this.type,
    required this.shopId,
    required this.occurredAtMs,
    required this.patches,
  });

  final int eventSeq;
  final String eventId;
  final String type;
  final int shopId;
  final int occurredAtMs;
  final List<Map<String, Object?>> patches;
}

class CashierKdsConfigSnapshot {
  const CashierKdsConfigSnapshot({
    required this.shopId,
    required this.version,
    required this.payload,
    required this.updatedAtMs,
    required this.expiresAtMs,
  });

  final int shopId;
  final int version;
  final Map<String, Object?> payload;
  final int updatedAtMs;
  final int expiresAtMs;

  Map<String, Object?>? get authorityDevice =>
      payload['cashier_authority'] is Map
      ? (payload['cashier_authority'] as Map).cast<String, Object?>()
      : payload['authority_device'] is Map
      ? (payload['authority_device'] as Map).cast<String, Object?>()
      : null;

  String? get authorityDeviceCode {
    final value =
        '${authorityDevice?['cashier_device_code'] ?? authorityDevice?['device_code'] ?? ''}'
            .trim();
    return value.isEmpty ? null : value;
  }

  String? get authorityEnforcement {
    final value = '${authorityDevice?['enforcement'] ?? ''}'.trim();
    return value.isEmpty ? null : value;
  }
}

class CashierWorkflowLine {
  const CashierWorkflowLine({
    required this.detailId,
    required this.orderId,
    required this.orderNo,
    required this.tableNumber,
    required this.fulfillmentType,
    required this.orderRemark,
    required this.dishId,
    required this.dishName,
    required this.specification,
    required this.unit,
    required this.lineQuantity,
    required this.prepRemaining,
    required this.cookRemaining,
    required this.readyRemaining,
    required this.refundedQuantity,
    required this.held,
    required this.rushed,
    required this.lacked,
    required this.workflowQueue,
    required this.localRevision,
    required this.orderRevision,
    required this.createdAtMs,
    this.cloudDetailId,
    this.cloudOrderId,
    this.completedAtMs,
    this.isCombo = false,
    this.comboName,
    this.comboId,
    this.servingDurationMinutes = 10,
  });

  final int detailId;
  final int orderId;
  final String orderNo;
  final String tableNumber;
  final String fulfillmentType;
  final String orderRemark;
  final int dishId;
  final String dishName;
  final String specification;
  final String unit;
  final int lineQuantity;
  final int prepRemaining;
  final int cookRemaining;
  final int readyRemaining;
  final int refundedQuantity;
  final bool held;
  final bool rushed;
  final bool lacked;
  final String workflowQueue;
  final int localRevision;
  final int orderRevision;
  final int createdAtMs;
  final int? cloudDetailId;
  final int? cloudOrderId;
  final int? completedAtMs;
  final bool isCombo;
  final String? comboName;
  final int? comboId;
  final int servingDurationMinutes;

  int get queueQuantity => switch (workflowQueue) {
    'pending_prep' => prepRemaining,
    'pending_cook' => cookRemaining - prepRemaining,
    'cooking' => cookRemaining - prepRemaining,
    'ready_serve' => readyRemaining - cookRemaining,
    _ => lineQuantity - refundedQuantity - readyRemaining,
  };

  /// Compatibility alias for queue-scoped projections.
  int get quantity => queueQuantity;

  Map<String, Object?> toApiJson({bool canonicalCloudIds = false}) => {
    'detail_id': canonicalCloudIds ? cloudDetailId : detailId,
    'order_id': canonicalCloudIds ? cloudOrderId : orderId,
    if (cloudDetailId != null && cloudDetailId! > 0)
      'cloud_detail_id': cloudDetailId,
    if (cloudOrderId != null && cloudOrderId! > 0)
      'cloud_order_id': cloudOrderId,
    'dish_id': dishId,
    'dish_name': dishName,
    'line_quantity': lineQuantity,
    'refunded_quantity': refundedQuantity,
    'prep_remaining': prepRemaining,
    'cook_remaining': cookRemaining,
    'ready_remaining': readyRemaining,
    'local_revision': localRevision,
    'order_revision': orderRevision,
    'fulfillment_bucket': fulfillmentType,
    'fulfillment_channel': fulfillmentType,
    'table_number': tableNumber,
    'order_no': orderNo,
    'specification': specification,
    'unit': unit,
    'remark': orderRemark,
    'created_at_ms': createdAtMs,
    'serving_duration_minutes': servingDurationMinutes,
    'completed_at_ms': completedAtMs,
    'held': held,
    'rushed': rushed,
    'lacked': lacked,
    'removed': false,
    'workflow_queue': workflowQueue,
    'is_combo': isCombo,
    'combo': isCombo,
    'set_meal': isCombo,
    if (comboName != null && comboName!.isNotEmpty) 'combo_name': comboName,
    if (comboId != null && comboId! > 0) 'combo_id': comboId,
  };
}

class CashierWorkflowBoard {
  const CashierWorkflowBoard({required this.queue, required this.lines});

  final String queue;
  final List<CashierWorkflowLine> lines;
}

class CashierAdvancePatch {
  const CashierAdvancePatch({
    required this.operationId,
    required this.detailId,
    required this.orderId,
    required this.fromQueue,
    required this.workflowQueue,
    required this.prepRemaining,
    required this.cookRemaining,
    required this.readyRemaining,
    required this.localRevision,
    this.duplicate = false,
  });

  final String operationId;
  final int detailId;
  final int orderId;
  final String fromQueue;
  final String workflowQueue;
  final int prepRemaining;
  final int cookRemaining;
  final int readyRemaining;
  final int localRevision;
  final bool duplicate;

  CashierAdvancePatch asDuplicate() => CashierAdvancePatch(
    operationId: operationId,
    detailId: detailId,
    orderId: orderId,
    fromQueue: fromQueue,
    workflowQueue: workflowQueue,
    prepRemaining: prepRemaining,
    cookRemaining: cookRemaining,
    readyRemaining: readyRemaining,
    localRevision: localRevision,
    duplicate: true,
  );

  Map<String, Object?> toJson() => {
    'operation_id': operationId,
    'detail_id': detailId,
    'order_id': orderId,
    'from_queue': fromQueue,
    'workflow_queue': workflowQueue,
    'prep_remaining': prepRemaining,
    'cook_remaining': cookRemaining,
    'ready_remaining': readyRemaining,
    'remaining_quantity': switch (workflowQueue) {
      'pending_prep' => prepRemaining,
      'pending_cook' => cookRemaining,
      'ready_serve' => readyRemaining,
      _ => 0,
    },
    'row_version': localRevision,
    'local_revision': localRevision,
    'done_line': workflowQueue == 'done' ? 1 : 0,
  };

  factory CashierAdvancePatch.fromJson(Map<String, Object?> json) {
    int readInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    return CashierAdvancePatch(
      operationId: '${json['operation_id'] ?? ''}',
      detailId: readInt('detail_id'),
      orderId: readInt('order_id'),
      fromQueue: '${json['from_queue'] ?? ''}',
      workflowQueue: '${json['workflow_queue'] ?? ''}',
      prepRemaining: readInt('prep_remaining'),
      cookRemaining: readInt('cook_remaining'),
      readyRemaining: readInt('ready_remaining'),
      localRevision: readInt('local_revision'),
      duplicate: json['duplicate'] == true,
    );
  }
}

class CashierCloudEvent {
  const CashierCloudEvent({
    required this.eventId,
    required this.shopId,
    required this.eventType,
    required this.aggregateKey,
    required this.aggregateSequence,
    required this.payload,
    required this.createdAtMs,
    this.attemptCount = 0,
  });

  final String eventId;
  final int shopId;
  final String eventType;
  final String aggregateKey;
  final int aggregateSequence;
  final Map<String, Object?> payload;
  final int createdAtMs;
  final int attemptCount;
}

class CashierCloudEventAck {
  const CashierCloudEventAck({
    required this.eventId,
    this.cloudOrderId,
    this.cloudOrderNo,
    this.detailMappings = const {},
  });

  final String eventId;
  final int? cloudOrderId;
  final String? cloudOrderNo;
  final Map<int, int> detailMappings;
}

/// D026 烤制岗取值（与云端契约一致）。设备可见岗集合只接受这三值；
/// 菜品所属岗也来自这三值。
const kKdsGrillTags = <String>['meat_grill', 'veg_grill', 'seafood_special'];

bool kIsGrillTag(String? value) =>
    value != null && kKdsGrillTags.contains(value);

class CashierKdsDevice {
  const CashierKdsDevice({
    required this.shopId,
    required this.deviceCode,
    required this.deviceName,
    required this.screenTag,
    required this.workflows,
    this.screenTags = const [],
    required this.pairedAtMs,
    required this.lastHeartbeatAtMs,
    required this.enabled,
  });

  final int shopId;
  final String deviceCode;
  final String deviceName;
  final String screenTag;
  final List<String> workflows;

  /// D026 可见烤制岗（荤烤/素烤/海鲜）。空 = 三岗全选，旧设备兼容。
  final List<String> screenTags;
  final int pairedAtMs;
  final int lastHeartbeatAtMs;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'shop_id': shopId,
    'device_code': deviceCode,
    'device_name': deviceName,
    'screen_tag': screenTag,
    'workflows': workflows,
    'screen_tags': screenTags,
    'paired_at_ms': pairedAtMs,
    'last_heartbeat_at_ms': lastHeartbeatAtMs,
    'enabled': enabled,
  };
}

class CashierOutboxStats {
  const CashierOutboxStats({
    required this.pending,
    required this.retrying,
    required this.deadLetter,
    required this.authPaused,
    this.lastDeliveredAtMs,
    this.lastError,
  });

  final int pending;
  final int retrying;
  final int deadLetter;
  final int authPaused;
  final int? lastDeliveredAtMs;
  final String? lastError;
}

class CashierDeadLetter {
  const CashierDeadLetter({
    required this.eventId,
    required this.shopId,
    required this.eventType,
    required this.aggregateKey,
    required this.attemptCount,
    required this.createdAtMs,
    required this.updatedAtMs,
    this.lastHttpStatus,
    this.lastCode,
    this.lastError,
  });

  final String eventId;
  final int shopId;
  final String eventType;
  final String aggregateKey;
  final int attemptCount;
  final int createdAtMs;
  final int updatedAtMs;
  final int? lastHttpStatus;
  final int? lastCode;
  final String? lastError;
}

class CashierDishCatalogItem {
  const CashierDishCatalogItem({
    this.id = 0,
    required this.dishId,
    required this.dishName,
    required this.unit,
    required this.sequence,
    this.categoryId,
    this.categoryName,
    this.categorySequence,
    this.dishSequence,
    this.stock,
    this.onSale = true,
    this.soldOut = false,
    this.servingDurationMinutes = 10,
    this.screenTag,
  });

  final int id;
  final int dishId;
  final String dishName;
  final String unit;
  final int sequence;
  final int? categoryId;
  final String? categoryName;
  final int? categorySequence;
  final int? dishSequence;
  final int? stock;
  final bool onSale;
  final bool soldOut;
  final int servingDurationMinutes;

  /// D026 菜品所属烤制岗（meat_grill/veg_grill/seafood_special）。
  /// 由收银端随菜品数据传入；null/空 = 未配置岗（保守可见）。
  final String? screenTag;

  Map<String, Object?> toApiJson() => {
    'id': id > 0 ? id : dishId,
    'catalog_id': id > 0 ? id : null,
    'dish_id': dishId,
    'dish_name': dishName,
    'name': dishName,
    'unit': unit,
    'stock': stock,
    'onsale': onSale,
    'sold_out': soldOut,
    'sorting': sequence,
    'sequence': sequence,
    'serving_duration_minutes': servingDurationMinutes,
    if (screenTag != null) 'screen_tag': screenTag,
    if (categoryId != null) 'category_id': categoryId,
    if (categoryName != null) 'category_name': categoryName,
    if (categorySequence != null) 'category_sequence': categorySequence,
    if (dishSequence != null) 'dish_sequence': dishSequence,
  };
}

class CashierCatalogChange {
  const CashierCatalogChange({
    required this.eventSeq,
    required this.configVersion,
  });

  final int eventSeq;
  final int configVersion;
}

class CashierKdsConflict implements Exception {
  const CashierKdsConflict(this.message);

  final String message;

  @override
  String toString() => 'CashierKdsConflict: $message';
}

class CashierKdsValidation implements Exception {
  const CashierKdsValidation(this.message);

  final String message;

  @override
  String toString() => 'CashierKdsValidation: $message';
}

class CashierLocalOrderPendingSync implements Exception {
  const CashierLocalOrderPendingSync([this.message = '本地已保存、等待云同步后再操作']);

  final String message;

  @override
  String toString() => message;
}
