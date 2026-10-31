import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';

abstract interface class KdsV2Transport {
  Future<KdsV2Bootstrap> bootstrap();
  Future<Map<String, dynamic>> businessDayOrders(
      {int? afterId, int limit = 200});
  Future<KdsV2Changes> changes(int afterSeq);
  Future<KdsV2CommandResult> command(KdsV2Command command);
  Future<void> updateConfig(Map<String, dynamic> config);
}

/// Optional capability for resolving a command whose acknowledgement was lost.
///
/// Kept separate from [KdsV2Transport] so older/local transports can remain
/// read/write compatible without pretending that they can safely arbitrate an
/// UNKNOWN command.
abstract interface class KdsV2CommandResolver {
  Future<KdsV2CommandResolution> resolveCommand(String commandId);
}

enum KdsDishLoadSource {
  bootstrapHttp,
  localCache,
  websocketPush,
  websocketBuffered,
  changesPoll,
  changesReconnect,
  changesGapRecovery,
  changesConflictRecovery,
  commandResponse,
  businessDaySnapshot,
  unknown,
}

extension KdsDishLoadSourceCode on KdsDishLoadSource {
  String get code => switch (this) {
        KdsDishLoadSource.bootstrapHttp => 'bootstrap_http',
        KdsDishLoadSource.localCache => 'local_cache',
        KdsDishLoadSource.websocketPush => 'websocket_push',
        KdsDishLoadSource.websocketBuffered => 'websocket_buffered',
        KdsDishLoadSource.changesPoll => 'changes_poll',
        KdsDishLoadSource.changesReconnect => 'changes_reconnect',
        KdsDishLoadSource.changesGapRecovery => 'changes_gap_recovery',
        KdsDishLoadSource.changesConflictRecovery =>
          'changes_conflict_recovery',
        KdsDishLoadSource.commandResponse => 'command_response',
        KdsDishLoadSource.businessDaySnapshot => 'business_day_snapshot',
        KdsDishLoadSource.unknown => 'unknown',
      };

  String get transport => switch (this) {
        KdsDishLoadSource.bootstrapHttp ||
        KdsDishLoadSource.changesPoll ||
        KdsDishLoadSource.changesReconnect ||
        KdsDishLoadSource.changesGapRecovery ||
        KdsDishLoadSource.changesConflictRecovery ||
        KdsDishLoadSource.commandResponse ||
        KdsDishLoadSource.businessDaySnapshot =>
          'http',
        KdsDishLoadSource.websocketPush ||
        KdsDishLoadSource.websocketBuffered =>
          'websocket',
        KdsDishLoadSource.localCache => 'local_storage',
        KdsDishLoadSource.unknown => 'unknown',
      };
}

class KdsDishLoadTrace {
  const KdsDishLoadTrace({
    required this.source,
    required this.eventSeq,
    required this.lineCount,
    this.eventId,
    this.eventType,
    this.patchCount = 0,
    this.channel,
  });

  final KdsDishLoadSource source;
  final int eventSeq;
  final String? eventId;
  final String? eventType;
  final int patchCount;
  final int lineCount;
  final String? channel;
}

class KdsV2Controller {
  KdsV2Controller(
    this.transport, {
    void Function(KdsV2State)? onState,
    void Function(KdsV2Envelope)? onEnvelopeApplied,
    void Function(KdsDishLoadTrace)? onDishLoad,
    String Function()? channelLabel,
    this.expectedShopId,
    this.onBootstrapApplied,
  })  : _onState = onState,
        _onEnvelopeApplied = onEnvelopeApplied,
        _onDishLoad = onDishLoad,
        _channelLabel = channelLabel;
  final KdsV2Transport transport;
  final void Function(KdsV2State)? _onState;
  final void Function(KdsV2Envelope)? _onEnvelopeApplied;
  final void Function(KdsDishLoadTrace)? _onDishLoad;
  final String Function()? _channelLabel;
  final int? expectedShopId;

  /// bootstrap 成功应用后回调（config_changed/重连/冲突等 controller
  /// 内部触发的全量重建也会回调），供 provider 立即补拉营业时段快照，
  /// 避免已完成页在分钟级轮询前出现空窗。
  final void Function()? onBootstrapApplied;
  KdsV2State state = const KdsV2State();
  final LinkedHashSet<String> _seenEventIds = LinkedHashSet();
  Future<void>? _recovery;
  Future<void>? _reconnectInFlight;
  final Map<String, String> _ambiguousCommandIds = {};
  final Map<String, Future<KdsV2CommandResult>> _commandsInFlight = {};
  int _bootstrapGeneration = 0;

  /// 最近一次合并的营业时段窗口（ms），用于判断窗口是否变化：
  /// 同一窗口内重复拉取快照时保留内存中的已完成历史行（快照归档/缺页
  /// 不会导致已完成菜品消失），仅窗口变化（换营业时段）时清除重建。
  int _historyWindowStartMs = 0;
  int _historyWindowEndMs = 0;

  /// 当前营业时段窗口是否已过期（用于控制快照拉取频率，杜绝每分钟高频全量拉取）。
  bool get isBusinessDayWindowExpired {
    if (_historyWindowEndMs <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch > _historyWindowEndMs;
  }

  Future<void> updateConfig(Map<String, dynamic> config) async {
    await transport.updateConfig(config);
    await start(force: true);
  }

  /// 已通过 bootstrap 对齐过的最高 config_version。
  /// 收银端可能在事件里递增 config_version 但 bootstrap 不回传该字段，
  /// 用此下限避免每个带版本事件都重复触发全量引导。
  int _configVersionFloor = -1;

  void _emit(KdsV2State next) {
    state = next;
    _onState?.call(next);
  }

  Future<void> start({bool force = false}) async {
    final generation = ++_bootstrapGeneration;
    _emit(state.copyWith(loading: true, clearError: true));
    try {
      final value = await transport.bootstrap();
      if (expectedShopId != null && value.shopId != expectedShopId) {
        throw const FormatException('KDS v2 bootstrap shop_id mismatch');
      }
      if (generation != _bootstrapGeneration) return;
      if (!force && value.eventSeq < state.eventSeq) {
        _emit(state.copyWith(loading: false, clearError: true));
        return;
      }
      final bootConfigVersion = value.configVersion;
      if (bootConfigVersion != null &&
          bootConfigVersion > _configVersionFloor) {
        _configVersionFloor = bootConfigVersion;
      }
      _seenEventIds.clear();
      final bootState = KdsV2State.fromBootstrap(
        value,
        connected: state.connected && !value.isStale,
        pendingSyncCount: state.pendingSyncCount,
      );
      // 已完成页诊断：bootstrap 通常只返回活动队列，done 行依赖快照接口
      final doneInBoot = value.lines
          .where((line) => line.slices
              .any((slice) => slice.queue == 'done' && slice.quantity > 0))
          .length;
      KdsFileLogger.info(
          '[BOOT] bootstrap 成功 seq=${value.eventSeq} queues=${value.queueCounts} 明细行=${value.lines.length}（含已完成 $doneInBoot 行）');
      // 已完成菜品持久化：bootstrap 只权威覆盖活动队列行，
      // 已完成行（live 完成行 / removed 保留行 / 快照历史行）合并保留，
      // 避免 config_changed/重连/命令冲突重建把已完成页清空
      // （快照接口只返回 completed 订单，live 完成行无法从快照恢复）。
      final retainedDone = state.lines
          .where((line) => !_hasActiveSlices(line))
          .toList(growable: false);
      if (retainedDone.isEmpty) {
        _emit(bootState);
      } else {
        final merged = {
          for (final line in bootState.lines) line.detailId: line
        };
        for (final line in retainedDone) {
          final existing = merged[line.detailId];
          if (existing == null) {
            merged[line.detailId] = line;
          } else if (_asInt(existing.raw['completed_at_ms']) <= 0 &&
              _asInt(line.raw['completed_at_ms']) > 0) {
            // 已完成行耗时固定：bootstrap 行可能缺 completed_at_ms
            //（非必需字段），用本地保留行的完成时间补上，避免重连后
            // 已完成耗时回退/丢失（耗时基于时间戳差值，不随时间累加）。
            merged[line.detailId] = existing.withRawFields(
                {'completed_at_ms': _asInt(line.raw['completed_at_ms'])});
          }
        }
        _emit(bootState.copyWith(lines: List.unmodifiable(merged.values)));
      }
      _recordDishLoad(KdsDishLoadTrace(
        source: KdsDishLoadSource.bootstrapHttp,
        eventSeq: value.eventSeq,
        lineCount: state.lines.length,
        eventType: 'bootstrap',
        channel: _channelLabel?.call(),
      ));
      onBootstrapApplied?.call();
    } catch (error) {
      KdsFileLogger.error('[BOOT] bootstrap 失败: $error');
      if (generation == _bootstrapGeneration) {
        _emit(state.copyWith(loading: false, error: '$error'));
      }
      rethrow;
    }
  }

  Future<void> startWithBufferedEvents(
      Iterable<KdsV2Envelope> bufferedEvents) async {
    await start();
    final pending = bufferedEvents
        .where((event) => event.eventSeq > state.eventSeq)
        .toList()
      ..sort((left, right) => left.eventSeq.compareTo(right.eventSeq));
    for (final event in pending) {
      await ingest(event, source: KdsDishLoadSource.websocketBuffered);
    }
  }

  /// 用本地缓存的最后已知快照作为初始展示（收银端不可达时的离线兜底）。
  /// event_seq 归零、config 版本下限重置：任何后续成功 bootstrap 都必须
  /// 作为权威数据覆盖缓存，避免缓存 seq 高于收银端导致引导被跳过。
  void restoreSnapshot(KdsV2State snapshot) {
    _bootstrapGeneration++;
    _configVersionFloor = -1;
    // 缓存仅用于离线展示；event_seq 归零、config 版本清空，
    // 保证后续任意成功 bootstrap 都能作为权威数据覆盖。
    _emit(snapshot.copyWith(
      eventSeq: 0,
      configVersion: null,
      connected: state.connected,
      loading: false,
      clearError: true,
    ));
    _recordDishLoad(KdsDishLoadTrace(
      source: KdsDishLoadSource.localCache,
      eventSeq: 0,
      lineCount: state.lines.length,
      eventType: 'snapshot_restore',
      channel: 'local',
    ));
  }

  void setConnected(bool value) =>
      _emit(state.copyWith(connected: value && !state.isStale));

  /// WebSocket dish_flags_changed 局部无感更新：
  /// 原地更新对应明细行的 hold_flag / held / order_rece，不引起全量重拉或大屏闪烁。
  void updateDishFlags({required int detailId, required int holdFlag}) {
    if (detailId <= 0) return;
    final isHeld = holdFlag == 1;
    final updated = [
      for (final line in state.lines)
        if (line.detailId == detailId)
          line.withRawFields({
            'held': isHeld,
            'hold_flag': holdFlag,
            'order_rece': isHeld ? 'mis_order' : 'rec_order',
          })
        else
          line,
    ];
    _emit(state.copyWith(lines: List.unmodifiable(updated)));
  }

  /// Merge the complete cashier business-day snapshot into the done queue.
  /// Live bootstrap/changes remain authoritative for active workflow queues.
  void mergeBusinessDayOrders(Map<String, dynamic> payload) {
    final body = payload['data'] is Map
        ? Map<String, dynamic>.from(payload['data'] as Map)
        : payload;
    final rawOrders = body['orders'];
    if (rawOrders is! List) return;
    var skippedNoMarker = 0;
    var skippedWindow = 0;
    var skippedDetail = 0;
    var mergedCount = 0;
    final merged = {for (final line in state.lines) line.detailId: line};
    for (final rawOrder in rawOrders.whereType<Map>()) {
      final order = Map<String, dynamic>.from(rawOrder);
      final completed = order['completed'] == true || order['completed'] == 1;
      // 营业日内已完成菜品初始化（方案A）：已结账订单照常合并；
      // 未结账订单带 done 标记（订单级或明细级，即划菜完成但未结账）
      // 也合并，使重启/换设备后能从服务端拉回当天已完成菜品。
      if (!completed && !_hasDoneMarker(order)) {
        skippedNoMarker++;
        continue;
      }
      final startMs = _asInt(body['business_day_start_ms']);
      final endMs = _asInt(body['business_day_end_ms']);
      final createdMs = _asInt(order['created_at_ms']);
      // created_at_ms 缺失（0）时不参与窗口过滤：不能把缺时间的订单
      // 误判为早于营业时段起点而跳过（否则已完成页整页丢失明细）。
      if (startMs > 0 && createdMs > 0 && createdMs < startMs) {
        skippedWindow++;
        continue;
      }
      if (endMs > 0 && createdMs > 0 && createdMs >= endMs) {
        skippedWindow++;
        continue;
      }
      final orderId = _asInt(order['order_id'] ?? order['orderId']);
      final details = order['details'];
      if (orderId <= 0 || details is! List) {
        skippedDetail++;
        continue;
      }
      for (final rawDetail in details.whereType<Map>()) {
        final detail = Map<String, dynamic>.from(rawDetail);
        // 未结账订单只合并已划菜完成的明细（done 标记），活动明细由
        // bootstrap/changes 实时提供，避免整单误标已完成。
        if (!completed && _queueOf(detail) != 'done') continue;
        final detailId = _asInt(detail['detail_id'] ?? detail['detailId']);
        final dishId = _asInt(detail['dish_id'] ?? detail['dishId']);
        final quantity = _asInt(detail['quantity']);
        final refunded =
            _asInt(detail['refunded_quantity'] ?? detail['refundedQuantity']);
        if (detailId <= 0 || dishId <= 0 || quantity <= refunded) {
          skippedDetail++;
          continue;
        }
        final existing = merged[detailId];
        if (existing != null && existing.raw['business_day_history'] != true) {
          continue;
        }
        try {
          final line = KdsV2Line.fromLegacyJson({
            'detail_id': detailId,
            'business_day_history': true,
            'order_id': orderId,
            if (_asInt(order['cloud_order_id'] ?? order['cloudOrderId']) > 0)
              'cloud_order_id':
                  _asInt(order['cloud_order_id'] ?? order['cloudOrderId']),
            'dish_id': dishId,
            'dish_name': '${detail['dish_name'] ?? detail['dishName'] ?? ''}',
            'quantity': quantity - refunded,
            'workflow_queue': 'done',
            'fulfillment_type': order['fulfillment_type'] ?? 'dine_in',
            'fulfillment_channel': order['fulfillment_type'] ?? 'dine_in',
            'order_no': '${order['order_no'] ?? ''}',
            'table_number': '${order['table_number'] ?? ''}',
            'specification': '${detail['specification'] ?? ''}',
            'unit': '${detail['unit'] ?? '份'}',
            'remark': '${detail['remark'] ?? order['remark'] ?? ''}',
            'local_revision': 1,
            'order_revision': 1,
            'created_at_ms': _asInt(order['created_at_ms']),
            'refunded_quantity': 0,
            'completed_at_ms': _completedAtMsOf(order),
          });
          merged[detailId] = line;
          mergedCount++;
        } on FormatException {
          // Ignore malformed historical rows; live state remains usable.
        }
      }
    }
    _emit(state.copyWith(lines: merged.values.toList(growable: false)));
    // 已完成页诊断：合并统计，定位"已完成不显示明细"的根因
    final doneLines = merged.values
        .where((line) => line.slices
            .any((slice) => slice.queue == 'done' && slice.quantity > 0))
        .length;
    KdsFileLogger.info(
        '[SNAP] 快照合并完成: 订单=${rawOrders.length} 新增明细=$mergedCount 跳过(无完成标记)=$skippedNoMarker 跳过(窗口外)=$skippedWindow 跳过(明细无效)=$skippedDetail 当前已完成行=$doneLines');
  }

  /// 订单是否带 done 标记（订单级 workflow_queue/queue/status，
  /// 或至少一个明细带 done 标记）：划菜完成但未结账的订单。
  static bool _hasDoneMarker(Map<String, dynamic> order) {
    final orderQueue =
        order['workflow_queue'] ?? order['queue'] ?? order['status'];
    if (orderQueue == 'done') return true;
    final details = order['details'];
    if (details is List) {
      return details
          .whereType<Map<String, dynamic>>()
          .any((detail) => _queueOf(detail) == 'done');
    }
    return false;
  }

  /// 明细的队列/状态字段（收银端可能用 workflow_queue/workflowQueue/queue/status
  /// 表达 done；本地收银端 LAN API 与云端 detail 一致使用驼峰 workflowQueue）。
  static String? _queueOf(Map<String, dynamic> detail) {
    final queue = detail['workflow_queue'] ??
        detail['workflowQueue'] ??
        detail['queue'] ??
        detail['status'];
    return queue is String ? queue : null;
  }

  /// 分页拉取营业时段历史订单并合并进已完成队列。
  /// 接口按 after_id 游标分页；直到返回不足一页或没有更多为止，
  /// 避免 limit 上限导致超量完成订单在已完成页丢失。
  Future<void>? _historyRefresh;

  Future<void> refreshBusinessDayOrders({int pageSize = 200}) {
    return _historyRefresh ??= _refreshBusinessDayOrders(pageSize: pageSize)
        .whenComplete(() => _historyRefresh = null);
  }

  Future<void> _refreshBusinessDayOrders({required int pageSize}) async {
    final initialSeq = state.eventSeq;
    final initialGeneration = _bootstrapGeneration;
    final orders = <dynamic>[];
    Map<String, dynamic>? window;
    var afterId = 0;
    var pageIndex = 0;
    try {
      while (true) {
        final payload = await transport.businessDayOrders(
          afterId: afterId > 0 ? afterId : null,
          limit: pageSize,
        );
        final body = payload['data'] is Map
            ? Map<String, dynamic>.from(payload['data'] as Map)
            : payload;
        final rawOrders = body['orders'];
        if (rawOrders is! List) {
          throw const FormatException('Missing business-day orders');
        }
        if (window != null &&
            (window['business_day_start_ms'] != body['business_day_start_ms'] ||
                window['business_day_end_ms'] != body['business_day_end_ms'])) {
          throw const FormatException(
              'Business-day window changed during pagination');
        }
        window = body;
        orders.addAll(rawOrders);
        pageIndex++;
        KdsFileLogger.info(
            '[SNAP] 第 $pageIndex 页 orders=${rawOrders.length} complete=${body['complete']} after_id=${afterId > 0 ? afterId : '-'}');
        if (body['complete'] == true) break;
        if (rawOrders.isEmpty && body['complete'] != false) break;
        var maxId = 0;
        for (final rawOrder in rawOrders.whereType<Map>()) {
          final id = _asInt(rawOrder['order_id'] ?? rawOrder['orderId']);
          if (id > maxId) maxId = id;
        }
        final nextId = _asInt(body['next_after_id'] ?? maxId);
        if (nextId <= afterId) {
          throw const FormatException('Invalid business-day cursor');
        }
        afterId = nextId;
        if (body['complete'] != false && rawOrders.length < pageSize) break;
      }
    } catch (error) {
      KdsFileLogger.error('[SNAP] 营业时段快照拉取失败（第 $pageIndex 页）: $error');
      rethrow;
    }
    // A live change or bootstrap during the request makes this snapshot stale.
    if (state.eventSeq != initialSeq ||
        _bootstrapGeneration != initialGeneration) {
      KdsFileLogger.info('[SNAP] 快照已过期（事件/引导在拉取期间变化），丢弃不合并');
      return;
    }
    final start = _asInt(window['business_day_start_ms']);
    final end = _asInt(window['business_day_end_ms']);
    final windowChanged =
        start != _historyWindowStartMs || end != _historyWindowEndMs;
    KdsFileLogger.info(
        '[SNAP] 拉取完成: ${orders.length} 单，窗口 ${start == 0 ? '?' : start}-${end == 0 ? '?' : end}${windowChanged ? '（窗口变化，重建历史行）' : ''}');
    // 已完成菜品持久化：仅当营业时段窗口变化（换时段/新一天开市）时
    // 清除旧窗口历史行并重建；同一窗口内重复拉取快照时保留内存中的
    // 已完成行（含快照归档/缺页的订单），只增补快照中的订单。
    final beforeCount = state.lines.length;
    final beforeDone =
        state.lines.where((line) => !_hasActiveSlices(line)).length;
    final retained = state.lines.where((line) {
      final created = _asInt(line.raw['created_at_ms']);
      // 快照历史行与 live 完成行统一按「当天营业日」过滤（created >= 开市
      // start）。窗口变化只触发重新评估，不再无条件清除 history 行：
      // 否则重连（新 controller 窗口归零 → windowChanged=true）会把
      // 当天已完成行整批误删（本地快照恢复的当天 history 行同样受保护）。
      // 跨天清理语义保持：created < 新 start 的历史行仍被清除。
      if (line.raw['business_day_history'] == true && !windowChanged) {
        return true;
      }
      if (_hasActiveSlices(line)) return true;
      // 缺失 created 的行保守保留（无法判定归属，避免误删）。
      if (created <= 0) return true;
      return start <= 0 || created >= start;
    }).toList();
    final afterDone = retained.where((line) => !_hasActiveSlices(line)).length;
    KdsFileLogger.info(
        '[SNAP] 窗口清理: 行 $beforeCount→${retained.length}（已完成行 $beforeDone→$afterDone）窗口变化=$windowChanged');
    state = state.copyWith(lines: retained);
    _historyWindowStartMs = start;
    _historyWindowEndMs = end;
    mergeBusinessDayOrders({...window, 'orders': orders});
    _recordDishLoad(KdsDishLoadTrace(
      source: KdsDishLoadSource.businessDaySnapshot,
      eventSeq: state.eventSeq,
      lineCount: state.lines.length,
      eventType: 'business_day_snapshot',
      channel: _channelLabel?.call(),
    ));
  }

  /// 该明细是否仍有活动（未完成）切片：快照只允许覆盖完全完成的 detail，
  /// 绝不把仍在待配菜/待制作/待传菜的 live 行覆盖成已完成。
  static bool _hasActiveSlices(KdsV2Line line) =>
      line.slices.any((slice) => slice.queue != 'done' && slice.quantity > 0);

  /// 只使用真实完成时间；缺失时保留未知，不用下单或更新时间伪造。
  static int _completedAtMsOf(Map<String, dynamic> order) {
    for (final key in const [
      'completed_at_ms',
    ]) {
      final value = _asInt(order[key]);
      if (value > 0) return value;
    }
    return 0;
  }

  static int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  Future<void> reconnect() {
    final existing = _reconnectInFlight;
    if (existing != null) return existing;
    final operation = _reconnect();
    _reconnectInFlight = operation;
    return operation.whenComplete(() => _reconnectInFlight = null);
  }

  Future<void> _reconnect() async {
    _emit(state.copyWith(
      connected: true,
      loading: true,
      clearError: true,
    ));
    try {
      while (true) {
        final afterSeq = state.eventSeq;
        final result = await transport.changes(afterSeq);
        if (result.snapshotRequired || result.eventSeq < afterSeq) {
          await start(force: true);
          break;
        }
        if (result.eventSeq == afterSeq) {
          if (result.events.isNotEmpty) {
            await start(force: true);
            break;
          }
          break;
        }
        final ordered = [...result.events]
          ..sort((a, b) => a.eventSeq.compareTo(b.eventSeq));
        var expectedSeq = afterSeq + 1;
        var validPage = ordered.isNotEmpty;
        for (final event in ordered) {
          if (event.eventSeq != expectedSeq ||
              event.eventSeq > result.eventSeq) {
            validPage = false;
            break;
          }
          expectedSeq++;
        }
        if (!validPage) {
          await start(force: true);
          break;
        }
        for (final event in ordered) {
          await ingest(event, source: KdsDishLoadSource.changesReconnect);
        }
        if (state.eventSeq <= afterSeq) {
          await start(force: true);
          break;
        }
        if (state.eventSeq == result.eventSeq) break;
      }
      _emit(state.copyWith(
        connected: true,
        loading: false,
        clearError: true,
      ));
    } catch (error) {
      _emit(state.copyWith(connected: true, loading: false, error: '$error'));
      rethrow;
    }
  }

  void rejectProtocol(Object error) {
    _emit(state.copyWith(loading: false, error: '$error'));
  }

  /// 兜底轮询：WS 推送静默失效（连接正常但收不到业务事件）时，
  /// 通过 /kds/v2/changes 增量补偿跟上收银端。
  /// 不改变 connected/loading；无变更时不产生任何状态发射；
  /// 失败静默保留当前内存画面，等待下一轮轮询、WS 事件或断线重连。
  Future<void> poll() async {
    if (_reconnectInFlight != null || _recovery != null) return;
    try {
      await _catchUpFrom(
        state.eventSeq,
        source: KdsDishLoadSource.changesPoll,
      );
    } catch (_) {
      // 静默失败：保留当前画面，下轮再试。
    }
  }

  Future<void> ingest(
    KdsV2Envelope event, {
    KdsDishLoadSource source = KdsDishLoadSource.unknown,
    String? channel,
  }) async {
    if (expectedShopId != null && event.shopId != expectedShopId) {
      throw const FormatException('KDS v2 event shop_id mismatch');
    }
    if (event.eventId.isNotEmpty && _seenEventIds.contains(event.eventId)) {
      return;
    }
    if (event.eventSeq <= state.eventSeq) {
      _remember(event.eventId);
      return;
    }
    if (_requiresConfigBootstrap(event)) {
      final existing = _recovery;
      if (existing != null) {
        await existing;
        if (event.eventSeq > state.eventSeq) {
          await ingest(event, source: source, channel: channel);
        }
        return;
      }
      await (_recovery =
          _refreshConfiguration(event).whenComplete(() => _recovery = null));
      return;
    }
    if (event.eventSeq != state.eventSeq + 1) {
      final existing = _recovery;
      if (existing != null) {
        await existing;
        if (event.eventSeq > state.eventSeq) {
          await ingest(event, source: source, channel: channel);
        }
        return;
      }
      await (_recovery = _recoverTo(event, source, channel)
          .whenComplete(() => _recovery = null));
      return;
    }
    _apply(event, source, channel);
  }

  bool _requiresConfigBootstrap(KdsV2Envelope event) {
    final incoming = event.configVersion;
    if (incoming == null) {
      // 无版本号的目录/配置变更广播同样必须触发 bootstrap 重载，
      // 否则新菜品等目录变化只能等手动刷新。
      return event.type == 'config_changed';
    }
    final current = state.configVersion ?? -1;
    final floor = current > _configVersionFloor ? current : _configVersionFloor;
    return incoming > floor;
  }

  Future<void> _refreshConfiguration(KdsV2Envelope trigger) async {
    await start();
    final requiredVersion = trigger.configVersion;
    if (requiredVersion == null) {
      // 无版本 config_changed：bootstrap 已重载目录/配置，直接确认。
      _remember(trigger.eventId);
      return;
    }
    final bootVersion = state.configVersion;
    if (bootVersion != null && bootVersion < requiredVersion) {
      final error = FormatException(
        'KDS v2 bootstrap config_version is older than $requiredVersion',
      );
      rejectProtocol(error);
      throw error;
    }
    // bootstrap 未回传 config_version 时也记录已对齐版本，
    // 避免后续同版本事件重复触发全量引导。
    if (requiredVersion > _configVersionFloor) {
      _configVersionFloor = requiredVersion;
    }
    _remember(trigger.eventId);
  }

  Future<void> _recoverTo(
      KdsV2Envelope trigger, KdsDishLoadSource source, String? channel) async {
    final result = await transport.changes(state.eventSeq);
    if (result.snapshotRequired) {
      await start();
      return;
    }
    final ordered = [...result.events]
      ..sort((a, b) => a.eventSeq.compareTo(b.eventSeq));
    for (final event in ordered) {
      if (event.eventSeq == state.eventSeq + 1) {
        _apply(event, KdsDishLoadSource.changesGapRecovery, channel);
      }
    }
    if (trigger.eventSeq == state.eventSeq + 1) {
      _apply(trigger, source, channel);
    } else if (state.eventSeq < trigger.eventSeq) {
      // An incomplete changes page is not authoritative; recover by snapshot.
      await start();
    }
  }

  void _apply(KdsV2Envelope event, KdsDishLoadSource source, String? channel) {
    _remember(event.eventId);
    _emit(KdsV2Reducer.applyEnvelope(state, event));
    final carriesDishData = event.patches.isNotEmpty ||
        const {'order_created', 'order_accepted', 'order_updated'}
            .contains(event.type);
    if (carriesDishData) {
      _recordDishLoad(KdsDishLoadTrace(
        source: source,
        eventSeq: event.eventSeq,
        eventId: event.eventId,
        eventType: event.type,
        patchCount: event.patches.length,
        lineCount: state.lines.length,
        channel: channel ?? _channelLabel?.call(),
      ));
    }
    _onEnvelopeApplied?.call(event);
  }

  void _recordDishLoad(KdsDishLoadTrace trace) {
    KdsFileLogger.info(
      '[DISH_SOURCE] source=${trace.source.code} transport=${trace.source.transport} '
      'channel=${trace.channel ?? 'unknown'} seq=${trace.eventSeq} '
      'event_id=${trace.eventId ?? '-'} type=${trace.eventType ?? '-'} '
      'patches=${trace.patchCount} lines_after=${trace.lineCount}',
    );
    try {
      _onDishLoad?.call(trace);
    } catch (error) {
      // 诊断观察者不得影响权威事件应用与界面刷新。
      KdsFileLogger.warn('[DISH_SOURCE] observer_failed: $error');
    }
  }

  void _remember(String eventId) {
    if (eventId.isEmpty) return;
    _seenEventIds.add(eventId);
    while (_seenEventIds.length > 512) {
      _seenEventIds.remove(_seenEventIds.first);
    }
  }

  Future<KdsV2CommandResult> command(KdsV2Command value) {
    // 离线划菜由 board provider 的 outbox 接管；controller 只有在连接
    // 恢复后才允许真正发 HTTP，避免绕过队列造成假成功。
    if (!state.canMutate || !state.connected) {
      throw StateError('KDS is disconnected/read-only');
    }
    final fingerprint = _commandFingerprint(value);
    final existing = _commandsInFlight[fingerprint];
    if (existing != null) return existing;
    final operation = _executeCommand(value, fingerprint);
    _commandsInFlight[fingerprint] = operation;
    return operation.whenComplete(() => _commandsInFlight.remove(fingerprint));
  }

  Future<KdsV2CommandResult> _executeCommand(
      KdsV2Command value, String fingerprint) async {
    final commandId = _ambiguousCommandIds[fingerprint] ?? value.commandId;
    final effective = value.withCommandId(commandId);
    try {
      final result = await transport.command(effective);
      if (result.commandId != effective.commandId) {
        throw FormatException(
          'KDS v2 command acknowledgement id mismatch: ${result.commandId}',
        );
      }
      await ingest(
          result.asEnvelope(
            shopId: expectedShopId,
            occurredAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
          source: KdsDishLoadSource.commandResponse);
      _ambiguousCommandIds.remove(fingerprint);
      return result;
    } on FormatException catch (error) {
      _ambiguousCommandIds.remove(fingerprint);
      rejectProtocol(error);
      rethrow;
    } on ApiException catch (error) {
      if (error.statusCode == 409 || error.code == 4090) {
        _ambiguousCommandIds.remove(fingerprint);
        await _refreshAfterConflict();
      } else if (_isAmbiguousCommandFailure(error)) {
        _ambiguousCommandIds[fingerprint] = commandId;
      } else {
        _ambiguousCommandIds.remove(fingerprint);
      }
      rethrow;
    } catch (error) {
      if (_isAmbiguousCommandFailure(error)) {
        _ambiguousCommandIds[fingerprint] = commandId;
      } else {
        _ambiguousCommandIds.remove(fingerprint);
      }
      rethrow;
    }
  }

  Future<void> _refreshAfterConflict() async {
    _emit(state.copyWith(loading: true, clearError: true));
    try {
      await _catchUpFrom(
        state.eventSeq,
        source: KdsDishLoadSource.changesConflictRecovery,
      );
      _emit(state.copyWith(loading: false, clearError: true));
    } catch (error) {
      _emit(state.copyWith(loading: false, error: '$error'));
      rethrow;
    }
  }

  Future<void> _catchUpFrom(
    int afterSeq, {
    required KdsDishLoadSource source,
  }) async {
    final result = await transport.changes(afterSeq);
    if (result.snapshotRequired) {
      await start();
      return;
    }
    final ordered = [...result.events]
      ..sort((left, right) => left.eventSeq.compareTo(right.eventSeq));
    for (final event in ordered) {
      await ingest(event, source: source);
    }
    if (state.eventSeq < result.eventSeq) await start();
  }

  String _commandFingerprint(KdsV2Command command) {
    final json = command.toJson()..remove('command_id');
    return jsonEncode(_canonicalJson(json));
  }

  Object? _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return {for (final key in keys) key: _canonicalJson(value[key])};
    }
    if (value is List) return value.map(_canonicalJson).toList();
    return value;
  }

  bool _isAmbiguousCommandFailure(Object error) =>
      error is KdsCommandAcceptedOffline ||
      error is TimeoutException ||
      (error is ApiException &&
          (error.isNetworkError || error.isTransientServiceFailure));
}
