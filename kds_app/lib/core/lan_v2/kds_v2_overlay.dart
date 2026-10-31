import 'package:flutter/foundation.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/storage/kds_command_outbox_store.dart';

/// 乐观操作在本地的生命周期状态
enum KdsOverlayStatus {
  persisting('PERSISTING', '落盘中'),
  pending('PENDING', '待同步'),
  sending('SENDING', '发送中'),
  unknown('UNKNOWN', '待查证'),
  conflict('CONFLICT', '冲突');

  const KdsOverlayStatus(this.wireName, this.label);
  final String wireName;
  final String label;

  static KdsOverlayStatus fromWireName(String name) {
    for (final val in KdsOverlayStatus.values) {
      if (val.wireName == name) return val;
    }
    if (name == 'RETRY_WAIT') return KdsOverlayStatus.unknown;
    return KdsOverlayStatus.pending;
  }

  static KdsOverlayStatus fromOutboxStatus(KdsOutboxStatus status,
      {bool requiresResolution = false}) {
    if (requiresResolution) return KdsOverlayStatus.unknown;
    return switch (status) {
      KdsOutboxStatus.persisting => KdsOverlayStatus.persisting,
      KdsOutboxStatus.pending => KdsOverlayStatus.pending,
      KdsOutboxStatus.sending => KdsOverlayStatus.sending,
      KdsOutboxStatus.retryWait ||
      KdsOutboxStatus.unknown =>
        KdsOverlayStatus.unknown,
      KdsOutboxStatus.conflict => KdsOverlayStatus.conflict,
      KdsOutboxStatus.acked => KdsOverlayStatus.pending,
    };
  }
}

/// 结构化乐观遮罩对象，记录单条本地未决操作的最小可逆差异
@immutable
class KdsV2OptimisticOverlay {
  const KdsV2OptimisticOverlay({
    required this.commandId,
    required this.aggregateKey,
    required this.commandType,
    required this.target,
    this.quantity,
    this.fromQueue,
    this.toQueue,
    required this.createdAt,
    this.status = KdsOverlayStatus.persisting,
    this.originChannel,
    this.lastError,
    this.retryCount = 0,
    this.lastAttemptAt,
    this.requiresResolution = false,
  });

  final String commandId;
  final String aggregateKey;
  final KdsV2CommandType commandType;
  final KdsV2CommandTarget target;
  final int? quantity;
  final String? fromQueue;
  final String? toQueue;
  final DateTime createdAt;
  final KdsOverlayStatus status;
  final String? originChannel;
  final String? lastError;
  final int retryCount;
  final DateTime? lastAttemptAt;
  final bool requiresResolution;

  int? get detailId => target.detailId;
  int? get orderId => target.orderId;

  KdsV2OptimisticOverlay copyWith({
    KdsOverlayStatus? status,
    String? originChannel,
    String? lastError,
    int? retryCount,
    DateTime? lastAttemptAt,
    bool? requiresResolution,
  }) {
    return KdsV2OptimisticOverlay(
      commandId: commandId,
      aggregateKey: aggregateKey,
      commandType: commandType,
      target: target,
      quantity: quantity,
      fromQueue: fromQueue,
      toQueue: toQueue,
      createdAt: createdAt,
      status: status ?? this.status,
      originChannel: originChannel ?? this.originChannel,
      lastError: lastError ?? this.lastError,
      retryCount: retryCount ?? this.retryCount,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      requiresResolution: requiresResolution ?? this.requiresResolution,
    );
  }

  Map<String, dynamic> toJson() => {
        'command_id': commandId,
        'aggregate_key': aggregateKey,
        'command_type': commandType.wireName,
        'target': target.toJson(),
        if (quantity != null) 'quantity': quantity,
        if (fromQueue != null) 'from_queue': fromQueue,
        if (toQueue != null) 'to_queue': toQueue,
        'created_at_ms': createdAt.millisecondsSinceEpoch,
        'status': status.wireName,
        if (originChannel != null) 'origin_channel': originChannel,
        if (lastError != null) 'last_error': lastError,
        'retry_count': retryCount,
        if (lastAttemptAt != null)
          'last_attempt_at_ms': lastAttemptAt!.millisecondsSinceEpoch,
        'requires_resolution': requiresResolution,
      };

  factory KdsV2OptimisticOverlay.fromJson(Map<String, dynamic> json) {
    final commandTypeStr = json['command_type']?.toString() ?? '';
    final commandType = KdsV2CommandType.values.firstWhere(
      (e) => e.wireName == commandTypeStr,
      orElse: () => KdsV2CommandType.advanceItem,
    );
    final rawTarget = json['target'];
    final target = rawTarget is Map<String, dynamic>
        ? KdsV2CommandTarget.fromJson(rawTarget)
        : rawTarget is Map
            ? KdsV2CommandTarget.fromJson(Map<String, dynamic>.from(rawTarget))
            : const KdsV2CommandTarget();
    final createdAtMs = json['created_at_ms'] as num? ?? 0;
    final lastAttemptMs = json['last_attempt_at_ms'] as num?;

    return KdsV2OptimisticOverlay(
      commandId: json['command_id']?.toString() ?? '',
      aggregateKey: json['aggregate_key']?.toString() ?? '',
      commandType: commandType,
      target: target,
      quantity: (json['quantity'] as num?)?.toInt(),
      fromQueue: json['from_queue']?.toString(),
      toQueue: json['to_queue']?.toString(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs.toInt()),
      status: KdsOverlayStatus.fromWireName(json['status']?.toString() ?? ''),
      originChannel: json['origin_channel']?.toString(),
      lastError: json['last_error']?.toString(),
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
      lastAttemptAt: lastAttemptMs != null
          ? DateTime.fromMillisecondsSinceEpoch(lastAttemptMs.toInt())
          : null,
      requiresResolution: json['requires_resolution'] == true,
    );
  }

  factory KdsV2OptimisticOverlay.fromCommand({
    required KdsV2Command command,
    required String aggregateKey,
    required DateTime createdAt,
    KdsOverlayStatus status = KdsOverlayStatus.persisting,
    String? originChannel,
    bool prepEnabled = true,
  }) {
    final fromQueue = command.target.fromQueue;
    final toQueue = inferDestQueue(command.type, fromQueue, prepEnabled: prepEnabled);
    return KdsV2OptimisticOverlay(
      commandId: command.commandId,
      aggregateKey: aggregateKey,
      commandType: command.type,
      target: command.target,
      quantity: command.quantity,
      fromQueue: fromQueue,
      toQueue: toQueue,
      createdAt: createdAt,
      status: status,
      originChannel: originChannel,
    );
  }

  factory KdsV2OptimisticOverlay.fromOutboxRecord(
    KdsOutboxRecord record, {
    required String aggregateKey,
    bool prepEnabled = true,
  }) {
    final cmd = record.command;
    final fromQueue = cmd.target.fromQueue;
    final toQueue = inferDestQueue(cmd.type, fromQueue, prepEnabled: prepEnabled);
    return KdsV2OptimisticOverlay(
      commandId: record.id,
      aggregateKey: aggregateKey,
      commandType: cmd.type,
      target: cmd.target,
      quantity: cmd.quantity,
      fromQueue: fromQueue,
      toQueue: toQueue,
      createdAt: record.createdAt,
      status: KdsOverlayStatus.fromOutboxStatus(
        record.status,
        requiresResolution: record.requiresResolution,
      ),
      originChannel: record.originChannel,
      lastError: record.lastError,
      retryCount: record.retryCount,
      lastAttemptAt: record.lastAttemptAt,
      requiresResolution: record.requiresResolution,
    );
  }
}

/// 根据操作类型与来源队列推断目标队列
String? inferDestQueue(
  KdsV2CommandType type,
  String? fromQueue, {
  bool prepEnabled = true,
}) {
  if (type == KdsV2CommandType.advanceItem ||
      type == KdsV2CommandType.advanceOrder) {
    return switch (fromQueue) {
      'pending_prep' => 'pending_cook',
      'pending_cook' => 'ready_serve',
      'ready_serve' => 'done',
      _ => null,
    };
  }
  if (type == KdsV2CommandType.revokeItem) {
    return switch (fromQueue) {
      'done' => 'ready_serve',
      'ready_serve' => prepEnabled ? 'pending_cook' : 'pending_cook',
      'pending_cook' => prepEnabled ? 'pending_prep' : null,
      _ => null,
    };
  }
  return null;
}

int _int(dynamic value, [int fallback = 0]) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? fallback;

/// 将有序乐观遮罩叠加至权威明细行列表，计算可见明细行列表
List<KdsV2Line> applyOverlaysToLines(
  Iterable<KdsV2Line> lines,
  Iterable<KdsV2OptimisticOverlay> overlays,
) {
  if (overlays.isEmpty) return lines.toList(growable: false);

  final overlaysByDetail = <int, List<KdsV2OptimisticOverlay>>{};
  for (final overlay in overlays) {
    final detailId = overlay.detailId;
    if (detailId != null && detailId > 0) {
      overlaysByDetail.putIfAbsent(detailId, () => []).add(overlay);
    }
  }

  if (overlaysByDetail.isEmpty) return lines.toList(growable: false);

  final result = <KdsV2Line>[];

  for (final line in lines) {
    final lineOverlays = overlaysByDetail[line.detailId];
    if (lineOverlays == null || lineOverlays.isEmpty) {
      result.add(line);
      continue;
    }

    final hasCumulativeQuantities = const [
      'prep_remaining',
      'cook_remaining',
      'ready_remaining',
    ].any(line.raw.containsKey);

    if (hasCumulativeQuantities) {
      var prepRemaining = _int(line.raw['prep_remaining']);
      var cookRemaining = _int(line.raw['cook_remaining']);
      var readyRemaining = _int(line.raw['ready_remaining']);
      final lineQuantity = _int(line.raw['line_quantity'] ?? line.quantity);
      final refundedQuantity = _int(line.raw['refunded_quantity']);
      final activeQuantity = lineQuantity - refundedQuantity;

      final optimisticQueues = <String, KdsOverlayStatus>{};
      final optimisticCommandIds = <String, String>{};

      for (final o in lineOverlays) {
        final qty = (o.quantity != null && o.quantity! > 0)
            ? o.quantity!
            : 1;

        if (o.commandType == KdsV2CommandType.advanceItem ||
            o.commandType == KdsV2CommandType.advanceOrder) {
          switch (o.fromQueue) {
            case 'pending_prep':
              prepRemaining = (prepRemaining - qty).clamp(0, cookRemaining);
              optimisticQueues['pending_cook'] = o.status;
              optimisticCommandIds['pending_cook'] = o.commandId;
              break;
            case 'pending_cook':
              cookRemaining = (cookRemaining - qty).clamp(prepRemaining, readyRemaining);
              optimisticQueues['ready_serve'] = o.status;
              optimisticCommandIds['ready_serve'] = o.commandId;
              break;
            case 'ready_serve':
              readyRemaining = (readyRemaining - qty).clamp(cookRemaining, activeQuantity);
              optimisticQueues['done'] = o.status;
              optimisticCommandIds['done'] = o.commandId;
              break;
          }
        } else if (o.commandType == KdsV2CommandType.revokeItem) {
          switch (o.fromQueue) {
            case 'done':
              readyRemaining = (readyRemaining + qty).clamp(0, activeQuantity);
              optimisticQueues['ready_serve'] = o.status;
              optimisticCommandIds['ready_serve'] = o.commandId;
              break;
            case 'ready_serve':
              cookRemaining = (cookRemaining + qty).clamp(0, readyRemaining);
              optimisticQueues['pending_cook'] = o.status;
              optimisticCommandIds['pending_cook'] = o.commandId;
              break;
            case 'pending_cook':
              prepRemaining = (prepRemaining + qty).clamp(0, cookRemaining);
              optimisticQueues['pending_prep'] = o.status;
              optimisticCommandIds['pending_prep'] = o.commandId;
              break;
          }
        }
      }

      final updatedRaw = Map<String, dynamic>.from(line.raw);
      updatedRaw['prep_remaining'] = prepRemaining;
      updatedRaw['cook_remaining'] = cookRemaining;
      updatedRaw['ready_remaining'] = readyRemaining;

      result.add(KdsV2Line(
        detailId: line.detailId,
        orderId: line.orderId,
        dishId: line.dishId,
        dishName: line.dishName,
        quantity: line.quantity,
        queue: line.queue,
        fulfillmentBucket: line.fulfillmentBucket,
        revision: line.revision,
        raw: Map.unmodifiable(updatedRaw),
        optimisticQueues: Map.unmodifiable(optimisticQueues),
        optimisticCommandIds: Map.unmodifiable(optimisticCommandIds),
      ));
    } else {
      // 兼容非累计切片老结构
      var effectiveQueue = line.queue;
      final optimisticQueues = <String, KdsOverlayStatus>{};
      final optimisticCommandIds = <String, String>{};

      for (final o in lineOverlays) {
        if (o.toQueue != null && o.toQueue!.isNotEmpty) {
          effectiveQueue = o.toQueue!;
          optimisticQueues[effectiveQueue] = o.status;
          optimisticCommandIds[effectiveQueue] = o.commandId;
        }
      }

      result.add(KdsV2Line(
        detailId: line.detailId,
        orderId: line.orderId,
        dishId: line.dishId,
        dishName: line.dishName,
        quantity: line.quantity,
        queue: effectiveQueue,
        fulfillmentBucket: line.fulfillmentBucket,
        revision: line.revision,
        raw: line.raw,
        optimisticQueues: Map.unmodifiable(optimisticQueues),
        optimisticCommandIds: Map.unmodifiable(optimisticCommandIds),
      ));
    }
  }

  return result;
}
