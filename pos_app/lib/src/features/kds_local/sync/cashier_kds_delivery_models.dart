/// KDS 云端投递通道模型（openapi v1.2.189 / v1.2.278）。
///
/// 覆盖：authority 租约、bootstrap 快照、增量事件、营业日订单、
/// 单订单投影、累计 ACK、投递状态。字段名与 openapi schema 保持一致，
/// 同时兼容常见别名（下划线/驼峰）。解析容错：缺失可空字段置 null，
/// 缺失必填数值字段按业务约定回退（见各模型注释）。
library;

/// 租约请求（POST /cashier/kds/authority/lease）。
class CashierKdsLeaseRequest {
  const CashierKdsLeaseRequest({
    required this.action,
    this.authorityEpoch,
    this.leaseToken,
    this.clientVersion,
  });

  /// ACQUIRE 获取/接管；RENEW 续租（须同时提交 leaseToken 与 authorityEpoch）。
  final String action;
  final int? authorityEpoch;
  final String? leaseToken;
  final String? clientVersion;

  Map<String, Object?> toJson() => {
        'action': action,
        if (authorityEpoch != null) 'authorityEpoch': authorityEpoch,
        if (leaseToken != null) 'leaseToken': leaseToken,
        if (clientVersion != null) 'clientVersion': clientVersion,
      };
}

/// 租约响应 data（acquire/renew）。
class CashierKdsLeaseResult {
  const CashierKdsLeaseResult({
    required this.shopId,
    required this.deviceCode,
    required this.authorityEpoch,
    required this.leaseToken,
    required this.leaseUntilMs,
    required this.renewAfterMs,
    required this.snapshotRequired,
    this.lastAckCursor = 0,
    this.headCursor = 0,
  });

  final int shopId;
  final String deviceCode;
  final int authorityEpoch;
  final String leaseToken;
  final int leaseUntilMs;

  /// 建议续租间隔（毫秒，示例 10000）。
  final int renewAfterMs;

  /// true 时必须完成 bootstrap 后才能消费/ACK 增量。
  final bool snapshotRequired;
  final int lastAckCursor;
  final int headCursor;

  factory CashierKdsLeaseResult.fromJson(Map<String, Object?> json) {
    return CashierKdsLeaseResult(
      shopId: _int(json, 'shopId') ?? 0,
      deviceCode: _str(json, 'deviceCode') ?? '',
      authorityEpoch: _int(json, 'authorityEpoch') ?? 0,
      leaseToken: _str(json, 'leaseToken') ?? '',
      leaseUntilMs: _int(json, 'leaseUntilMs') ?? 0,
      renewAfterMs: _int(json, 'renewAfterMs') ?? 10000,
      snapshotRequired: json['snapshotRequired'] == true,
      lastAckCursor: _int(json, 'lastAckCursor') ?? 0,
      headCursor: _int(json, 'headCursor') ?? 0,
    );
  }
}

/// 厨房投影明细行。
class CashierKdsProjectionLine {
  const CashierKdsProjectionLine({
    required this.detailId,
    required this.dishId,
    required this.dishName,
    required this.quantity,
    required this.refundedQuantity,
    required this.remainingQuantity,
    required this.lineStatus,
    required this.lineType,
    this.specification,
    this.unit,
    this.clientLineId,
    this.comboId,
    this.comboInstanceId,
    this.parentDetailId,
    this.categoryId,
    this.workflowQueue,
    this.remark,
    this.rushed = false,
  });

  final int detailId;
  final int dishId;
  final String dishName;
  final int quantity;
  final int refundedQuantity;
  final int remainingQuantity;

  /// NORMAL / REFUNDED / CANCELLED。
  final String lineStatus;

  /// NORMAL / COMBO_HEADER / COMBO_COMPONENT。
  final String lineType;
  final String? specification;
  final String? unit;
  final String? clientLineId;
  final int? comboId;
  final String? comboInstanceId;
  final int? parentDetailId;
  final String? categoryId;

  /// 云端配置可确定时返回；为空由收银本地配置路由。
  final String? workflowQueue;
  final String? remark;
  final bool rushed;

  factory CashierKdsProjectionLine.fromJson(Map<String, Object?> json) {
    return CashierKdsProjectionLine(
      detailId: _int(json, 'detailId') ?? 0,
      dishId: _int(json, 'dishId') ?? 0,
      dishName: _str(json, 'dishName') ?? '',
      quantity: _int(json, 'quantity') ?? 0,
      refundedQuantity: _int(json, 'refundedQuantity') ?? 0,
      remainingQuantity: _int(json, 'remainingQuantity') ?? 0,
      lineStatus: _str(json, 'lineStatus') ?? 'NORMAL',
      lineType: _str(json, 'lineType') ?? 'NORMAL',
      specification: _str(json, 'specification'),
      unit: _str(json, 'unit'),
      clientLineId: _str(json, 'clientLineId'),
      comboId: _int(json, 'comboId'),
      comboInstanceId: _str(json, 'comboInstanceId'),
      parentDetailId: _int(json, 'parentDetailId'),
      categoryId: _str(json, 'categoryId'),
      workflowQueue: _str(json, 'workflowQueue'),
      remark: _str(json, 'remark'),
      rushed: json['rushed'] == true,
    );
  }

  /// 序列化回 openapi 字段名（供落库/转发复用）。
  Map<String, Object?> toJson() => {
        'detailId': detailId,
        'dishId': dishId,
        'dishName': dishName,
        'specification': specification,
        'unit': unit,
        'quantity': quantity,
        'refundedQuantity': refundedQuantity,
        'remainingQuantity': remainingQuantity,
        'lineStatus': lineStatus,
        'lineType': lineType,
        'clientLineId': clientLineId,
        'comboId': comboId,
        'comboInstanceId': comboInstanceId,
        'parentDetailId': parentDetailId,
        'categoryId': categoryId,
        'workflowQueue': workflowQueue,
        'remark': remark,
        'rushed': rushed,
      };
}

/// 厨房订单投影（订单事件/单订单投影/business-day 行）。
class CashierKdsOrderProjection {
  const CashierKdsOrderProjection({
    required this.orderId,
    required this.orderNo,
    required this.shopId,
    required this.projectionVersion,
    required this.state,
    required this.sourceChannel,
    required this.fulfillmentType,
    required this.createdAtMs,
    required this.lines,
    this.sourceDeviceCode,
    this.tableNumber,
    this.numberOfDiners,
    this.orderRemark,
    this.acceptanceStatus,
    this.updatedAtMs,
  });

  final int orderId;
  final String orderNo;
  final int shopId;

  /// 单订单厨房投影严格单调版本。
  final int projectionVersion;

  /// READY / VOIDED / CLOSED。
  final String state;

  /// POS / CASHIER / MINI_PROGRAM / ADMIN / THIRD_PARTY / MEITUAN。
  final String sourceChannel;

  /// DINE_IN / TAKEOUT / DELIVERY。
  final String fulfillmentType;
  final int createdAtMs;
  final List<CashierKdsProjectionLine> lines;
  final String? sourceDeviceCode;
  final String? tableNumber;
  final int? numberOfDiners;
  final String? orderRemark;
  final String? acceptanceStatus;
  final int? updatedAtMs;

  factory CashierKdsOrderProjection.fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'];
    return CashierKdsOrderProjection(
      orderId: _int(json, 'orderId') ?? 0,
      orderNo: _str(json, 'orderNo') ?? '',
      shopId: _int(json, 'shopId') ?? 0,
      projectionVersion: _int(json, 'projectionVersion') ?? 0,
      state: _str(json, 'state') ?? 'READY',
      sourceChannel: _str(json, 'sourceChannel') ?? 'CASHIER',
      fulfillmentType: _str(json, 'fulfillmentType') ?? 'DINE_IN',
      createdAtMs: _int(json, 'createdAtMs') ?? 0,
      updatedAtMs: _int(json, 'updatedAtMs'),
      sourceDeviceCode: _str(json, 'sourceDeviceCode'),
      tableNumber: _str(json, 'tableNumber'),
      numberOfDiners: _int(json, 'numberOfDiners'),
      orderRemark: _str(json, 'orderRemark'),
      acceptanceStatus: _str(json, 'acceptanceStatus'),
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map((row) => CashierKdsProjectionLine.fromJson(
                    row.cast<String, Object?>(),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

/// 明细状态增量（ORDER_LINE_STATUS_CHANGED 事件的投影）。
class CashierKdsLineStatusDelta {
  const CashierKdsLineStatusDelta({
    required this.detailId,
    required this.itemStatus,
    required this.prepQuantity,
    required this.cookedQuantity,
    required this.servedQuantity,
    required this.rushFlag,
    required this.overdueFlag,
    required this.addDishFlag,
    required this.archived,
    required this.updatedAtMs,
  });

  final int detailId;

  /// 0 待制作 1 制作中 2 已完成 3 已退菜。
  final int itemStatus;
  final int prepQuantity;
  final int cookedQuantity;
  final int servedQuantity;
  final int rushFlag;
  final int overdueFlag;
  final int addDishFlag;
  final int archived;
  final int updatedAtMs;

  factory CashierKdsLineStatusDelta.fromJson(Map<String, Object?> json) {
    return CashierKdsLineStatusDelta(
      detailId: _int(json, 'detailId') ?? 0,
      itemStatus: _int(json, 'itemStatus') ?? 0,
      prepQuantity: _int(json, 'prepQuantity') ?? 0,
      cookedQuantity: _int(json, 'cookedQuantity') ?? 0,
      servedQuantity: _int(json, 'servedQuantity') ?? 0,
      rushFlag: _int(json, 'rushFlag') ?? 0,
      overdueFlag: _int(json, 'overdueFlag') ?? 0,
      addDishFlag: _int(json, 'addDishFlag') ?? 0,
      archived: _int(json, 'archived') ?? 0,
      updatedAtMs: _int(json, 'updatedAtMs') ?? 0,
    );
  }
}

/// 明细状态增量投影（整单事件类型固定为 ORDER_LINE_STATUS_CHANGED）。
class CashierKdsLineStatusProjection {
  const CashierKdsLineStatusProjection({
    required this.orderId,
    required this.orderNo,
    required this.shopId,
    required this.occurredAtMs,
    required this.lines,
  });

  final int orderId;
  final String orderNo;
  final int shopId;
  final int occurredAtMs;
  final List<CashierKdsLineStatusDelta> lines;

  factory CashierKdsLineStatusProjection.fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'];
    return CashierKdsLineStatusProjection(
      orderId: _int(json, 'orderId') ?? 0,
      orderNo: _str(json, 'orderNo') ?? '',
      shopId: _int(json, 'shopId') ?? 0,
      occurredAtMs: _int(json, 'occurredAtMs') ?? 0,
      lines: rawLines is List
          ? rawLines
              .whereType<Map>()
              .map((row) => CashierKdsLineStatusDelta.fromJson(
                    row.cast<String, Object?>(),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

/// 投递事件（至少一次返回、可重复；按 eventId + projectionVersion 幂等）。
class CashierKdsDeliveryEvent {
  const CashierKdsDeliveryEvent({
    required this.eventId,
    required this.cursor,
    required this.shopId,
    required this.eventType,
    required this.orderId,
    required this.projectionVersion,
    required this.originChannel,
    required this.occurredAtMs,
    this.originDeviceCode,
    this.changedDetailIds = const [],
    this.projection,
    this.lineStatusProjection,
  });

  final String eventId;
  final int cursor;
  final int shopId;

  /// ORDER_ACCEPTED / ORDER_READY / ORDER_UPDATED / ORDER_LINE_VOIDED /
  /// ORDER_CANCELLED / ORDER_VOIDED / ORDER_RUSHED / ORDER_CLOSED /
  /// ORDER_LINE_STATUS_CHANGED。
  final String eventType;
  final int orderId;
  final int projectionVersion;
  final String originChannel;
  final int occurredAtMs;
  final String? originDeviceCode;
  final List<int> changedDetailIds;

  /// 订单投影事件携带的完整订单快照；明细状态事件为 null。
  final CashierKdsOrderProjection? projection;

  /// ORDER_LINE_STATUS_CHANGED 事件携带的明细状态增量；其余事件为 null。
  final CashierKdsLineStatusProjection? lineStatusProjection;

  bool get isLineStatusEvent => eventType == 'ORDER_LINE_STATUS_CHANGED';

  factory CashierKdsDeliveryEvent.fromJson(Map<String, Object?> json) {
    final projectionRaw = json['projection'];
    CashierKdsOrderProjection? orderProjection;
    CashierKdsLineStatusProjection? lineStatusProjection;
    if (projectionRaw is Map) {
      final projectionJson = projectionRaw.cast<String, Object?>();
      if (json['eventType'] == 'ORDER_LINE_STATUS_CHANGED') {
        lineStatusProjection =
            CashierKdsLineStatusProjection.fromJson(projectionJson);
      } else {
        orderProjection = CashierKdsOrderProjection.fromJson(projectionJson);
      }
    }
    final rawChanged = json['changedDetailIds'];
    return CashierKdsDeliveryEvent(
      eventId: _str(json, 'eventId') ?? '',
      cursor: _int(json, 'cursor') ?? 0,
      shopId: _int(json, 'shopId') ?? 0,
      eventType: _str(json, 'eventType') ?? '',
      orderId: _int(json, 'orderId') ?? 0,
      projectionVersion: _int(json, 'projectionVersion') ?? 0,
      originChannel: _str(json, 'originChannel') ?? 'CASHIER',
      occurredAtMs: _int(json, 'occurredAtMs') ?? 0,
      originDeviceCode: _str(json, 'originDeviceCode'),
      changedDetailIds: rawChanged is List
          ? rawChanged
              .whereType<num>()
              .map((value) => value.toInt())
              .toList(growable: false)
          : const [],
      projection: orderProjection,
      lineStatusProjection: lineStatusProjection,
    );
  }
}

/// 增量事件响应 data。
class CashierKdsEventsResult {
  const CashierKdsEventsResult({
    required this.currentCursor,
    required this.nextCursor,
    required this.minAvailableCursor,
    required this.snapshotRequired,
    required this.events,
  });

  final int currentCursor;
  final int nextCursor;
  final int minAvailableCursor;
  final bool snapshotRequired;
  final List<CashierKdsDeliveryEvent> events;

  factory CashierKdsEventsResult.fromJson(Map<String, Object?> json) {
    final rawEvents = json['events'];
    return CashierKdsEventsResult(
      currentCursor: _int(json, 'currentCursor') ?? 0,
      nextCursor: _int(json, 'nextCursor') ?? 0,
      minAvailableCursor: _int(json, 'minAvailableCursor') ?? 0,
      snapshotRequired: json['snapshotRequired'] == true,
      events: rawEvents is List
          ? rawEvents
              .whereType<Map>()
              .map((row) => CashierKdsDeliveryEvent.fromJson(
                    row.cast<String, Object?>(),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

/// bootstrap 分页快照 data。
class CashierKdsBootstrapResult {
  const CashierKdsBootstrapResult({
    required this.snapshotToken,
    required this.baseCursor,
    required this.complete,
    required this.orders,
    this.nextPageToken,
  });

  final String snapshotToken;
  final int baseCursor;
  final String? nextPageToken;
  final bool complete;
  final List<CashierKdsOrderProjection> orders;

  factory CashierKdsBootstrapResult.fromJson(Map<String, Object?> json) {
    final rawOrders = json['orders'];
    return CashierKdsBootstrapResult(
      snapshotToken: _str(json, 'snapshotToken') ?? '',
      baseCursor: _int(json, 'baseCursor') ?? 0,
      nextPageToken: _str(json, 'nextPageToken'),
      complete: json['complete'] == true,
      orders: rawOrders is List
          ? rawOrders
              .whereType<Map>()
              .map((row) => CashierKdsOrderProjection.fromJson(
                    row.cast<String, Object?>(),
                  ))
              .toList(growable: false)
          : const [],
    );
  }
}

/// 营业日订单明细回填 data（business-day/orders/detail）。
///
/// schema 为开放对象（additionalProperties），按 description 解析
/// businessDayStart/businessDayEnd/orders/nextCursor/complete；
/// orders 每行含订单头与 details/lines（厨房完成进度），保持原始结构。
class CashierKdsBusinessDayDetailResult {
  const CashierKdsBusinessDayDetailResult({
    required this.orders,
    required this.complete,
    this.businessDayStart,
    this.businessDayEnd,
    this.nextCursor,
  });

  final String? businessDayStart;
  final String? businessDayEnd;
  final List<Map<String, Object?>> orders;

  /// 分页游标（不透明字符串）；null 表示已到最后一页。
  final String? nextCursor;
  final bool complete;

  factory CashierKdsBusinessDayDetailResult.fromJson(
    Map<String, Object?> json,
  ) {
    final rawOrders = json['orders'];
    return CashierKdsBusinessDayDetailResult(
      businessDayStart: _str(json, 'businessDayStart'),
      businessDayEnd: _str(json, 'businessDayEnd'),
      orders: rawOrders is List
          ? rawOrders
              .whereType<Map>()
              .map((row) => row.cast<String, Object?>())
              .toList(growable: false)
          : const [],
      nextCursor: _str(json, 'nextCursor'),
      complete: json['complete'] == true,
    );
  }
}

/// 营业时段订单快照 data（business-day/orders）。
class CashierKdsBusinessDayOrdersResult {
  const CashierKdsBusinessDayOrdersResult({
    required this.shopId,
    required this.orders,
    required this.complete,
    this.businessDay,
    this.businessDayStart,
    this.businessDayEnd,
    this.openTime,
    this.closeTime,
    this.nextCursor,
  });

  final int shopId;
  final String? businessDay;
  final String? businessDayStart;
  final String? businessDayEnd;
  final String? openTime;
  final String? closeTime;
  final List<Map<String, Object?>> orders;

  /// `order_time:order_id` 复合游标；null 表示已到最后一页。
  final String? nextCursor;
  final bool complete;

  factory CashierKdsBusinessDayOrdersResult.fromJson(Map<String, Object?> json) {
    final rawOrders = json['orders'];
    return CashierKdsBusinessDayOrdersResult(
      shopId: _int(json, 'shopId') ?? 0,
      businessDay: _str(json, 'businessDay'),
      businessDayStart: _str(json, 'businessDayStart'),
      businessDayEnd: _str(json, 'businessDayEnd'),
      openTime: _str(json, 'openTime'),
      closeTime: _str(json, 'closeTime'),
      orders: rawOrders is List
          ? rawOrders
              .whereType<Map>()
              .map((row) => row.cast<String, Object?>())
              .toList(growable: false)
          : const [],
      nextCursor: _str(json, 'nextCursor'),
      complete: json['complete'] == true,
    );
  }
}

/// ACK 响应 data。
class CashierKdsAckResult {
  const CashierKdsAckResult({
    required this.acknowledgedCursor,
    required this.headCursor,
    required this.duplicate,
    this.lag = 0,
  });

  final int acknowledgedCursor;
  final int headCursor;
  final bool duplicate;
  final int lag;

  factory CashierKdsAckResult.fromJson(Map<String, Object?> json) {
    return CashierKdsAckResult(
      acknowledgedCursor: _int(json, 'acknowledgedCursor') ?? 0,
      headCursor: _int(json, 'headCursor') ?? 0,
      duplicate: json['duplicate'] == true,
      lag: _int(json, 'lag') ?? 0,
    );
  }
}

/// 投递状态 data（delivery/status）。
class CashierKdsDeliveryStatusResult {
  const CashierKdsDeliveryStatusResult({
    required this.shopId,
    required this.headCursor,
    required this.acknowledgedCursor,
    required this.minAvailableCursor,
    required this.lag,
    required this.authorityOnline,
    required this.snapshotRequired,
    this.oldestUnackedAtMs,
    this.authorityDeviceCode,
    this.authorityEpoch,
    this.leaseUntilMs,
  });

  final int shopId;
  final int headCursor;
  final int acknowledgedCursor;
  final int minAvailableCursor;
  final int lag;
  final bool authorityOnline;
  final bool snapshotRequired;
  final int? oldestUnackedAtMs;
  final String? authorityDeviceCode;
  final int? authorityEpoch;
  final int? leaseUntilMs;

  factory CashierKdsDeliveryStatusResult.fromJson(Map<String, Object?> json) {
    return CashierKdsDeliveryStatusResult(
      shopId: _int(json, 'shopId') ?? 0,
      headCursor: _int(json, 'headCursor') ?? 0,
      acknowledgedCursor: _int(json, 'acknowledgedCursor') ?? 0,
      minAvailableCursor: _int(json, 'minAvailableCursor') ?? 0,
      lag: _int(json, 'lag') ?? 0,
      authorityOnline: json['authorityOnline'] == true,
      snapshotRequired: json['snapshotRequired'] == true,
      oldestUnackedAtMs: _int(json, 'oldestUnackedAtMs'),
      authorityDeviceCode: _str(json, 'authorityDeviceCode'),
      authorityEpoch: _int(json, 'authorityEpoch'),
      leaseUntilMs: _int(json, 'leaseUntilMs'),
    );
  }
}

// ---------- 内部解析工具 ----------

int? _int(Map<String, Object?> json, String key) {
  final value = json[key] ?? json[_snake(key)];
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value.trim());
    if (parsed != null) return parsed;
  }
  return null;
}

String? _str(Map<String, Object?> json, String key) {
  final value = json[key] ?? json[_snake(key)];
  if (value is String) return value;
  if (value is num || value is bool) return '$value';
  return null;
}

String _snake(String camel) => camel.replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => '_${match.group(0)!.toLowerCase()}',
    );
