import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';

class KdsV2State {
  const KdsV2State({
    this.eventSeq = 0,
    this.lines = const [],
    this.queueCounts = const {},
    this.stats = const {},
    this.catalog = const [],
    this.orderDetails = const [],
    this.config = const {},
    this.configVersion,
    this.optimisticHiddenSlices = const {},
    this.overlays = const [],
    this.connected = false,
    this.loading = false,
    this.error,
    this.lastEventAtMs,
    this.rejectedLineCount = 0,
    this.pendingSyncCount = 0,
    this.allChannelsUnavailable = false,
    this.isStale = false,
    this.cacheAgeSeconds,
    this.cachedAtMs,
    this.servedVia,
    this.authorityCursor,
  });
  final int eventSeq;
  final List<KdsV2Line> lines;
  final Map<String, int> queueCounts;
  final Map<String, dynamic> stats;
  final List<KdsV2CatalogItem> catalog;
  final List<KdsV2OrderDetail> orderDetails;
  final Map<String, dynamic> config;
  final int? configVersion;
  final Set<String> optimisticHiddenSlices;
  final List<KdsV2OptimisticOverlay> overlays;
  final bool connected;
  final bool loading;
  final String? error;

  /// 最近一次收到业务事件的本地毫秒时间（仅由 provider 层标注，
  /// reducer 不改写），用于顶栏展示"最近事件时间/无事件时长"。
  final int? lastEventAtMs;
  final int rejectedLineCount;

  /// 待同步给收银端的离线指令数量
  final int pendingSyncCount;
  final bool allChannelsUnavailable;
  final bool isStale;
  final int? cacheAgeSeconds;
  final int? cachedAtMs;
  final String? servedVia;
  final int? authorityCursor;

  bool get realtimeReady => connected && !isStale && !loading && error == null;

  /// 已有权威快照（内存或本地恢复）时允许操作；provider 会将指令放入
  /// 待同步队列，连接恢复后再按顺序发送。刷新/bootstrap 失败（error）只
  /// 代表“本次未能刷新”，显式离线（未连接）时快照仍可信，不阻断离线划菜；
  /// 仅“已连接但同步异常”（协议损坏/半连接）时锁定写入。
  bool get canMutate =>
      lines.isNotEmpty && !loading && (error == null || !connected);
  factory KdsV2State.fromBootstrap(KdsV2Bootstrap value,
          {bool connected = false, int pendingSyncCount = 0}) =>
      KdsV2State(
        eventSeq: value.eventSeq,
        lines: value.lines,
        queueCounts: value.queueCounts,
        stats: value.stats,
        catalog: value.catalog,
        orderDetails: value.orderDetails,
        config: value.config,
        configVersion: value.configVersion,
        rejectedLineCount: value.rejectedLineCount,
        connected: connected,
        pendingSyncCount: pendingSyncCount,
        isStale: value.isStale,
        cacheAgeSeconds: value.cacheAgeSeconds,
        cachedAtMs: value.cachedAtMs,
        servedVia: value.servedVia,
        authorityCursor: value.authorityCursor,
      );

  KdsV2State copyWith({
    int? eventSeq,
    List<KdsV2Line>? lines,
    Map<String, int>? queueCounts,
    Map<String, dynamic>? stats,
    List<KdsV2CatalogItem>? catalog,
    List<KdsV2OrderDetail>? orderDetails,
    Map<String, dynamic>? config,
    int? configVersion,
    Set<String>? optimisticHiddenSlices,
    List<KdsV2OptimisticOverlay>? overlays,
    bool? connected,
    bool? loading,
    String? error,
    int? lastEventAtMs,
    int? rejectedLineCount,
    int? pendingSyncCount,
    bool? allChannelsUnavailable,
    bool? isStale,
    int? cacheAgeSeconds,
    int? cachedAtMs,
    String? servedVia,
    int? authorityCursor,
    bool clearCacheMetadata = false,
    bool clearError = false,
  }) =>
      KdsV2State(
        eventSeq: eventSeq ?? this.eventSeq,
        lines: lines ?? this.lines,
        queueCounts: queueCounts ?? this.queueCounts,
        stats: stats ?? this.stats,
        catalog: catalog ?? this.catalog,
        orderDetails: orderDetails ?? this.orderDetails,
        config: config ?? this.config,
        configVersion: configVersion ?? this.configVersion,
        optimisticHiddenSlices:
            optimisticHiddenSlices ?? this.optimisticHiddenSlices,
        overlays: overlays ?? this.overlays,
        connected: connected ?? this.connected,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        lastEventAtMs: lastEventAtMs ?? this.lastEventAtMs,
        rejectedLineCount: rejectedLineCount ?? this.rejectedLineCount,
        pendingSyncCount: pendingSyncCount ?? this.pendingSyncCount,
        allChannelsUnavailable:
            allChannelsUnavailable ?? this.allChannelsUnavailable,
        isStale: clearCacheMetadata ? false : (isStale ?? this.isStale),
        cacheAgeSeconds: clearCacheMetadata
            ? null
            : (cacheAgeSeconds ?? this.cacheAgeSeconds),
        cachedAtMs: clearCacheMetadata ? null : (cachedAtMs ?? this.cachedAtMs),
        servedVia: clearCacheMetadata ? null : (servedVia ?? this.servedVia),
        authorityCursor: clearCacheMetadata
            ? null
            : (authorityCursor ?? this.authorityCursor),
      );
}

abstract final class KdsV2Reducer {
  static KdsV2State applyEnvelope(KdsV2State state, KdsV2Envelope event) {
    final byDetail = {for (final line in state.lines) line.detailId: line};
    for (final patch in event.patches) {
      if (patch.removed) {
        final existing = byDetail[patch.detailId];
        // 已完成菜品持久化：明细已全部划到完成（无活动切片）时，
        // 收银端结账/清理的 removed 事件不删除行，仅标记 removed
        // 保留在已完成页（避免「划完菜过一会就不见了」）；
        // 仍有活动数量的退菜/作废才按协议删除。
        if (existing != null && !_hasActiveQuantity(existing)) {
          byDetail[patch.detailId] = existing.withRawFields({'removed': true});
        } else {
          byDetail.remove(patch.detailId);
        }
      } else if (patch.line != null) {
        final previous = byDetail[patch.detailId];
        var next = patch.line!;
        // 收银端约定：完成数量增加时必须刷新 completed_at_ms。旧版或
        // 降级 patch 偶尔会携带上一次的时间，不能让它把最新划菜排序卡住。
        if (_doneQuantity(next) > _doneQuantity(previous) &&
            event.occurredAtMs != null &&
            _completedAtMs(next) <= _completedAtMs(previous)) {
          next = next.withRawFields({'completed_at_ms': event.occurredAtMs});
        }
        byDetail[patch.detailId] = next;
      }
    }
    return state.copyWith(
      eventSeq: event.eventSeq,
      lines: List.unmodifiable(byDetail.values),
      orderDetails: _mergeOrderDetails(state.orderDetails, event.orderDetails),
      queueCounts:
          event.queueCounts.isEmpty ? state.queueCounts : event.queueCounts,
      clearError: true,
      rejectedLineCount: state.rejectedLineCount + event.rejectedLineCount,
      clearCacheMetadata: true,
    );
  }

  static List<KdsV2OrderDetail> _mergeOrderDetails(
    List<KdsV2OrderDetail> current,
    List<KdsV2OrderDetail> replacements,
  ) {
    if (replacements.isEmpty) return current;
    final replacedOrderIds =
        replacements.map((detail) => detail.orderId).toSet();
    return List.unmodifiable([
      ...current.where(
        (detail) => !replacedOrderIds.contains(detail.orderId),
      ),
      ...replacements,
    ]);
  }

  /// 明细是否仍有活动（未完成）切片：有活动数量时 removed 必须删除
  ///（退菜/作废），全部完成时 removed 仅标记保留。
  static bool _hasActiveQuantity(KdsV2Line line) =>
      line.slices.any((slice) => slice.queue != 'done' && slice.quantity > 0);

  static int _doneQuantity(KdsV2Line? line) => line == null
      ? 0
      : line.slices
          .where((slice) => slice.queue == 'done')
          .fold(0, (sum, slice) => sum + slice.quantity);

  static int _completedAtMs(KdsV2Line? line) {
    final value = line?.raw['completed_at_ms'];
    return value is num ? value.toInt() : 0;
  }
}
