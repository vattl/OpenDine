import 'package:kds_app/core/board/kds_fulfillment.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';

Map<String, dynamic> _body(Map<String, dynamic> json) {
  final data = json['data'];
  return data is Map ? Map<String, dynamic>.from(data) : json;
}

int _int(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

String _firstText(Map<String, dynamic> json, Iterable<String> keys,
    [String fallback = '']) {
  for (final key in keys) {
    final value = json[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return fallback;
}

String _fulfillmentBucket(Map<String, dynamic> json,
    {required bool allowLegacyAliases}) {
  final canonical = _firstText(json, const ['fulfillment_bucket']);
  if (canonical.isNotEmpty) {
    final normalized = canonical.toLowerCase();
    if (allowLegacyAliases && normalized == 'takeaway') return 'takeout';
    if (allowLegacyAliases && normalized == 'self_pickup') return 'pickup';
    if (const {'dine_in', 'takeout', 'pickup', 'pack', 'delivery'}
        .contains(normalized)) {
      return normalized;
    }
    throw FormatException(
      'KDS v2 fulfillment_bucket is invalid: $canonical',
    );
  }
  if (!allowLegacyAliases) {
    throw const FormatException('KDS v2 detail is missing fulfillment_bucket');
  }
  final hasAlias = const ['fulfillment_type', 'dineInOrTakeOut']
      .any((key) => _firstText(json, [key]).isNotEmpty);
  return hasAlias ? KdsFulfillment.resolve(json).mergeKey : '';
}

const _canonicalLineFields = {
  'detail_id',
  'order_id',
  'dish_id',
  'dish_name',
  'line_quantity',
  'refunded_quantity',
  'prep_remaining',
  'cook_remaining',
  'ready_remaining',
  'local_revision',
  'order_revision',
  'fulfillment_bucket',
  'table_number',
  'order_no',
  'specification',
  'unit',
  'remark',
  'created_at_ms',
  'held',
  'rushed',
  'lacked',
  'removed',
};

int _strictInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) {
    throw FormatException('KDS v2 detail $key must be an integer');
  }
  return value;
}

void _validateCanonicalLine(Map<String, dynamic> json) {
  final missing = _canonicalLineFields.where((key) => !json.containsKey(key));
  if (missing.isNotEmpty) {
    throw FormatException(
      'KDS v2 detail is missing required fields: ${missing.join(',')}',
    );
  }
  final detailId = _strictInt(json, 'detail_id');
  final orderId = _strictInt(json, 'order_id');
  final dishId = _strictInt(json, 'dish_id');
  final lineQuantity = _strictInt(json, 'line_quantity');
  final refundedQuantity = _strictInt(json, 'refunded_quantity');
  final prepRemaining = _strictInt(json, 'prep_remaining');
  final cookRemaining = _strictInt(json, 'cook_remaining');
  final readyRemaining = _strictInt(json, 'ready_remaining');
  final localRevision = _strictInt(json, 'local_revision');
  final orderRevision = _strictInt(json, 'order_revision');
  final createdAtMs = _strictInt(json, 'created_at_ms');
  if (detailId <= 0 || orderId <= 0 || dishId <= 0) {
    throw const FormatException('KDS v2 detail ids must be positive');
  }
  if (_firstText(json, const ['dish_name']).isEmpty ||
      _firstText(json, const ['order_no']).isEmpty) {
    throw const FormatException(
      'KDS v2 dish_name and order_no must be non-empty',
    );
  }
  if (lineQuantity <= 0 ||
      refundedQuantity < 0 ||
      refundedQuantity > lineQuantity ||
      prepRemaining < 0 ||
      prepRemaining > cookRemaining ||
      cookRemaining > readyRemaining ||
      readyRemaining > lineQuantity - refundedQuantity ||
      localRevision <= 0 ||
      orderRevision <= 0 ||
      createdAtMs <= 0) {
    throw const FormatException(
      'KDS v2 quantities, revisions, or timestamp are invalid',
    );
  }
  for (final key in const ['held', 'rushed', 'lacked', 'removed']) {
    if (json[key] is! bool) {
      throw FormatException('KDS v2 detail $key must be boolean');
    }
  }
  for (final key in const ['table_number', 'specification', 'unit', 'remark']) {
    if (json[key] != null && json[key] is! String) {
      throw FormatException('KDS v2 detail $key must be string or null');
    }
  }
  _fulfillmentBucket(json, allowLegacyAliases: false);
}

void _requireV2(Map<String, dynamic> json) {
  if (_int(json['protocol_version']) != 2) {
    throw const FormatException('KDS LAN protocol_version must be 2');
  }
}

Map<String, int> _counts(dynamic raw) => raw is Map
    ? Map.unmodifiable(raw.map((key, value) => MapEntry('$key', _int(value))))
    : const {};

Map<String, int> _strictCounts(dynamic raw, String field) {
  if (raw is! Map) {
    throw FormatException('KDS v2 $field must be an object');
  }
  final result = <String, int>{};
  for (final entry in raw.entries) {
    if (entry.value is! int || (entry.value as int) < 0) {
      throw FormatException(
          'KDS v2 $field values must be non-negative integers');
    }
    result['${entry.key}'] = entry.value as int;
  }
  return Map.unmodifiable(result);
}

enum KdsV2CommandType {
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

  const KdsV2CommandType(this.wireName);
  final String wireName;
}

class KdsV2CommandTarget {
  const KdsV2CommandTarget({
    this.orderId,
    this.detailId,
    this.detailIds = const [],
    this.fromQueue,
  });
  final int? orderId;
  final int? detailId;
  final List<int> detailIds;
  final String? fromQueue;

  Map<String, dynamic> toJson() => {
        if (orderId != null) 'order_id': orderId,
        if (detailId != null) 'detail_id': detailId,
        if (detailIds.isNotEmpty) 'detail_ids': detailIds,
        if (fromQueue != null) 'from_queue': fromQueue,
      };

  factory KdsV2CommandTarget.fromJson(Map<String, dynamic> json) {
    final rawDetailIds = json['detail_ids'];
    final detailIds = rawDetailIds is List
        ? rawDetailIds
            .map((e) => _int(e))
            .where((e) => e > 0)
            .toList(growable: false)
        : const <int>[];
    final orderIdVal = json['order_id'];
    final detailIdVal = json['detail_id'];
    return KdsV2CommandTarget(
      orderId: orderIdVal != null ? _int(orderIdVal) : null,
      detailId: detailIdVal != null ? _int(detailIdVal) : null,
      detailIds: detailIds,
      fromQueue: json['from_queue']?.toString(),
    );
  }
}

class KdsV2Command {
  KdsV2Command({
    required this.commandId,
    required this.type,
    required this.target,
    this.quantity,
    this.expectedRevision,
    this.remark,
    this.setSoldOut,
    this.expectedRevisions = const {},
  });
  final String commandId;
  final KdsV2CommandType type;
  final KdsV2CommandTarget target;
  final int? quantity;
  final int? expectedRevision;
  final String? remark;
  final bool? setSoldOut;
  final Map<int, int> expectedRevisions;

  KdsV2Command withCommandId(String value) => KdsV2Command(
        commandId: value,
        type: type,
        target: target,
        quantity: quantity,
        expectedRevision: expectedRevision,
        remark: remark,
        setSoldOut: setSoldOut,
        expectedRevisions: expectedRevisions,
      );

  KdsV2Command withTarget(
    KdsV2CommandTarget value, {
    Map<int, int>? expectedRevisions,
  }) =>
      KdsV2Command(
        commandId: commandId,
        type: type,
        target: value,
        quantity: quantity,
        expectedRevision: expectedRevision,
        remark: remark,
        setSoldOut: setSoldOut,
        expectedRevisions: expectedRevisions ?? this.expectedRevisions,
      );

  Map<String, dynamic> toJson() => {
        'command_id': commandId,
        'type': type.wireName,
        'target': target.toJson(),
        if (quantity != null) 'quantity': quantity,
        if (expectedRevision != null) 'expected_revision': expectedRevision,
        if (remark != null ||
            setSoldOut != null ||
            expectedRevisions.isNotEmpty)
          'payload': {
            if (remark != null) 'remark': remark,
            if (setSoldOut != null) 'set_sold_out': setSoldOut,
            if (expectedRevisions.isNotEmpty)
              'expected_revisions': expectedRevisions.map(
                (detailId, revision) => MapEntry('$detailId', revision),
              ),
          },
      };

  factory KdsV2Command.fromJson(Map<String, dynamic> json) {
    final commandId = json['command_id']?.toString() ?? '';
    final typeWire = json['type']?.toString() ?? '';
    KdsV2CommandType? foundType;
    for (final t in KdsV2CommandType.values) {
      if (t.wireName == typeWire) {
        foundType = t;
        break;
      }
    }
    if (foundType == null) {
      throw FormatException('Unknown KdsV2CommandType wire name: $typeWire');
    }
    final rawTarget = json['target'];
    final target = rawTarget is Map
        ? KdsV2CommandTarget.fromJson(Map<String, dynamic>.from(rawTarget))
        : const KdsV2CommandTarget();
    final rawPayload = json['payload'];
    final payload = rawPayload is Map
        ? Map<String, dynamic>.from(rawPayload)
        : const <String, dynamic>{};

    final expRevs = <int, int>{};
    final rawRevs = payload['expected_revisions'];
    if (rawRevs is Map) {
      for (final entry in rawRevs.entries) {
        final dId = int.tryParse(entry.key.toString());
        final rev = int.tryParse(entry.value.toString());
        if (dId != null && rev != null) {
          expRevs[dId] = rev;
        }
      }
    }
    final remarkVal = payload['remark'] ?? json['remark'];
    final setSoldOutVal = payload['set_sold_out'] ?? json['set_sold_out'];
    final quantityVal = json['quantity'];
    final expectedRevisionVal = json['expected_revision'];

    return KdsV2Command(
      commandId: commandId,
      type: foundType,
      target: target,
      quantity: quantityVal != null ? _int(quantityVal) : null,
      expectedRevision:
          expectedRevisionVal != null ? _int(expectedRevisionVal) : null,
      remark: remarkVal?.toString(),
      setSoldOut: setSoldOutVal is bool ? setSoldOutVal : null,
      expectedRevisions: expRevs,
    );
  }
}

class KdsV2Line {
  KdsV2Line({
    required this.detailId,
    required this.orderId,
    required this.dishId,
    required this.dishName,
    required this.quantity,
    required this.queue,
    required this.fulfillmentBucket,
    required this.revision,
    required this.raw,
    this.optimisticQueues = const {},
    this.optimisticCommandIds = const {},
  });
  final int detailId;
  final int orderId;
  final int dishId;
  final String dishName;
  final int quantity;
  final String queue;
  final String fulfillmentBucket;
  final int revision;
  final Map<String, dynamic> raw;
  final Map<String, KdsOverlayStatus> optimisticQueues;
  final Map<String, String> optimisticCommandIds;

  KdsV2Line withRawFields(Map<String, dynamic> fields) => KdsV2Line(
        detailId: detailId,
        orderId: orderId,
        dishId: dishId,
        dishName: dishName,
        quantity: quantity,
        queue: queue,
        fulfillmentBucket: fulfillmentBucket,
        revision: revision,
        raw: Map.unmodifiable({...raw, ...fields}),
        optimisticQueues: optimisticQueues,
        optimisticCommandIds: optimisticCommandIds,
      );

  KdsV2Line withOptimisticQueues(
    Map<String, KdsOverlayStatus> queues, {
    Map<String, String>? commandIds,
  }) =>
      KdsV2Line(
        detailId: detailId,
        orderId: orderId,
        dishId: dishId,
        dishName: dishName,
        quantity: quantity,
        queue: queue,
        fulfillmentBucket: fulfillmentBucket,
        revision: revision,
        raw: raw,
        optimisticQueues: Map.unmodifiable(queues),
        optimisticCommandIds:
            commandIds != null ? Map.unmodifiable(commandIds) : optimisticCommandIds,
      );

  String get mergeKey => '$dishId:$fulfillmentBucket';

  /// 履约渠道：优先可选细分字段 `fulfillment_channel`（2026-08-18 协调），
  /// 缺省/非法时回退 `fulfillment_bucket`。
  String get channel {
    final rawChannel = raw['fulfillment_channel'];
    if (rawChannel is String) {
      final normalized = rawChannel.trim().toLowerCase();
      if (const {'dine_in', 'takeout', 'delivery', 'pickup', 'pack'}
          .contains(normalized)) {
        return normalized;
      }
    }
    return fulfillmentBucket;
  }

  /// 云端订单 ID（t_order.id，如 13909）。仅用于展示/对单；
  /// 划菜命令仍必须使用 [orderId]（收银端本地订单 ID）。
  /// 收银端 `advance_item` 等增量事件会携带；`order_ready` 等 bootstrap 流
  /// 事件偶发缺失，此时可用 [cloudOrderNo] 或同单补齐兜底。
  int? get cloudOrderId {
    final value = raw['cloud_order_id'];
    final id = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return id > 0 ? id : null;
  }

  /// 云端正式明细 ID。LAN 投影携带此别名后，双模传输层可在切到
  /// 云端时只改写实体身份，不改变 command_id 或业务参数。
  int? get cloudDetailId {
    final value = raw['cloud_detail_id'];
    final id = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return id > 0 ? id : null;
  }

  /// 云端订单号（t_order.order_no，如 ORD2026090505201...）。
  /// KDS v2 协议下发的是云端订单号（非收银端本地 `L{ts}-{id}`），
  /// 缺失时返回 null。
  String? get cloudOrderNo {
    final value = raw['order_no']?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  int? get orderRevision =>
      raw['order_revision'] == null ? null : _int(raw['order_revision']);
  int waitSecondsAt(int nowMs) {
    if (raw['wait_seconds'] != null) {
      return _int(raw['wait_seconds']).clamp(0, 1 << 31);
    }
    final createdAtMs = _int(raw['created_at_ms']);
    if (createdAtMs <= 0) return 0;
    return ((nowMs - createdAtMs) ~/ 1000).clamp(0, 1 << 31);
  }

  /// Pure view projection. The authoritative reducer still stores one full
  /// detail snapshot; a partially progressed detail can appear in many queues.
  List<KdsV2LineSlice> get slices {
    final hasCumulativeQuantities = const [
      'prep_remaining',
      'cook_remaining',
      'ready_remaining',
    ].any(raw.containsKey);
    if (hasCumulativeQuantities) {
      final prepRemaining = _int(raw['prep_remaining']);
      final cookRemaining = _int(raw['cook_remaining']);
      final readyRemaining = _int(raw['ready_remaining']);
      final activeQuantity = _int(raw['line_quantity'] ?? raw['quantity']) -
          _int(raw['refunded_quantity']);
      final values = <(String, int)>[
        ('pending_prep', prepRemaining),
        ('pending_cook', cookRemaining - prepRemaining),
        ('ready_serve', readyRemaining - cookRemaining),
        ('done', activeQuantity - readyRemaining),
      ];
      return List.unmodifiable(
          values.where((entry) => entry.$2 > 0).map((entry) => KdsV2LineSlice(
                detail: this,
                queue: entry.$1,
                quantity: entry.$2,
                isOptimistic: optimisticQueues.containsKey(entry.$1),
                overlayStatus: optimisticQueues[entry.$1],
                commandId: optimisticCommandIds[entry.$1],
              )));
    }
    if (quantity <= 0 || queue.isEmpty) return const [];
    return [
      KdsV2LineSlice(
        detail: this,
        queue: queue,
        quantity: quantity,
        isOptimistic: optimisticQueues.containsKey(queue),
        overlayStatus: optimisticQueues[queue],
        commandId: optimisticCommandIds[queue],
      )
    ];
  }

  factory KdsV2Line.fromJson(Map<String, dynamic> json,
      {String? queueFallback}) {
    _validateCanonicalLine(json);
    return KdsV2Line._parse(json, queueFallback: queueFallback);
  }

  factory KdsV2Line.fromLegacyJson(Map<String, dynamic> json,
          {String? queueFallback}) =>
      KdsV2Line._parse(
        json,
        queueFallback: queueFallback,
        allowLegacyAliases: true,
      );

  factory KdsV2Line._parse(
    Map<String, dynamic> json, {
    String? queueFallback,
    bool allowLegacyAliases = false,
  }) {
    final cumulativeKeys = const [
      'prep_remaining',
      'cook_remaining',
      'ready_remaining',
    ];
    final hasCumulativeQuantities = cumulativeKeys.any(json.containsKey);
    final lineQuantity = _int(json['line_quantity'] ?? json['quantity']);
    if (hasCumulativeQuantities) {
      if (!cumulativeKeys.every(json.containsKey)) {
        throw const FormatException(
            'KDS v2 detail is missing cumulative quantity fields');
      }
      final refundedQuantity = _int(json['refunded_quantity']);
      final activeQuantity = lineQuantity - refundedQuantity;
      final prepRemaining = _int(json['prep_remaining']);
      final cookRemaining = _int(json['cook_remaining']);
      final readyRemaining = _int(json['ready_remaining']);
      if (lineQuantity < 0 ||
          refundedQuantity < 0 ||
          activeQuantity < 0 ||
          prepRemaining < 0 ||
          prepRemaining > cookRemaining ||
          cookRemaining > readyRemaining ||
          readyRemaining > activeQuantity) {
        throw const FormatException(
            'KDS v2 detail cumulative quantities are invalid');
      }
    }
    return KdsV2Line(
      detailId: _int(json['detail_id']),
      orderId: _int(json['order_id']),
      dishId: _int(json['dish_id']),
      dishName: '${json['dish_name'] ?? ''}',
      quantity: lineQuantity,
      queue: _firstText(
        json,
        allowLegacyAliases
            ? const ['workflow_queue', 'queue', 'queue_status']
            : const ['workflow_queue'],
        queueFallback ?? '',
      ),
      fulfillmentBucket:
          _fulfillmentBucket(json, allowLegacyAliases: allowLegacyAliases),
      revision: _int(allowLegacyAliases
          ? json['local_revision'] ?? json['row_version'] ?? json['revision']
          : json['local_revision']),
      raw: Map.unmodifiable(json),
    );
  }
}

class KdsV2LineSlice {
  const KdsV2LineSlice({
    required this.detail,
    required this.queue,
    required this.quantity,
    this.isOptimistic = false,
    this.overlayStatus,
    this.commandId,
  });
  final KdsV2Line detail;
  final String queue;
  final int quantity;
  final bool isOptimistic;
  final KdsOverlayStatus? overlayStatus;
  final String? commandId;
  int get detailId => detail.detailId;
  int get orderId => detail.orderId;
  int get dishId => detail.dishId;
  String get dishName => detail.dishName;
  String get fulfillmentBucket => detail.fulfillmentBucket;
  int? get cloudOrderId => detail.cloudOrderId;
  String? get cloudOrderNo => detail.cloudOrderNo;
  String get channel => detail.channel;
  int get revision => detail.revision;
  int? get orderRevision => detail.orderRevision;
  int waitSecondsAt(int nowMs) => detail.waitSecondsAt(nowMs);
  Map<String, dynamic> get raw => detail.raw;
  String get mergeKey => detail.mergeKey;
}

class KdsV2Patch {
  const KdsV2Patch({required this.detailId, required this.removed, this.line});
  final int detailId;
  final bool removed;
  final KdsV2Line? line;

  factory KdsV2Patch.fromJson(Map<String, dynamic> json) {
    final removed = json['removed'] == true;
    final nested = json['line'];
    final snapshot = nested is Map ? Map<String, dynamic>.from(nested) : json;
    final detailId = _int(json['detail_id'] ?? snapshot['detail_id']);
    if (detailId <= 0) {
      throw const FormatException('KDS v2 patch is missing detail_id');
    }
    if (removed) {
      return KdsV2Patch(detailId: detailId, removed: true);
    }
    final line = KdsV2Line.fromJson(snapshot);
    return KdsV2Patch(
      detailId: detailId,
      removed: removed,
      line: line,
    );
  }
}

class KdsV2OrderDetail {
  const KdsV2OrderDetail({
    required this.orderId,
    required this.orderNo,
    required this.tableNumber,
    required this.fulfillmentType,
    required this.orderRemark,
    required this.detailId,
    required this.dishId,
    required this.dishName,
    required this.specification,
    required this.unit,
    required this.quantity,
    required this.refundedQuantity,
    required this.remainingQuantity,
    required this.status,
    required this.removed,
    required this.remark,
    required this.raw,
    this.orderRushed = false,
  });

  final int orderId;
  final String orderNo;
  final String tableNumber;
  final String fulfillmentType;
  final String orderRemark;
  final int detailId;
  final int dishId;
  final String dishName;
  final String specification;
  final String unit;
  final int quantity;
  final int refundedQuantity;
  final int remainingQuantity;
  final String status;
  final bool removed;
  final String remark;

  /// 订单明细可选展示字段（含菜品级出餐时长）。
  final Map<String, dynamic> raw;

  /// 云端订单 ID（t_order.id）与订单号（t_order.order_no），仅用于对单展示。
  int? get cloudOrderId {
    final value = raw['cloud_order_id'];
    final id = value is num ? value.toInt() : int.tryParse('$value') ?? 0;
    return id > 0 ? id : null;
  }

  String? get cloudOrderNo {
    final value = raw['order_no']?.toString().trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  /// 整单催菜/加急标记（v2.2 新增，只增不清）；旧收银端不返回时为 false
  final bool orderRushed;

  factory KdsV2OrderDetail.fromJson(Map<String, dynamic> json) {
    const requiredFields = {
      'order_id',
      'order_no',
      'table_number',
      'fulfillment_type',
      'order_remark',
      'detail_id',
      'dish_id',
      'dish_name',
      'specification',
      'unit',
      'quantity',
      'refunded_quantity',
      'remaining_quantity',
      'status',
      'removed',
      'remark',
    };
    final missing = requiredFields.where((field) => !json.containsKey(field));
    if (missing.isNotEmpty) {
      throw FormatException(
        'KDS v2 order detail is missing required fields: ${missing.join(',')}',
      );
    }
    final orderId = _strictInt(json, 'order_id');
    final detailId = _strictInt(json, 'detail_id');
    final dishId = _strictInt(json, 'dish_id');
    final quantity = _strictInt(json, 'quantity');
    final refundedQuantity = _strictInt(json, 'refunded_quantity');
    final remainingQuantity = _strictInt(json, 'remaining_quantity');
    if (orderId <= 0 || detailId <= 0 || dishId <= 0 || quantity <= 0) {
      throw const FormatException(
          'KDS v2 order detail ids and quantity must be positive');
    }
    if (refundedQuantity < 0 ||
        refundedQuantity > quantity ||
        remainingQuantity != quantity - refundedQuantity) {
      throw const FormatException('KDS v2 order detail quantities are invalid');
    }
    for (final field in const [
      'order_no',
      'table_number',
      'fulfillment_type',
      'order_remark',
      'dish_name',
      'specification',
      'unit',
      'status',
      'remark',
    ]) {
      if (json[field] is! String) {
        throw FormatException('KDS v2 order detail $field must be a string');
      }
    }
    if ((json['order_no'] as String).trim().isEmpty ||
        (json['dish_name'] as String).trim().isEmpty) {
      throw const FormatException(
        'KDS v2 order detail order_no and dish_name must be non-empty',
      );
    }
    final fulfillmentType = json['fulfillment_type'] as String;
    // 2026-08-18 协调后：履约渠道正式枚举含 pickup（自提）与 pack（旧版打包）
    if (!const {'dine_in', 'takeout', 'delivery', 'pickup', 'pack'}
        .contains(fulfillmentType)) {
      throw const FormatException(
        'KDS v2 order detail fulfillment_type is invalid',
      );
    }
    final status = json['status'] as String;
    if (!const {'active', 'partially_refunded', 'refunded'}.contains(status)) {
      throw const FormatException('KDS v2 order detail status is invalid');
    }
    if (json['removed'] is! bool ||
        ((json['removed'] as bool) != (status == 'refunded'))) {
      throw const FormatException(
        'KDS v2 order detail removed does not match status',
      );
    }
    return KdsV2OrderDetail(
      orderId: orderId,
      orderNo: json['order_no'] as String,
      tableNumber: json['table_number'] as String,
      fulfillmentType: fulfillmentType,
      orderRemark: json['order_remark'] as String,
      detailId: detailId,
      dishId: dishId,
      dishName: json['dish_name'] as String,
      specification: json['specification'] as String,
      unit: json['unit'] as String,
      quantity: quantity,
      refundedQuantity: refundedQuantity,
      remainingQuantity: remainingQuantity,
      status: status,
      removed: json['removed'] as bool,
      remark: json['remark'] as String,
      raw: Map.unmodifiable(json),
      // 可选字段：v2.2+ 整单催菜标记，缺失时默认 false
      orderRushed: json['order_rushed'] == true,
    );
  }
}

List<KdsV2OrderDetail> _parseOrderDetails(dynamic raw) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw const FormatException('KDS v2 order_details must be an array');
  }
  // order_details 仅用于展示：单条无效不阻塞其余明细与主流程
  final result = <KdsV2OrderDetail>[];
  for (final value in raw) {
    if (value is! Map) {
      KdsFileLogger.warn('[KDS] 跳过非对象 order_details 条目');
      continue;
    }
    try {
      result.add(KdsV2OrderDetail.fromJson(Map<String, dynamic>.from(value)));
    } on FormatException catch (error) {
      KdsFileLogger.warn(
          '[KDS] 跳过无效 order_details detail_id=${value['detail_id']}: $error');
    }
  }
  return List.unmodifiable(result);
}

class KdsV2Envelope {
  KdsV2Envelope({
    required this.eventSeq,
    required this.eventId,
    required this.type,
    required this.patches,
    this.orderDetails = const [],
    required this.queueCounts,
    this.commandId,
    this.shopId,
    this.occurredAtMs,
    this.configVersion,
    this.rejectedLineCount = 0,
  });
  final int eventSeq;
  final String eventId;
  final String type;
  final List<KdsV2Patch> patches;
  final List<KdsV2OrderDetail> orderDetails;
  final Map<String, int> queueCounts;
  final String? commandId;
  final int? shopId;
  final int? occurredAtMs;
  final int? configVersion;
  final int rejectedLineCount;

  factory KdsV2Envelope.fromJson(Map<String, dynamic> input) {
    final json = _body(input);
    _requireV2(json);
    final eventSeq = json['event_seq'];
    final eventId = json['event_id'];
    final type = json['type'];
    final rawPatches = json['patches'];
    final commandId = json['command_id'] as String?;
    if (eventSeq is! int || eventSeq < 0) {
      throw const FormatException(
          'KDS v2 event_seq must be a non-negative integer');
    }
    if (eventId is! String || eventId.trim().isEmpty) {
      throw const FormatException('KDS v2 event_id must be non-empty');
    }
    if (type is! String || type.trim().isEmpty) {
      throw const FormatException('KDS v2 event type must be non-empty');
    }
    if (rawPatches is! List) {
      throw const FormatException('KDS v2 patches must be an array');
    }
    // 单个无效 patch（如 dish_id=0 的云端虚拟行）不拖垮整个事件：
    // 跳过并告警，其余 patch 正常应用
    final patches = <KdsV2Patch>[];
    var rejectedLineCount = rawPatches.where((value) => value is! Map).length;
    for (final raw in rawPatches.whereType<Map>()) {
      try {
        patches.add(KdsV2Patch.fromJson(Map<String, dynamic>.from(raw)));
      } on FormatException catch (error) {
        rejectedLineCount++;
        KdsFileLogger.warn(
            '[KDS] 事件 $eventId 跳过无效 patch detail_id=${raw['detail_id']}: $error');
      }
    }
    return KdsV2Envelope(
      eventSeq: eventSeq,
      eventId: eventId,
      commandId: commandId,
      type: type,
      patches: List.unmodifiable(patches),
      orderDetails: _parseOrderDetails(json['order_details']),
      queueCounts: _strictCounts(json['queue_counts'], 'queue_counts'),
      shopId: json['shop_id'] == null ? null : _int(json['shop_id']),
      occurredAtMs:
          json['occurred_at_ms'] == null ? null : _int(json['occurred_at_ms']),
      configVersion:
          json['config_version'] == null ? null : _int(json['config_version']),
      rejectedLineCount: rejectedLineCount,
    );
  }
}

class KdsV2CatalogItem {
  const KdsV2CatalogItem({
    required this.dishId,
    required this.dishName,
    required this.unit,
    required this.sequence,
    this.id = 0,
    this.categoryId,
    this.categoryName = '',
    this.categorySequence,
    this.soldOut = false,
  });
  final int dishId;
  final String dishName;
  final String unit;
  final int sequence;

  /// 目录自增物理序号（`id` / `catalog_id`），全局唯一稳定排序依据；
  /// 旧收银端不返回时为 0，排序回退到分类链。
  final int id;
  final int? categoryId;
  final String categoryName;
  final int? categorySequence;

  /// 收银端目录估清（缺货）标记；占位卡据此显示「估清」
  final bool soldOut;
  factory KdsV2CatalogItem.fromJson(Map<String, dynamic> json) =>
      KdsV2CatalogItem(
        dishId: _int(json['dish_id']),
        dishName: '${json['dish_name'] ?? ''}',
        unit: '${json['unit'] ?? '份'}',
        sequence: _int(json['dish_sequence'] ?? json['sequence']),
        id: _int(json['id'] ?? json['catalog_id']),
        categoryId:
            json['category_id'] == null ? null : _int(json['category_id']),
        categoryName: '${json['category_name'] ?? ''}',
        categorySequence: json['category_sequence'] == null
            ? null
            : _int(json['category_sequence']),
        soldOut: json['sold_out'] == true,
      );
}

class KdsV2Bootstrap {
  KdsV2Bootstrap({
    required this.shopId,
    required this.eventSeq,
    required this.lines,
    required this.queueCounts,
    required this.stats,
    required this.catalog,
    this.orderDetails = const [],
    required this.config,
    this.configVersion,
    this.rejectedLineCount = 0,
    this.isStale = false,
    this.cacheAgeSeconds,
    this.cachedAtMs,
    this.servedVia,
    this.authorityCursor,
  });
  final int eventSeq;
  final int? shopId;
  final List<KdsV2Line> lines;
  final Map<String, int> queueCounts;
  final Map<String, dynamic> stats;
  final List<KdsV2CatalogItem> catalog;
  final List<KdsV2OrderDetail> orderDetails;
  final Map<String, dynamic> config;
  final int? configVersion;
  final int rejectedLineCount;
  final bool isStale;
  final int? cacheAgeSeconds;
  final int? cachedAtMs;
  final String? servedVia;
  final int? authorityCursor;

  factory KdsV2Bootstrap.fromJson(Map<String, dynamic> input) {
    final json = _body(input);
    _requireV2(json);
    final linesByDetail = <int, KdsV2Line>{};
    var rejectedLineCount = 0;
    final queues = json['queues'];
    if (queues is Map) {
      for (final entry in queues.entries) {
        final values = entry.value;
        if (values is! List) continue;
        for (final raw in values.whereType<Map>()) {
          // 单行无效（如云端套餐头/未映射行 dish_id=0）不应杀死整个看板：
          // 跳过并告警，剩余行正常加载
          final KdsV2Line line;
          try {
            line = KdsV2Line.fromJson(Map<String, dynamic>.from(raw),
                queueFallback: '${entry.key}');
          } on FormatException catch (error) {
            rejectedLineCount++;
            KdsFileLogger.warn(
                '[KDS] bootstrap 跳过无效行 detail_id=${raw['detail_id']}: $error');
            continue;
          }
          if (line.detailId <= 0) {
            rejectedLineCount++;
            KdsFileLogger.warn('[KDS] bootstrap 跳过无效行：detail_id 缺失');
            continue;
          }
          final existing = linesByDetail[line.detailId];
          if (existing == null || line.revision >= existing.revision) {
            linesByDetail[line.detailId] = line;
          }
        }
      }
    }
    final rawCatalog = json['fixed_catalog'] as List? ?? const [];
    final device = json['device'];
    final deviceJson = device is Map
        ? Map<String, dynamic>.from(device)
        : const <String, dynamic>{};
    final rawConfig = json['config'] is Map
        ? Map<String, dynamic>.from(json['config'] as Map)
        : <String, dynamic>{};
    if (json['enable_prep_workflow'] != null) {
      rawConfig['enable_prep_workflow'] =
          json['enable_prep_workflow'] == true ||
              json['enable_prep_workflow'] == 1;
    } else if (json['workflow'] is Map &&
        (json['workflow'] as Map)['enable_prep_workflow'] != null) {
      rawConfig['enable_prep_workflow'] =
          (json['workflow'] as Map)['enable_prep_workflow'] == true ||
              (json['workflow'] as Map)['enable_prep_workflow'] == 1;
    }
    final permissions = json['permissions'];
    if (permissions is Map) {
      final permissionJson = Map<String, dynamic>.from(permissions);
      for (final key in const ['visible_queues', 'allowed_commands']) {
        if (permissionJson[key] is List) {
          rawConfig[key] = List.unmodifiable(permissionJson[key] as List);
        }
      }
    }
    final transportMetadata = json['_transport_metadata'] is Map
        ? Map<String, dynamic>.from(json['_transport_metadata'] as Map)
        : const <String, dynamic>{};
    final cacheState =
        '${transportMetadata['cache_state'] ?? ''}'.trim().toUpperCase();
    return KdsV2Bootstrap(
      shopId: json['shop_id'] != null
          ? _int(json['shop_id'])
          : deviceJson['shop_id'] == null
              ? null
              : _int(deviceJson['shop_id']),
      eventSeq: _int(json['event_seq']),
      lines: List.unmodifiable(linesByDetail.values),
      queueCounts: _counts(json['queue_counts']),
      stats: json['stats'] is Map
          ? Map.unmodifiable(Map<String, dynamic>.from(json['stats'] as Map))
          : const {},
      catalog: List.unmodifiable(rawCatalog
          .whereType<Map>()
          .map((e) => KdsV2CatalogItem.fromJson(Map<String, dynamic>.from(e)))),
      orderDetails: _parseOrderDetails(json['order_details']),
      config: Map.unmodifiable(rawConfig),
      configVersion:
          json['config_version'] == null ? null : _int(json['config_version']),
      rejectedLineCount: rejectedLineCount,
      isStale: cacheState == 'STALE',
      cacheAgeSeconds: transportMetadata['age_seconds'] == null
          ? null
          : _int(transportMetadata['age_seconds']),
      cachedAtMs: transportMetadata['cached_at_ms'] == null
          ? null
          : _int(transportMetadata['cached_at_ms']),
      servedVia: transportMetadata['served_via']?.toString(),
      authorityCursor: transportMetadata['authority_cursor'] == null
          ? null
          : _int(transportMetadata['authority_cursor']),
    );
  }
}

class KdsV2Changes {
  const KdsV2Changes({
    required this.eventSeq,
    required this.snapshotRequired,
    required this.events,
  });
  final int eventSeq;
  final bool snapshotRequired;
  final List<KdsV2Envelope> events;
  factory KdsV2Changes.fromJson(Map<String, dynamic> input) {
    final json = _body(input);
    _requireV2(json);
    final events =
        json['events'] as List? ?? json['changes'] as List? ?? const [];
    if (json['event_seq'] is! int || (json['event_seq'] as int) < 0) {
      throw const FormatException(
          'KDS v2 changes is missing a valid event_seq');
    }
    return KdsV2Changes(
      eventSeq: json['event_seq'] as int,
      snapshotRequired: json['snapshot_required'] == true,
      events: List.unmodifiable(events
          .whereType<Map>()
          .map((e) => KdsV2Envelope.fromJson(Map<String, dynamic>.from(e)))),
    );
  }
}

class KdsV2CommandResult {
  KdsV2CommandResult({
    required this.commandId,
    required this.duplicate,
    required this.eventSeq,
    required this.patches,
    this.orderDetails = const [],
    required this.queueCounts,
    this.orderSummary,
  });
  final String commandId;
  final bool duplicate;
  final int eventSeq;
  final List<KdsV2Patch> patches;
  final List<KdsV2OrderDetail> orderDetails;
  final Map<String, int> queueCounts;
  final Map<String, dynamic>? orderSummary;
  factory KdsV2CommandResult.fromJson(Map<String, dynamic> input) {
    final json = _body(input);
    final commandId = json['command_id'];
    final eventSeq = json['event_seq'];
    if (commandId is! String || commandId.trim().isEmpty) {
      throw const FormatException(
          'KDS v2 command response is missing command_id');
    }
    if (eventSeq is! int || eventSeq < 0) {
      throw const FormatException(
          'KDS v2 command response is missing a valid event_seq');
    }
    if (json['patches'] is! List || json['queue_counts'] is! Map) {
      throw const FormatException(
          'KDS v2 command response is missing patches or queue_counts');
    }
    final patches = json['patches'] as List;
    return KdsV2CommandResult(
      commandId: commandId,
      duplicate: json['duplicate'] == true,
      eventSeq: eventSeq,
      patches: List.unmodifiable(patches
          .whereType<Map>()
          .map((e) => KdsV2Patch.fromJson(Map<String, dynamic>.from(e)))),
      orderDetails: _parseOrderDetails(json['order_details']),
      queueCounts: _counts(json['queue_counts']),
      orderSummary: json['order_summary'] is Map
          ? Map<String, dynamic>.from(json['order_summary'] as Map)
          : null,
    );
  }

  KdsV2Envelope asEnvelope({int? shopId, int? occurredAtMs}) => KdsV2Envelope(
        eventSeq: eventSeq,
        eventId: 'command:$commandId',
        commandId: commandId,
        type: 'command_result',
        patches: patches,
        orderDetails: orderDetails,
        queueCounts: queueCounts,
        shopId: shopId,
        occurredAtMs: occurredAtMs,
      );
}

/// The LAN cashier durably stored the command but has not obtained the cloud
/// authority's terminal result yet. This is intentionally not a successful
/// [KdsV2CommandResult]; callers must keep the same command id pending and use
/// the command-resolution endpoint before retrying.
class KdsCommandAcceptedOffline implements Exception {
  const KdsCommandAcceptedOffline(this.commandId);

  final String commandId;

  @override
  String toString() => 'KDS command accepted offline: $commandId';
}

enum KdsV2CommandResolutionStatus {
  applied,
  executing,
  rejected,
  notFound,
}

class KdsV2CommandResolution {
  const KdsV2CommandResolution({
    required this.commandId,
    required this.status,
    this.result,
  });

  final String commandId;
  final KdsV2CommandResolutionStatus status;
  final KdsV2CommandResult? result;

  factory KdsV2CommandResolution.fromJson(Map<String, dynamic> input) {
    final json = _body(input);
    _requireV2(json);
    final commandId = json['command_id'];
    if (commandId is! String || commandId.trim().isEmpty) {
      throw const FormatException(
          'KDS v2 command resolution is missing command_id');
    }

    final status = switch (json['status']) {
      'APPLIED' => KdsV2CommandResolutionStatus.applied,
      'EXECUTING' => KdsV2CommandResolutionStatus.executing,
      'REJECTED' => KdsV2CommandResolutionStatus.rejected,
      'NOT_FOUND' => KdsV2CommandResolutionStatus.notFound,
      _ => throw const FormatException(
          'KDS v2 command resolution has an invalid status'),
    };
    KdsV2CommandResult? result;
    if (status == KdsV2CommandResolutionStatus.applied) {
      final rawResult = json['result'];
      if (rawResult is! Map) {
        throw const FormatException(
            'APPLIED KDS v2 command resolution is missing result');
      }
      result = KdsV2CommandResult.fromJson(
        Map<String, dynamic>.from(rawResult),
      );
      if (result.commandId != commandId) {
        throw const FormatException(
            'KDS v2 command resolution result has mismatched command_id');
      }
    }
    return KdsV2CommandResolution(
      commandId: commandId,
      status: status,
      result: result,
    );
  }
}

/// 后厨退菜声光强提醒数据模型
class KdsRefundAlertItem {
  const KdsRefundAlertItem({
    required this.id,
    required this.tableOrPickupCode,
    required this.dishName,
    required this.quantity,
    this.unit = '份',
    required this.occurredAt,
  });

  final String id;
  final String tableOrPickupCode;
  final String dishName;
  final int quantity;
  final String unit;
  final DateTime occurredAt;
}
