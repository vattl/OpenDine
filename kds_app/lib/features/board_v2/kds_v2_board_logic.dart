import 'package:kds_app/core/board/kds_spec_text.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';

/// 菜品维度展示合并键。
///
/// 固定模式按 dishId 合并；非固定模式开启“同名合并”时，忽略规格和
/// dishId，只按名称合并，但仍隔离履约渠道，避免堂食/外卖共用一张卡而
/// 导致表头和划菜语义混淆。
String dishNameMergeKey(KdsV2LineSlice slice) {
  final name = slice.dishName.trim();
  final channel = slice.channel.trim().toLowerCase();
  return '$name:$channel';
}

const prepFlowBusyMessage = '当前配菜流程仍有菜品，请完成配菜后在关闭';

bool canDisablePrepFlow(Iterable<KdsV2Line> lines) => !lines.any(
      (line) => line.slices.any(
        (slice) => slice.queue == 'pending_prep' && slice.quantity > 0,
      ),
    );

/// 取餐码 / 云端订单 ID 提取辅助：**严格仅使用 cloud_order_id，禁止使用本地收银 order_id**
///
/// 优先级：
/// 1. 云端订单主键 `cloud_order_id`（t_order.id，如 13909）；
/// 2. 同单其它明细行已知的云端订单主键（同单补齐）；
/// 3. 若无云端 ID 则返回 null。
int? extractCloudOrderId(KdsV2LineSlice line, [Iterable<KdsV2LineSlice>? group]) {
  var cloudId = line.cloudOrderId;
  if (cloudId == null && group != null) {
    for (final slice in group) {
      if (slice.orderId == line.orderId && slice.cloudOrderId != null) {
        cloudId = slice.cloudOrderId;
        break;
      }
    }
  }
  return cloudId;
}

String? kdsPickupCode(KdsV2LineSlice line, [Iterable<KdsV2LineSlice>? group]) {
  final cloudId = extractCloudOrderId(line, group);
  return cloudId != null ? '$cloudId' : null;
}

/// 订单 ID 展示辅助：**以云端 t_order 为准**（仅使用 cloud_order_id，不使用本地收银 ID 或订单号）。
String orderDisplayId(KdsV2LineSlice line, [Iterable<KdsV2LineSlice>? group]) {
  final cloudId = extractCloudOrderId(line, group);
  if (cloudId != null) return '$cloudId';
  return '';
}

/// 解析权威行或明细行的台号/取餐码标识：堂食单显示台号，自提/外卖/打包显示取餐码（cloud_order_id）
String resolveLineTableOrPickupCode({
  required String channel,
  required Map<String, dynamic> raw,
  int? cloudOrderId,
  int? orderId,
  Iterable<KdsV2Line>? allLines,
}) {
  final normalizedChannel = channel.trim().toLowerCase();
  final prefix = switch (normalizedChannel) {
    'dine_in' => null,
    'pack' => '打包',
    'pickup' => '自提',
    'delivery' || 'takeout' => '外卖',
    _ => null,
  };
  var code = cloudOrderId;
  if (code == null && orderId != null && allLines != null) {
    for (final candidate in allLines) {
      if (candidate.orderId == orderId && candidate.cloudOrderId != null) {
        code = candidate.cloudOrderId;
        break;
      }
    }
  }
  if (prefix == null) {
    final table = '${raw['table_number'] ?? ''}'.trim();
    if (table.isNotEmpty) return table;
    return code != null ? '堂食 $code' : '堂食';
  }
  return code != null ? '$prefix $code' : prefix;
}

/// 整单推进的目标行：该订单中流程仍停留在 [fromQueue] 的明细行。
///
/// 整单推进必须逐明细 advanceItem，禁止整单 advanceOrder——
/// 同一张单的部分明细可能已进入待传菜，整单推进会把待传菜的直接划走；
/// 只返回 [fromQueue] 队列的行，严格遵循单一流程。
List<KdsV2Line> orderLinesToAdvance(
  Iterable<KdsV2Line> lines, {
  required int orderId,
  required String fromQueue,
  bool includePrep = false,
}) {
  final targetQueues = (fromQueue == 'pending_cook' && includePrep)
      ? const {'pending_cook', 'pending_prep'}
      : {fromQueue};
  return lines
      .where((line) => line.orderId == orderId)
      .where((line) => line.slices.any(
          (slice) => targetQueues.contains(slice.queue) && slice.quantity > 0))
      .toList(growable: false);
}

/// 计算配菜流程关闭时需要自动推进的明细行（只含仍有待配菜数量的行）。
///
/// [onlyOrderIds] 非空时只保留本次事件涉及的订单：重连/启动兜底、
/// 以及不相关的其他新单，都不会把历史滞留的加菜行捎带推走。
///
/// 调用方必须对返回的行**逐明细 advanceItem**（fromQueue=pending_prep），
/// 禁止整单 advanceOrder——同一张单的部分明细可能已进入待传菜，
/// 整单推进会把待传菜的直接划走。
List<KdsV2Line> prepLinesToAdvance(
  Iterable<KdsV2Line> lines, {
  Set<int>? onlyOrderIds,
}) {
  return lines
      .where((line) =>
          (onlyOrderIds == null || onlyOrderIds.contains(line.orderId)) &&
          line.slices.any(
              (slice) => slice.queue == 'pending_prep' && slice.quantity > 0))
      .toList(growable: false);
}

int compareKdsCatalogItems(KdsV2CatalogItem a, KdsV2CatalogItem b) {
  // 规范排序：服务端按 category_sequence ➔ category_id ➔
  // dish_sequence ➔ dish_id 生成连续自增 id 并固定入库、按 id ASC 返回。
  // 排序字段（category_sequence/dish_sequence）允许重复，因此 id/catalog_id
  // 是全局唯一稳定排序依据，客户端直接以 id 升序排列。
  if (a.id > 0 && b.id > 0 && a.id != b.id) return a.id.compareTo(b.id);
  // 兼容旧收银端（无 id 字段）：回退分类排序链，dishId 兜底。
  const missing = 0x7fffffff;
  final byCategorySequence =
      (a.categorySequence ?? missing).compareTo(b.categorySequence ?? missing);
  if (byCategorySequence != 0) return byCategorySequence;
  final byCategoryId =
      (a.categoryId ?? missing).compareTo(b.categoryId ?? missing);
  if (byCategoryId != 0) return byCategoryId;
  final byDishSequence = a.sequence.compareTo(b.sequence);
  if (byDishSequence != 0) return byDishSequence;
  return a.dishId.compareTo(b.dishId);
}

class KdsV2OrderDisplayLine {
  const KdsV2OrderDisplayLine({
    required this.detailId,
    required this.dishName,
    required this.quantity,
    required this.currentQueueQuantity,
    required this.removed,
    this.orderRushed = false,
    this.unit = '份',
    this.createdAtMs,
    this.rushed = false,
    this.addDish = false,
    this.remainingQuantity = 0,
    this.activeQuantity = 0,
    this.revision,
    this.specText,
    this.overlayStatus,
    this.raw = const {},
  });

  final int detailId;
  final String dishName;
  final int quantity;
  final int currentQueueQuantity;
  final bool removed;

  /// 乐观遮罩状态（若当前行处于本地未决操作中）
  final KdsOverlayStatus? overlayStatus;

  /// 整单催菜/加急（v2.2 order_details.order_rushed 或行级 rushed）
  final bool orderRushed;

  /// 单位（串/份）
  final String unit;

  /// 行创建时间（逐行等待时长与超时标记）；无权威值时为 null
  final int? createdAtMs;

  /// 行级催菜
  final bool rushed;

  /// 加菜行
  final bool addDish;

  /// 全队列剩余可操作数量（不含 done，用于「已传 x/y」进度）
  final int remainingQuantity;

  /// 活跃数量（quantity - refunded），「已传 x/y」的分母
  final int activeQuantity;

  /// 行乐观锁版本（local_revision），行级推进必填；无权威行时为 null
  ///（不可推进）
  final int? revision;

  /// 规格/辣度等可展示文案（如「微辣,9成熟」），无规格时为 null
  final String? specText;

  /// 原始行数据（用于提取完成时间戳等）
  final Map<String, dynamic> raw;

  bool get isInCurrentQueue => !removed && currentQueueQuantity > 0;

  /// 当前队列仍有切片时展示该切片数量；划出一部分后数量随权威投影递减。
  /// 已离开当前队列的只读历史行仍展示原始下单数量。
  int get displayQuantity =>
      isInCurrentQueue ? currentQueueQuantity : quantity;
}

List<KdsV2OrderDisplayLine> projectOrderDetails({
  required Iterable<KdsV2Line> lines,
  Iterable<KdsV2OrderDetail> orderDetails = const [],
  required int orderId,
  required String currentQueue,
  bool includePrep = false,
}) {
  final operational = {
    for (final line in lines.where((line) => line.orderId == orderId))
      line.detailId: line,
  };
  final targetQueues = (currentQueue == 'pending_cook' && includePrep)
      ? const {'pending_cook', 'pending_prep'}
      : {currentQueue};
  int remainingAll(KdsV2Line? line) =>
      line?.slices
          .where((slice) => slice.queue != 'done')
          .fold<int>(0, (sum, slice) => sum + slice.quantity) ??
      0;
  int? createdAtOf(Map<String, dynamic> raw) =>
      (raw['created_at_ms'] as num?)?.toInt();
  // 规格/辣度：优先权威行 raw（selectedSpicy/spec_norm/taste_norm），
  // 回退 order_details.specification；统一走 KdsSpecText 解析
  String? specTextOf(KdsV2Line? line, String? specification) =>
      (line != null
          ? KdsSpecText.fromLine(line.raw, includeTaste: true)
          : null) ??
      KdsSpecText.parseOptionJson(specification, includeTaste: true);
  KdsOverlayStatus? overlayStatusOf(KdsV2Line? line) {
    if (line == null) return null;
    for (final slice in line.slices) {
      if (targetQueues.contains(slice.queue) && slice.overlayStatus != null) {
        return slice.overlayStatus;
      }
    }
    return null;
  }

  final projection =
      orderDetails.where((detail) => detail.orderId == orderId).map((detail) {
    final line = operational[detail.detailId];
    final currentQuantity = line?.slices
            .where((slice) => targetQueues.contains(slice.queue))
            .fold<int>(0, (sum, slice) => sum + slice.quantity) ??
        0;
    return KdsV2OrderDisplayLine(
      detailId: detail.detailId,
      dishName: detail.dishName,
      quantity: detail.quantity,
      currentQueueQuantity: currentQuantity,
      removed: detail.removed,
      orderRushed: detail.orderRushed || line?.raw['rushed'] == true,
      unit: detail.unit,
      createdAtMs: createdAtOf(line?.raw ?? detail.raw),
      rushed: line?.raw['rushed'] == true,
      addDish:
          line?.raw['add_dish'] == true || line?.raw['is_add_dish'] == true,
      remainingQuantity:
          line != null ? remainingAll(line) : detail.remainingQuantity,
      activeQuantity: detail.remainingQuantity,
      revision: line?.revision,
      specText: specTextOf(line, detail.specification),
      overlayStatus: overlayStatusOf(line),
      // 没有可操作权威行（例如已退菜）时，仍保留 order_details 的
      // 菜品级 serving_duration_minutes 等只读展示字段。
      raw: line?.raw ?? detail.raw,
    );
  }).toList();
  if (projection.isNotEmpty) return projection;

  final result = operational.values.map((line) {
    final activeQuantity =
        ((line.raw['line_quantity'] as num?)?.toInt() ?? line.quantity) -
            ((line.raw['refunded_quantity'] as num?)?.toInt() ?? 0);
    final currentQuantity = line.slices
        .where((slice) => targetQueues.contains(slice.queue))
        .fold<int>(0, (sum, slice) => sum + slice.quantity);
    return KdsV2OrderDisplayLine(
      detailId: line.detailId,
      dishName: line.dishName,
      quantity: activeQuantity.clamp(0, 0x7fffffff),
      currentQueueQuantity: currentQuantity,
      removed: false,
      orderRushed: line.raw['rushed'] == true,
      unit: '${line.raw['unit'] ?? '份'}',
      createdAtMs: createdAtOf(line.raw),
      rushed: line.raw['rushed'] == true,
      addDish: line.raw['add_dish'] == true || line.raw['is_add_dish'] == true,
      remainingQuantity: remainingAll(line),
      activeQuantity: activeQuantity.clamp(0, 0x7fffffff),
      revision: line.revision,
      specText: KdsSpecText.fromLine(line.raw, includeTaste: true),
      overlayStatus: overlayStatusOf(line),
      raw: line.raw,
    );
  }).toList()
    ..sort((a, b) {
      final aCreated =
          (operational[a.detailId]?.raw['created_at_ms'] as num?)?.toInt() ?? 0;
      final bCreated =
          (operational[b.detailId]?.raw['created_at_ms'] as num?)?.toInt() ?? 0;
      final byCreated = aCreated.compareTo(bCreated);
      return byCreated != 0 ? byCreated : a.detailId.compareTo(b.detailId);
    });
  return result;
}

int completedAtMs(Map<String, dynamic> raw) {
  for (final key in const [
    'completed_at_ms',
    'queue_completed_at',
    'served_at',
    'completed_at',
  ]) {
    final value = raw[key];
    if (value is num) return value.toInt();
  }
  return 0;
}

int compareCompletedSlices(KdsV2LineSlice a, KdsV2LineSlice b) {
  final byCompletion = completedAtMs(b.raw).compareTo(completedAtMs(a.raw));
  return byCompletion != 0 ? byCompletion : b.detailId.compareTo(a.detailId);
}

Set<String> optimisticAdvanceKeys({
  required Iterable<KdsV2Line> lines,
  required KdsV2CommandType type,
  required KdsV2CommandTarget target,
}) {
  if (type != KdsV2CommandType.advanceItem &&
      type != KdsV2CommandType.advanceOrder) {
    return const {};
  }
  final queue = target.fromQueue;
  if (queue == null || queue.isEmpty) return const {};
  final ids = <int>{
    if (target.detailId != null) target.detailId!,
    ...target.detailIds,
  };
  return lines
      .where((line) => target.orderId != null
          ? line.orderId == target.orderId
          : ids.contains(line.detailId))
      .where((line) => line.slices.any((slice) => slice.queue == queue))
      .map((line) => '${line.detailId}:$queue')
      .toSet();
}

/// 计算看板当前视图下的切片统计计数。
///
/// 订单视图下统计订单数（唯一 orderId 数量）；
/// 菜品视图下统计活动菜品卡片数（固定菜位/同名合并规则；已完成队列不合并，保留独立批次卡片）。
int countBoardSlices({
  required Iterable<KdsV2LineSlice> slices,
  required bool isDishView,
  bool isDone = false,
  bool fixedDishOrderEnabled = true,
  bool mergeSameDishNameEnabled = true,
}) {
  if (slices.isEmpty) return 0;
  if (!isDishView) {
    // 订单视图：统计订单数（唯一单数）
    return slices.map((s) => s.orderId).toSet().length;
  }
  // 菜品视图：
  if (isDone) {
    // 已完成队列不合并，保留独立完成批次卡片
    return slices.map((s) => s.detailId).toSet().length;
  }
  if (fixedDishOrderEnabled) {
    // 固定菜位模式：按 mergeKey（dishId:channel）聚合活动菜品卡片
    return slices.map((s) => s.mergeKey).toSet().length;
  }
  if (mergeSameDishNameEnabled) {
    // 同名合并模式：按 dishName:channel 聚合
    return slices.map((s) => dishNameMergeKey(s)).toSet().length;
  }
  // 自由流单菜卡片：按 detailId 区分
  return slices.map((s) => s.detailId).toSet().length;
}
