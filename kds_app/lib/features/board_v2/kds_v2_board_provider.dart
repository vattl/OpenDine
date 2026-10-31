import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/api/kds_api_client.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/lan_v2/kds_dual_mode_transport.dart';
import 'package:kds_app/core/lan_v2/kds_keyed_command_scheduler.dart';
import 'package:kds_app/core/lan_v2/kds_v2_client.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/core/storage/app_prefs.dart';
import 'package:kds_app/core/storage/kds_board_snapshot_store.dart';
import 'package:kds_app/core/storage/kds_command_outbox_store.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/core/ws/kds_websocket.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_logic.dart';
import 'package:kds_app/features/board_v2/kds_undo_toast.dart';
import 'package:uuid/uuid.dart';

String? kdsV2ConnectionBindingKey(
  String apiBase,
  String? token,
  KdsWebSocketService? webSocket,
  int connectionGeneration, {
  String cloudApiBase = '',
}) {
  if (apiBase.isEmpty || token == null || token.isEmpty || webSocket == null) {
    return null;
  }
  return '$apiBase|$cloudApiBase|$token|$connectionGeneration|${identityHashCode(webSocket)}';
}

@visibleForTesting
String kdsAggregateKeyForCommand(
  KdsV2Command command,
  Iterable<KdsV2Line> lines,
) {
  final explicitOrderId = command.target.orderId;
  if (explicitOrderId != null && explicitOrderId > 0) {
    return 'order:$explicitOrderId';
  }
  final detailIds = <int>{
    if (command.target.detailId case final id? when id > 0) id,
    ...command.target.detailIds.where((id) => id > 0),
  };
  final orderIds = lines
      .where(
        (line) =>
            detailIds.contains(line.detailId) ||
            (line.cloudDetailId != null &&
                detailIds.contains(line.cloudDetailId)),
      )
      .map((line) => line.orderId)
      .where((id) => id > 0)
      .toSet();
  if (orderIds.length == 1) return 'order:${orderIds.single}';
  if (orderIds.length > 1) {
    final sorted = orderIds.toList()..sort();
    return 'orders:${sorted.join(",")}';
  }
  if (detailIds.isNotEmpty) {
    final sorted = detailIds.toList()..sort();
    return 'details:${sorted.join(",")}';
  }
  return 'cmd:${command.commandId}';
}

final kdsV2BoardProvider =
    NotifierProvider<KdsV2BoardNotifier, KdsV2State>(KdsV2BoardNotifier.new);

typedef _PendingSyncCommand = KdsOutboxRecord;

class KdsV2BoardNotifier extends Notifier<KdsV2State> {
  /// 兜底轮询间隔：WS 推送静默失效时，最长 15s 内通过 changes 补偿跟上。
  static const _fallbackPollInterval = Duration(seconds: 15);

  KdsV2Controller? _controller;
  KdsDualModeTransport? _transport;
  StreamSubscription? _eventSub;
  StreamSubscription<bool>? _connectedSub;
  Timer? _pollTimer;
  String? _sessionKey;
  int? _lastEventAtMs;

  /// 最近一次拉取营业时段快照的本地日期（YYYYMMDD，0 表示未拉取）。
  /// 用于日切检测：跨天后在兜底轮询中自动重拉快照。
  int _snapshotMinute = 0;
  final Map<String, int> _optimisticAdvanceCounts = {};
  final Map<String, DateTime> _countDriftLoggedAt = {};
  final List<_PendingSyncCommand> _outboxQueue = [];
  final List<KdsV2OptimisticOverlay> _overlays = [];
  bool _allChannelsUnavailable = false;
  late final KdsKeyedCommandScheduler _scheduler = KdsKeyedCommandScheduler(
    executor: _executeScheduledCommand,
    aggregateKeyExtractor: (record) => _aggregateKeyForCommand(record.command),
    initialConcurrency: 4,
    maxConcurrency: 8,
    minConcurrency: 1,
    onMetricsUpdated: (metrics) {
      if (_controller case final c?) {
        state = _visibleState(c.state);
      }
    },
  );

  /// 连接探活只发布建议，不直接切换。页面监听该值并由用户确认。
  final ValueNotifier<KdsChannelSwitchSuggestion?> channelSwitchSuggestion =
      ValueNotifier(null);

  /// 划菜成功后的可撤回记录（顶部撤回提示条数据源）。
  /// 仅「待传菜划到已完成」的划菜会提示，且只保留最近一次（新划菜直接替换
  /// 旧的，不支持合并/全部撤回）。页面通过 ValueListenableBuilder 监听。
  final ValueNotifier<KdsAdvanceUndoBatch?> undoBatch = ValueNotifier(null);

  /// 后厨退菜声光强提醒数据源。
  final ValueNotifier<List<KdsRefundAlertItem>> refundAlerts =
      ValueNotifier(const []);

  void dismissRefundAlert(String id) {
    refundAlerts.value =
        refundAlerts.value.where((item) => item.id != id).toList();
  }

  void clearRefundAlerts() {
    refundAlerts.value = const [];
  }
  KdsBoardSnapshotStore? _snapshotStore;
  KdsCommandOutboxStore? _outboxStore;
  Timer? _snapshotSaveTimer;

  @override
  KdsV2State build() {
    ref.onDispose(_dispose);
    ref.listen<SessionState>(sessionProvider, (_, next) {
      _handleSessionChange(next);
    });
    _handleSessionChange(ref.read(sessionProvider));
    return stateOrEmpty;
  }

  void _handleSessionChange(SessionState session) {
    final webSocket = ref.read(sessionProvider.notifier).webSocket;
    final key = session.isLoggedIn
        ? kdsV2ConnectionBindingKey(
            session.apiBase,
            session.token,
            webSocket,
            session.connectionGeneration,
            cloudApiBase: session.cloudApiBase,
          )
        : null;
    if (key == null) {
      Future.microtask(_detach);
    } else if (key != _sessionKey) {
      Future.microtask(() => _attach(key));
    } else if (_transport != null &&
        _transport!.mode != session.connectionMode) {
      _transport!.updateMode(session.connectionMode);
    }
  }

  KdsV2State get stateOrEmpty => _controller == null
      ? const KdsV2State()
      : _visibleState(_controller!.state);

  Future<void> _enqueueOutbox(KdsOutboxRecord record) async {
    final store = _outboxStore;
    if (store == null) return;
    final shopId = ref.read(sessionProvider).device?.shopId;
    if (shopId != null) {
      await store.enqueue(record, shopId: shopId);
    }
  }

  Future<void> _updateOutbox(KdsOutboxRecord record) async {
    final store = _outboxStore;
    if (store == null) return;
    final shopId = ref.read(sessionProvider).device?.shopId;
    if (shopId != null) {
      await store.updateStatus(record, shopId: shopId);
    }
  }

  Future<void> _removeOutbox(String commandId) async {
    final store = _outboxStore;
    if (store == null) return;
    final shopId = ref.read(sessionProvider).device?.shopId;
    if (shopId != null) {
      await store.remove(commandId, shopId: shopId);
    }
  }

  Future<void> _clearOutbox() async {
    final store = _outboxStore;
    if (store == null) return;
    final shopId = ref.read(sessionProvider).device?.shopId;
    await store.clear(shopId: shopId);
  }

  KdsV2State _visibleState(KdsV2State source) => source.copyWith(
        lines: applyOverlaysToLines(source.lines, _overlays),
        overlays: List.unmodifiable(_overlays),
        optimisticHiddenSlices: Set.unmodifiable(_optimisticAdvanceCounts.keys),
        lastEventAtMs: _lastEventAtMs,
        pendingSyncCount: _scheduler.pendingCount,
        allChannelsUnavailable: _allChannelsUnavailable,
      );

  Future<void> _attach(String key) async {
    if (_sessionKey == key) return;
    final sessionState = ref.read(sessionProvider);
    final sessionNotifier = ref.read(sessionProvider.notifier);
    final ws = sessionNotifier.webSocket;
    if (ws == null) return;

    if (_controller != null && _transport != null) {
      // 仅连接代际或通道发生切换，平滑复用已有 Controller，避免闪烁与状态丢失
      final controller = _controller!;
      _sessionKey = key;
      _wireWebSocket(
        ws,
        controller,
        key,
        boundChannel: sessionState.activeChannel,
      );
      unawaited(controller.reconnect().catchError((error) {
        KdsFileLogger.warn('[CONTROLLER] 平滑重连失败，回退全量 start: $error');
        return controller.start(force: true);
      }).whenComplete(() {
        if (identical(_controller, controller) && _sessionKey == key) {
          unawaited(_flushOutbox(controller, key));
        }
      }));
      return;
    }

    _detach();
    _sessionKey = key;

    final lanClient = KdsV2Client(KdsV2HttpAdapter(KdsApiClient(
      getBaseUrl: () => ref.read(sessionProvider).apiBase,
      getToken: () => ref.read(sessionProvider).token,
      onUnauthorized: () {
        final mode = ref.read(sessionProvider).connectionMode;
        if (mode == KdsConnectionMode.lanOnly ||
            mode == KdsConnectionMode.lanFirst ||
            mode == KdsConnectionMode.cloudFirst) {
          sessionNotifier.logout();
        }
      },
    )));

    KdsV2Client? cloudClient;
    if (sessionState.cloudApiBase.trim().isNotEmpty) {
      cloudClient = KdsV2Client(KdsV2HttpAdapter(KdsApiClient(
        getBaseUrl: () => ref.read(sessionProvider).cloudApiBase,
        getToken: () => ref.read(sessionProvider).token,
        onUnauthorized: () {
          // 统一 token 模式：任一通道 401 都表示云端签发的凭据已失效。
          final mode = ref.read(sessionProvider).connectionMode;
          if (mode == KdsConnectionMode.cloudDirect) {
            sessionNotifier.logout();
          } else {
            KdsFileLogger.warn(
                '[DUAL_MODE] 云端 401: 收银端 token 可能尚未同步到云端，将回退至登录');
            sessionNotifier.logout();
          }
        },
      )));
    }

    late final KdsV2Controller controller;
    late final KdsDualModeTransport transport;
    transport = KdsDualModeTransport(
      lanTransport: lanClient,
      cloudTransport: cloudClient,
      mode: sessionState.connectionMode,
      initialChannel: sessionState.activeChannel,
      expectedShopId: sessionState.device?.shopId,
      onChannelSwitched: (newChannel) {
        channelSwitchSuggestion.value = null;
        sessionNotifier.switchActiveChannel(newChannel);
        _scheduler.pause();
        _scheduler.bumpGeneration();
        // LAN 代理和云端共享同一云端权威事件流。切换后仍需 bootstrap
        // 重建权威快照与游标；controller 成功应用后再释放切换写屏障。
        unawaited(controller.start(force: true).then((_) {
          transport.completeHandover();
          _scheduler.resume();
          KdsFileLogger.info(
              '[DUAL_MODE] 新通道 controller start 成功，释放切换写屏障并恢复调度');
        }).catchError((error) {
          KdsFileLogger.warn('[DUAL_MODE] 新通道 bootstrap 未完成，继续保持写屏障: $error');
          transport.reportActiveChannelUnavailable(error);
        }));
      },
      onChannelStateChanged: (channelState) {
        _allChannelsUnavailable = channelState == KdsChannelState.unavailable;
        if (_controller case final activeController?) {
          if (_allChannelsUnavailable) {
            _scheduler.pause();
            activeController.setConnected(false);
          } else {
            _scheduler.resume();
            activeController.setConnected(true);
          }
          state = _visibleState(activeController.state);
        }
      },
      onChannelSwitchSuggested: (suggestion) {
        channelSwitchSuggestion.value = suggestion;
      },
    );
    _transport = transport;

    controller = KdsV2Controller(
      transport,
      expectedShopId: sessionState.device?.shopId,
      channelLabel: () => transport.activeChannel.value,
      onState: (next) {
        // Controller is deliberately reused when LAN/cloud channels switch.
        // The session binding key changes with the WebSocket generation, so
        // checking the original key here would suppress every post-failover
        // state update even though this is still the active controller.
        if (identical(_controller, controller)) {
          _logQueueCountDrift(next);
          state = _visibleState(next);
          if (next.lines.isNotEmpty) _scheduleSnapshotSave(controller);
        }
      },
      onEnvelopeApplied: (event) {
        if (event.commandId != null && event.commandId!.isNotEmpty) {
          _removeOverlayAndOutbox(event.commandId!);
        }
        // 收银端本地下单使用 order_created；云端订单投影确认使用
        // order_accepted。两者都代表新订单首次进入 KDS，统一触发提示音。
        if (const {'order_created', 'order_accepted'}.contains(event.type) &&
            identical(_controller, controller)) {
          final currentKey = _sessionKey;
          if (currentKey != null) {
            unawaited(_handleNewOrder(controller, currentKey));
          }
        }

        // 催菜事件声效反馈
        final anyRushed = event.patches.any((p) =>
            p.line?.raw['rushed'] == true ||
            p.line?.raw['order_rushed'] == true);
        if (anyRushed && identical(_controller, controller)) {
          unawaited(SystemSound.play(SystemSoundType.alert).catchError((_) {}));
          HapticFeedback.mediumImpact();
        }

        // 退菜强提醒：当有明细被标记为 refunded 或活动明细被 removed 时，触发强报警
        if (identical(_controller, controller)) {
          for (final patch in event.patches) {
            final isRefundedStatus =
                patch.line?.raw['line_status'] == 'refunded' ||
                    patch.line?.raw['status'] == 'refunded';
            if (patch.removed || isRefundedStatus) {
              final prevLine = state.lines
                  .where((line) => line.detailId == patch.detailId)
                  .firstOrNull;
              if (prevLine != null &&
                  prevLine.slices.any((s) => s.queue != 'done' && s.quantity > 0)) {
                final raw = prevLine.raw;
                final tableNum = raw['table_number']?.toString().trim();
                final pickupCode = raw['pickup_code']?.toString().trim();
                final tableOrCode = (tableNum != null && tableNum.isNotEmpty)
                    ? '$tableNum号桌'
                    : (pickupCode != null && pickupCode.isNotEmpty
                        ? '取餐码 $pickupCode'
                        : '');
                final alertItem = KdsRefundAlertItem(
                  id: '${patch.detailId}_${DateTime.now().millisecondsSinceEpoch}',
                  tableOrPickupCode: tableOrCode,
                  dishName: prevLine.dishName,
                  quantity: prevLine.quantity,
                  unit: raw['unit']?.toString() ?? '份',
                  occurredAt: DateTime.now(),
                );
                refundAlerts.value = [alertItem, ...refundAlerts.value];
                unawaited(
                    SystemSound.play(SystemSoundType.alert).catchError((_) {}));
                HapticFeedback.heavyImpact();
              }
            }
          }
        }
      },
      onBootstrapApplied: () {
        // controller 内部触发的 bootstrap（config_changed/重连/命令冲突/
        // 轮询落后）会重建活动队列；立即补拉营业时段快照，
        // 避免已完成页在分钟级轮询前出现空窗。start() 已合并保留
        // 内存中的已完成行，这里只做增补刷新。
        if (identical(_controller, controller)) {
          unawaited(controller.refreshBusinessDayOrders().catchError((error) {
            KdsFileLogger.warn('[SNAP] 内部 bootstrap 后补拉快照失败: $error');
          }));
        }
      },
    );
    _controller = controller;
    controller.setConnected(false);
    final sharedPrefs = await SharedPreferences.getInstance();
    _snapshotStore ??= KdsBoardSnapshotStore(sharedPrefs);
    _outboxStore ??= await KdsCommandOutboxStore.open(
      legacyPrefs: sharedPrefs,
    );
    final shopId = ref.read(sessionProvider).device?.shopId;
    final cached = _snapshotStore?.load(expectedShopId: shopId);
    if (cached != null) controller.restoreSnapshot(cached);
    if (_outboxQueue.isEmpty) {
      final restoredOutbox =
          await _outboxStore?.load(expectedShopId: shopId) ?? const [];
      if (restoredOutbox.isNotEmpty) {
        _outboxQueue.addAll(restoredOutbox);
        _scheduler.clear();
        _overlays.clear();
        for (final item in restoredOutbox) {
          final aggKey = _aggregateKeyForCommand(item.command);
          final overlay = KdsV2OptimisticOverlay.fromOutboxRecord(
            item,
            aggregateKey: aggKey,
          );
          _overlays.add(overlay);
          for (final hKey in item.hiddenKeys) {
            _optimisticAdvanceCounts.update(hKey, (count) => count + 1,
                ifAbsent: () => 1);
          }
        }
        _scheduler.restore(restoredOutbox);
      }
    }
    var starting = true;
    final pendingEvents = ws.drainBufferedEvents();
    _wireWebSocket(
      ws,
      controller,
      key,
      boundChannel: sessionState.activeChannel,
      isStarting: () => starting,
      pendingEvents: pendingEvents,
    );
    try {
      await controller.start();
      // 已完成页使用收银端营业时段完整快照（分页拉全），
      // 避免历史完成订单因归档/事件保留期丢失，也避免 limit 截断超量订单。
      try {
        await controller.refreshBusinessDayOrders();
        _snapshotMinute = _minuteStamp();
      } catch (error) {
        // 实时看板可独立工作；快照接口失败时保留 bootstrap/changes 数据。
        // 记录失败原因：已完成页不显示明细时先看这里。
        KdsFileLogger.warn('[SNAP] 营业时段快照拉取失败（已完成页可能为空，活动队列不受影响）: $error');
      }
      // bootstrap 合并已完成行 + 快照增补完成后才落盘，避免把
      // "已完成行被 bootstrap 清空"的中间状态写入本地快照（污染持久化）。
      unawaited(_flushSnapshotSave(controller));
      while (pendingEvents.isNotEmpty) {
        final batch = List.of(pendingEvents);
        pendingEvents.clear();
        for (final event in batch) {
          _lastEventAtMs = DateTime.now().millisecondsSinceEpoch;
          if (event.type == 'dish_flags_changed') {
            final payload = event.payload ?? event.raw;
            final rawDetailId = payload['detail_id'] ?? payload['detailId'];
            final detailId = rawDetailId is num
                ? rawDetailId.toInt()
                : int.tryParse('$rawDetailId') ?? 0;
            final rawHoldFlag = payload['hold_flag'] ?? payload['holdFlag'];
            final holdFlag = rawHoldFlag is num
                ? rawHoldFlag.toInt()
                : int.tryParse('$rawHoldFlag') ?? 0;
            if (detailId > 0) {
              controller.updateDishFlags(detailId: detailId, holdFlag: holdFlag);
              continue;
            }
          }
          try {
            await controller.ingest(
              KdsV2Envelope.fromJson(event.raw),
              source: KdsDishLoadSource.websocketBuffered,
              channel: sessionState.activeChannel.value,
            );
          } on FormatException catch (error) {
            // One malformed buffered event must not block all later events
            // collected while the initial snapshot was loading.
            controller.rejectProtocol(error);
          }
        }
      }
    } catch (_) {
      // Controller exposes the error while keeping any in-memory snapshot.
    } finally {
      starting = false;
    }
    if (_sessionKey != key || !identical(_controller, controller)) return;
    if (!_allChannelsUnavailable) {
      _scheduler.resume();
      controller.setConnected(true);
    }
    _startFallbackPoll(controller, key);
    if (ws.isConnected) {
      controller.setConnected(true);
      try {
        await controller.reconnect();
      } catch (_) {
        // Reconnect remains locked and exposes its error in controller state.
      }
    }
    unawaited(_flushOutbox(controller, key));
  }

  void _wireWebSocket(
    KdsWebSocketService ws,
    KdsV2Controller controller,
    String key, {
    required KdsActiveChannel boundChannel,
    bool Function()? isStarting,
    List<KdsWsEvent>? pendingEvents,
  }) {
    _connectedSub?.cancel();
    _eventSub?.cancel();
    _connectedSub = ws.connectedStream.listen((connected) {
      if (!connected) {
        _transport?.reportRealtimeDisconnected(boundChannel);
        return;
      }
      controller.setConnected(true);
      _scheduler.resume();
      if (isStarting?.call() ?? false) return;
      unawaited(controller.reconnect().catchError((_) {}).whenComplete(() {
        if (identical(_controller, controller) && _sessionKey == key) {
          unawaited(_flushOutbox(controller, key));
          unawaited(controller.refreshBusinessDayOrders().catchError((error) {
            KdsFileLogger.warn('[SNAP] 重连后补拉快照失败: $error');
          }));
        }
      }));
    });
    if (ws.isConnected) {
      controller.setConnected(true);
      _scheduler.resume();
    }
    _eventSub = ws.eventStream.listen((event) async {
      if ((isStarting?.call() ?? false) && pendingEvents != null) {
        pendingEvents.add(event);
        return;
      }
      _lastEventAtMs = DateTime.now().millisecondsSinceEpoch;
      if (event.type == 'dish_flags_changed') {
        final payload = event.payload ?? event.raw;
        final rawDetailId = payload['detail_id'] ?? payload['detailId'];
        final detailId = rawDetailId is num
            ? rawDetailId.toInt()
            : int.tryParse('$rawDetailId') ?? 0;
        final rawHoldFlag = payload['hold_flag'] ?? payload['holdFlag'];
        final holdFlag = rawHoldFlag is num
            ? rawHoldFlag.toInt()
            : int.tryParse('$rawHoldFlag') ?? 0;
        if (detailId > 0) {
          controller.updateDishFlags(detailId: detailId, holdFlag: holdFlag);
          return;
        }
      }
      try {
        await controller.ingest(
          KdsV2Envelope.fromJson(event.raw),
          source: KdsDishLoadSource.websocketPush,
          channel: boundChannel.value,
        );
      } on FormatException catch (error) {
        controller.rejectProtocol(error);
      }
    });
  }

  Future<void> refresh() async {
    final controller = _controller;
    final key = _sessionKey;
    if (controller == null || key == null) return;
    await controller.start();
    try {
      await controller.refreshBusinessDayOrders();
      _snapshotMinute = _minuteStamp();
    } catch (error) {
      // 快照失败不阻塞手动刷新主链路，但记录原因便于定位已完成页问题。
      KdsFileLogger.warn('[SNAP] 手动刷新补拉快照失败: $error');
    }
    unawaited(_flushOutbox(controller, key));
  }

  Future<void> switchActiveChannel(KdsActiveChannel target) async {
    final transport = _transport;
    if (transport == null) {
      throw StateError('KDS 连接尚未就绪，无法切换通道');
    }
    await transport.requestChannelSwitch(target);
  }

  void dismissChannelSwitchSuggestion(KdsActiveChannel target) {
    _transport?.dismissChannelSwitchSuggestion(target);
    if (channelSwitchSuggestion.value?.targetChannel == target) {
      channelSwitchSuggestion.value = null;
    }
  }

  /// 看板快照防抖落盘：状态变化后 2s 内再写一次，避免高频事件刷存储。
  void _scheduleSnapshotSave(KdsV2Controller controller) {
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = Timer(const Duration(seconds: 2), () {
      _snapshotSaveTimer = null;
      unawaited(_flushSnapshotSave(controller));
    });
  }

  /// 立即将当前权威状态写入本地快照（bootstrap 成功/主动清理时调用）。
  Future<void> _flushSnapshotSave(KdsV2Controller controller) async {
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = null;
    if (!identical(_controller, controller)) return;
    final store = _snapshotStore;
    if (store == null) return;
    await store.save(controller.state,
        shopId: ref.read(sessionProvider).device?.shopId);
  }

  /// 兜底轮询（修复：收银端 WS 推送静默失效时看板长期不刷新）。
  /// 每 15s 走一次 /kds/v2/changes 增量补偿；无变更时不发射任何状态，
  /// 失败静默保留当前画面，不会打断 WS 事件路径。
  void _startFallbackPoll(KdsV2Controller controller, String key) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_fallbackPollInterval, (_) {
      if (!identical(_controller, controller) || _sessionKey != key) return;
      // 增量追赶治理（T007）：以 /kds/v2/changes 增量追赶为主路径；
      // 营业日完整快照仅在冷启动、内部重建（onBootstrapApplied）或营业时段窗口过期切换时拉取，杜绝每分钟高频全量拉取。
      if (controller.isBusinessDayWindowExpired) {
        final minute = _minuteStamp();
        if (minute != _snapshotMinute) {
          _snapshotMinute = minute;
          unawaited(controller.refreshBusinessDayOrders().catchError((error) {
            KdsFileLogger.warn('[SNAP] 营业时段切换补拉快照失败: $error');
          }));
        }
      }
      unawaited(controller.poll().then((_) {
        if (identical(_controller, controller) && _sessionKey == key) {
          unawaited(_flushOutbox(controller, key));
        }
      }));
    });
  }

  static int _minuteStamp() => DateTime.now().millisecondsSinceEpoch ~/ 60000;

  /// 诊断：服务端 queue_counts 与本地明细投影不一致时记录日志。
  /// 典型残留场景：服务端计数 > 0 但本屏没有任何可见明细（历史数据、
  /// 权限口径差异）。同一队列 1 分钟内只记一次，避免刷屏。
  void _logQueueCountDrift(KdsV2State next) {
    if (next.queueCounts.isEmpty) return;
    final local = <String, int>{};
    for (final line in next.lines) {
      for (final slice in line.slices) {
        if (slice.quantity <= 0) continue;
        local.update(slice.queue, (value) => value + slice.quantity,
            ifAbsent: () => slice.quantity);
      }
    }
    final now = DateTime.now();
    for (final entry in next.queueCounts.entries) {
      if (entry.value <= 0) continue;
      if ((local[entry.key] ?? 0) > 0) continue;
      final last = _countDriftLoggedAt[entry.key];
      if (last != null && now.difference(last) < const Duration(minutes: 1)) {
        continue;
      }
      _countDriftLoggedAt[entry.key] = now;
      KdsFileLogger.warn(
        '[Board] 角标与内容不一致：服务端 ${entry.key}=${entry.value}，'
        '本屏无可见明细（疑似历史残留或统计口径差异）',
      );
    }
  }

  /// 整单推进的逐明细实现：只推进该订单中流程仍停留在 [fromQueue]
  /// 的行（数量 = 该行在该队列的权威切片数量，乐观锁 = 行 revision）。
  /// 已进入其他队列（如待传菜）的行不受影响，严格遵循单一流程。
  /// 返回实际下发推进命令的明细行数。
  Future<int> advanceOrderLines({
    required int orderId,
    required String fromQueue,
    bool includePrep = false,
  }) async {
    final controller = _controller;
    final key = _sessionKey;
    if (controller == null || key == null) {
      throw StateError('KDS board is not ready');
    }
    final targets = orderLinesToAdvance(
      controller.state.lines,
      orderId: orderId,
      fromQueue: fromQueue,
      includePrep: includePrep,
    );
    final targetQueues = (fromQueue == 'pending_cook' && includePrep)
        ? const {'pending_cook', 'pending_prep'}
        : {fromQueue};
    for (final line in targets) {
      for (final slice in line.slices) {
        if (!targetQueues.contains(slice.queue) || slice.quantity <= 0) {
          continue;
        }
        await _sendWithController(
          controller,
          key,
          type: KdsV2CommandType.advanceItem,
          target: KdsV2CommandTarget(
            detailId: line.detailId,
            fromQueue: slice.queue,
          ),
          quantity: slice.quantity,
          expectedRevision: line.revision,
        );
      }
    }
    return targets.length;
  }

  Future<void> send({
    required KdsV2CommandType type,
    required KdsV2CommandTarget target,
    int? quantity,
    int? expectedRevision,
    String? remark,
    bool? setSoldOut,
    Map<int, int> expectedRevisions = const {},
  }) async {
    final controller = _controller;
    final key = _sessionKey;
    if (controller == null || key == null) {
      throw StateError('KDS board is not ready');
    }
    await _sendWithController(
      controller,
      key,
      type: type,
      target: target,
      quantity: quantity,
      expectedRevision: expectedRevision,
      remark: remark,
      setSoldOut: setSoldOut,
      expectedRevisions: expectedRevisions,
    );
  }

  Future<void> _sendWithController(
    KdsV2Controller controller,
    String key, {
    required KdsV2CommandType type,
    required KdsV2CommandTarget target,
    int? quantity,
    int? expectedRevision,
    String? remark,
    bool? setSoldOut,
    Map<int, int> expectedRevisions = const {},
  }) async {
    if (!identical(_controller, controller) || _sessionKey != key) {
      throw StateError('KDS session changed before command dispatch');
    }
    final command = KdsV2Command(
      commandId: const Uuid().v4(),
      type: type,
      target: target,
      quantity: quantity,
      expectedRevision: expectedRevision,
      remark: remark,
      setSoldOut: setSoldOut,
      expectedRevisions: expectedRevisions,
    );
    final hidden = optimisticAdvanceKeys(
      lines: controller.state.lines,
      type: type,
      target: target,
    );
    final aggKey = _aggregateKeyForCommand(command);
    final effectiveChannel = _transport?.activeChannel.value ??
        ref.read(sessionProvider).activeChannel.value;
    final overlay = KdsV2OptimisticOverlay.fromCommand(
      command: command,
      aggregateKey: aggKey,
      createdAt: DateTime.now(),
      status: KdsOverlayStatus.persisting,
      originChannel: effectiveChannel,
    );
    _overlays.add(overlay);

    for (final hKey in hidden) {
      _optimisticAdvanceCounts.update(hKey, (count) => count + 1,
          ifAbsent: () => 1);
    }
    // 同步刷新可见状态：p95 <= 50ms（同步完成）
    state = _visibleState(controller.state);

    if (_scheduler.pendingCount >= KdsCommandOutboxStore.maxCapacity) {
      _overlays.removeWhere((o) => o.commandId == command.commandId);
      for (final hKey in hidden) {
        final count = _optimisticAdvanceCounts[hKey] ?? 0;
        if (count <= 1) {
          _optimisticAdvanceCounts.remove(hKey);
        } else {
          _optimisticAdvanceCounts[hKey] = count - 1;
        }
      }
      state = _visibleState(controller.state);
      KdsFileLogger.warn(
          '[OP] 待发指令队列已达容量上限(${KdsCommandOutboxStore.maxCapacity})，拒绝新指令');
      throw StateError(
          '指令待发队列已满(${KdsCommandOutboxStore.maxCapacity})，请等待网络恢复或稍后再试');
    }

    final targetDesc = target.detailId != null
        ? 'detail=${target.detailId}'
        : target.detailIds.isNotEmpty
            ? 'details=${target.detailIds}'
            : 'order=${target.orderId}';
    KdsFileLogger.info(
        '[OP] 下发 ${type.wireName} $targetDesc from=${target.fromQueue ?? '-'} qty=${quantity ?? '-'} cmd=${command.commandId}');
    final newCmd = _PendingSyncCommand(
      id: command.commandId,
      command: command,
      hiddenKeys: hidden,
      createdAt: DateTime.now(),
      status: KdsOutboxStatus.persisting,
      originChannel: effectiveChannel,
    );
    _outboxQueue.add(newCmd);

    try {
      await _enqueueOutbox(newCmd);
      final pendingCmd = newCmd.copyWith(status: KdsOutboxStatus.pending);
      _syncOverlayWithOutbox(pendingCmd);
      unawaited(_updateOutbox(pendingCmd));
      final idx = _outboxQueue.indexWhere((c) => c.id == newCmd.id);
      if (idx >= 0) _outboxQueue[idx] = pendingCmd;
      if (!_allChannelsUnavailable) {
        _scheduler.resume();
      }
      _scheduler.resumeAggregate(aggKey);
      _scheduler.enqueue(pendingCmd);
      state = _visibleState(controller.state);
    } catch (e) {
      _overlays.removeWhere((o) => o.commandId == command.commandId);
      _outboxQueue.removeWhere((c) => c.id == newCmd.id);
      for (final hKey in hidden) {
        final count = _optimisticAdvanceCounts[hKey] ?? 0;
        if (count <= 1) {
          _optimisticAdvanceCounts.remove(hKey);
        } else {
          _optimisticAdvanceCounts[hKey] = count - 1;
        }
      }
      state = _visibleState(controller.state);
      KdsFileLogger.error('[OP] 指令落盘失败，已回滚乐观显示: $e');
      rethrow;
    }
  }

  String _aggregateKeyForCommand(KdsV2Command command) {
    return kdsAggregateKeyForCommand(
      command,
      _controller?.state.lines ?? const <KdsV2Line>[],
    );
  }

  KdsActiveChannel? _activeChannelFromValue(String? raw) {
    if (raw == null) return null;
    for (final channel in KdsActiveChannel.values) {
      if (channel.value == raw) return channel;
    }
    return null;
  }

  /// 唤醒调度器冲刷待同步队列中的指令
  Future<void> _flushOutbox(KdsV2Controller controller, String key) async {
    if (!identical(_controller, controller) || _sessionKey != key) return;
    if (!_allChannelsUnavailable) {
      _scheduler.resume();
      _scheduler.resumeAllAggregates();
    }
  }

  Future<KdsCommandExecutionResult> _executeScheduledCommand(
    KdsOutboxRecord record,
    int generation,
  ) async {
    final controller = _controller;
    final key = _sessionKey;
    if (controller == null || key == null) {
      return const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.networkFailure,
        errorMessage: 'controller detached',
      );
    }

    final aggKey = _aggregateKeyForCommand(record.command);
    final activeChannel = _transport?.activeChannel.value;

    if (record.requiresResolution) {
      final originChannel = _activeChannelFromValue(record.originChannel) ??
          _activeChannelFromValue(activeChannel) ??
          _activeChannelFromValue(
              ref.read(sessionProvider).activeChannel.value) ??
          KdsActiveChannel.cloud;

      if (record.originChannel != originChannel.value) {
        KdsFileLogger.info(
            '[OP] cmd=${record.command.commandId} 缺少有效原始通道(${record.originChannel})，自动补充为 ${originChannel.value} 并发起账本裁决');
        final patched = record.copyWith(originChannel: originChannel.value);
        _syncOverlayWithOutbox(patched);
        unawaited(_updateOutbox(patched));
        final idx = _outboxQueue.indexWhere((c) => c.id == record.id);
        if (idx >= 0) _outboxQueue[idx] = patched;
      }
      final canCloudReplicaProbe = originChannel == KdsActiveChannel.lan &&
          activeChannel == KdsActiveChannel.cloud.value &&
          _transport?.cloudTransport != null;
      final canLanProxyProbe = originChannel == KdsActiveChannel.cloud &&
          activeChannel == KdsActiveChannel.lan.value;
      if (activeChannel != originChannel.value &&
          !canCloudReplicaProbe &&
          !canLanProxyProbe) {
        KdsFileLogger.warn(
            '[OP] cmd=${record.command.commandId} 等待原通道 ${originChannel.value} 裁决，挂起聚合 $aggKey，当前通道=$activeChannel');
        return const KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.networkFailure,
          errorMessage: 'channel mismatch for resolution',
        );
      }
      final transport = _transport;
      if (transport == null) {
        return const KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.networkFailure,
          errorMessage: 'transport is null',
        );
      }
      try {
        final resolution = await transport.resolveCommand(
          record.command.commandId,
          originChannel: originChannel,
        );
        if (!identical(_controller, controller) || _sessionKey != key) {
          return const KdsCommandExecutionResult(
            outcome: KdsCommandExecutionOutcome.networkFailure,
            errorMessage: 'session changed',
          );
        }
        switch (resolution.status) {
          case KdsV2CommandResolutionStatus.applied:
            final result = resolution.result!;
            await controller.ingest(
              result.asEnvelope(
                shopId: controller.expectedShopId,
                occurredAtMs: DateTime.now().millisecondsSinceEpoch,
              ),
              source: KdsDishLoadSource.commandResponse,
              channel: originChannel.value,
            );
            KdsFileLogger.info(
                '[OP] cmd=${record.command.commandId} UNKNOWN 已裁决为 APPLIED');
            _removeOverlayAndOutbox(record.id);
            return const KdsCommandExecutionResult(
              outcome: KdsCommandExecutionOutcome.success,
            );
          case KdsV2CommandResolutionStatus.executing:
            KdsFileLogger.info(
                '[OP] cmd=${record.command.commandId} UNKNOWN 仍在 EXECUTING，挂起聚合 $aggKey 稍后再查');
            return const KdsCommandExecutionResult(
              outcome: KdsCommandExecutionOutcome.networkFailure,
              errorMessage: 'executing',
            );
          case KdsV2CommandResolutionStatus.rejected:
            KdsFileLogger.warn(
                '[OP] cmd=${record.command.commandId} 已被权威端拒绝，移除本地待确认操作');
            _removeOverlayAndOutbox(record.id);
            return const KdsCommandExecutionResult(
              outcome: KdsCommandExecutionOutcome.businessFailure,
              errorMessage: 'rejected',
            );
          case KdsV2CommandResolutionStatus.notFound:
            KdsFileLogger.info(
                '[OP] cmd=${record.command.commandId} UNKNOWN 已裁决为 NOT_FOUND，允许同 ID 重发');
            final updated = record.copyWith(
              status: KdsOutboxStatus.pending,
              requiresResolution: false,
              originChannel: activeChannel,
            );
            _syncOverlayWithOutbox(updated);
            unawaited(_updateOutbox(updated));
            final idx = _outboxQueue.indexWhere((c) => c.id == record.id);
            if (idx >= 0) _outboxQueue[idx] = updated;
            return KdsCommandExecutionResult(
              outcome: KdsCommandExecutionOutcome.networkFailure,
              errorMessage: 'not found ready to retry',
              nextRecord: updated,
            );
        }
      } catch (error) {
        final failed = record.copyWith(
          status: KdsOutboxStatus.unknown,
          lastError: '$error',
          requiresResolution: true,
        );
        _syncOverlayWithOutbox(failed);
        unawaited(_updateOutbox(failed));
        final idx = _outboxQueue.indexWhere((c) => c.id == record.id);
        if (idx >= 0) _outboxQueue[idx] = failed;
        KdsFileLogger.warn(
            '[OP] cmd=${record.command.commandId} UNKNOWN 查证失败，挂起聚合 $aggKey: $error');
        return KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.networkFailure,
          errorMessage: '$error',
          nextRecord: failed,
        );
      }
    }

    final sendingRecord = record.copyWith(
      status: KdsOutboxStatus.sending,
      retryCount: record.retryCount + 1,
      lastAttemptAt: DateTime.now(),
    );
    _syncOverlayWithOutbox(sendingRecord);
    unawaited(_updateOutbox(sendingRecord));
    final qIdx = _outboxQueue.indexWhere((c) => c.id == record.id);
    if (qIdx >= 0) _outboxQueue[qIdx] = sendingRecord;
    state = _visibleState(controller.state);

    final isAdvance = record.command.type == KdsV2CommandType.advanceItem;
    final undoDetailId = record.command.target.detailId;
    final preQueues = isAdvance && undoDetailId != null
        ? _lineQueues(controller, undoDetailId)
        : const <String, int>{};

    try {
      await controller.command(record.command);
      KdsFileLogger.info(
          '[OP] 确认 ${record.command.type.wireName} cmd=${record.command.commandId} 成功');
      if (isAdvance &&
          undoDetailId != null &&
          identical(_controller, controller) &&
          _sessionKey == key) {
        _pushUndo(controller, record.command, preQueues, undoDetailId);
      }
      _removeOverlayAndOutbox(record.id);
      return const KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.success,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 429) {
        final pending = sendingRecord.copyWith(
          status: KdsOutboxStatus.pending,
          lastError: error.message,
        );
        _syncOverlayWithOutbox(pending);
        unawaited(_updateOutbox(pending));
        final idx = _outboxQueue.indexWhere((c) => c.id == record.id);
        if (idx >= 0) _outboxQueue[idx] = pending;
        return KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.rateLimited,
          errorMessage: error.message,
          nextRecord: pending,
        );
      } else if (error.statusCode == 409 || error.code == 4090) {
        KdsFileLogger.warn(
            '[OP] ${record.command.type.wireName} cmd=${record.command.commandId} 冲突(409)，移除并对齐');
        _removeOverlayAndOutbox(record.id);
        return KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.conflict,
          errorMessage: error.message,
        );
      } else if (error.isNetworkError || error.isTransientServiceFailure) {
        final failed = sendingRecord.copyWith(
          status: KdsOutboxStatus.unknown,
          lastError: error.message,
          requiresResolution: true,
        );
        _syncOverlayWithOutbox(failed);
        unawaited(_updateOutbox(failed));
        final idx = _outboxQueue.indexWhere((c) => c.id == record.id);
        if (idx >= 0) _outboxQueue[idx] = failed;
        KdsFileLogger.warn(
            '[OP] ${record.command.type.wireName} cmd=${record.command.commandId} 网络异常，挂起聚合 $aggKey 待重试');
        return KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.networkFailure,
          errorMessage: error.message,
          nextRecord: failed,
        );
      } else {
        KdsFileLogger.warn(
            '[OP] ${record.command.type.wireName} cmd=${record.command.commandId} 业务失败并移除: ${error.message}');
        _removeOverlayAndOutbox(record.id);
        return KdsCommandExecutionResult(
          outcome: KdsCommandExecutionOutcome.businessFailure,
          errorMessage: error.message,
        );
      }
    } catch (e) {
      final failed = sendingRecord.copyWith(
        status: KdsOutboxStatus.unknown,
        lastError: '$e',
        requiresResolution: true,
      );
      _syncOverlayWithOutbox(failed);
      unawaited(_updateOutbox(failed));
      final idx = _outboxQueue.indexWhere((c) => c.id == record.id);
      if (idx >= 0) _outboxQueue[idx] = failed;
      KdsFileLogger.warn(
          '[OP] ${record.command.type.wireName} cmd=${record.command.commandId} 通信异常，挂起聚合 $aggKey: $e');
      return KdsCommandExecutionResult(
        outcome: KdsCommandExecutionOutcome.networkFailure,
        errorMessage: '$e',
        nextRecord: failed,
      );
    }
  }

  void _removeOverlayAndOutbox(String commandId) {
    _overlays.removeWhere((o) => o.commandId == commandId);
    _scheduler.removeCommand(commandId);
    final idx = _outboxQueue.indexWhere((cmd) => cmd.id == commandId);
    if (idx >= 0) {
      final item = _outboxQueue.removeAt(idx);
      for (final hKey in item.hiddenKeys) {
        final count = _optimisticAdvanceCounts[hKey] ?? 0;
        if (count <= 1) {
          _optimisticAdvanceCounts.remove(hKey);
        } else {
          _optimisticAdvanceCounts[hKey] = count - 1;
        }
      }
    }
    unawaited(_removeOutbox(commandId));
    if (_controller case final controller?) {
      state = _visibleState(controller.state);
    }
  }

  void _syncOverlayWithOutbox(KdsOutboxRecord record) {
    final idx = _overlays.indexWhere((o) => o.commandId == record.id);
    if (idx >= 0) {
      _overlays[idx] = KdsV2OptimisticOverlay.fromOutboxRecord(
        record,
        aggregateKey: _overlays[idx].aggregateKey,
      );
    }
  }

  /// 按队列聚合某明细当前各切片数量（撤销落点判定用）。
  Map<String, int> _lineQueues(KdsV2Controller controller, int detailId) {
    for (final line in controller.state.lines) {
      if (line.detailId != detailId) continue;
      return {for (final slice in line.slices) slice.queue: slice.quantity};
    }
    return const {};
  }

  /// 划菜确认成功后记录可撤回项。仅「待传菜 → 已完成」的划菜才提示倒计时
  /// 撤回；待配菜→待制作、待制作→待传菜 均不提示。
  /// 只保留最近一次：新的可撤回划菜直接替换旧通知，上一条不再显示、不可撤回。
  void _pushUndo(KdsV2Controller controller, KdsV2Command command,
      Map<String, int> preQueues, int detailId) {
    final postQueues = _lineQueues(controller, detailId);
    final sourceQueue = command.target.fromQueue ?? '';
    final destQueue = advanceDestQueue(sourceQueue, preQueues, postQueues);
    // 仅「待传菜划到已完成」的划菜需要倒计时撤回提示
    if (sourceQueue != 'ready_serve' || destQueue != 'done') return;
    final moved = sourceQueue.isEmpty
        ? 0
        : (preQueues[sourceQueue] ?? 0) - (postQueues[sourceQueue] ?? 0);
    final quantity = moved > 0 ? moved : (command.quantity ?? 0);
    if (quantity <= 0) return;
    KdsV2Line? line;
    for (final candidate in controller.state.lines) {
      if (candidate.detailId == detailId) {
        line = candidate;
        break;
      }
    }
    if (line == null) return;
    final tableOrCode = resolveLineTableOrPickupCode(
      channel: line.channel,
      raw: line.raw,
      cloudOrderId: line.cloudOrderId,
      orderId: line.orderId,
      allLines: controller.state.lines,
    );
    final item = KdsAdvanceUndoItem(
      detailId: detailId,
      orderId: line.orderId,
      dishName: line.dishName,
      unit: '${line.raw['unit'] ?? ''}',
      quantity: quantity,
      destQueue: destQueue,
      tableOrPickupCode: tableOrCode,
    );
    // 单条替换：只允许撤回最近一次划菜，不支持整批/全部撤回。
    undoBatch.value =
        KdsAdvanceUndoBatch(items: [item], generatedAt: DateTime.now());
  }

  /// 撤回最近一次划菜：对单条明细下发 revoke_item，把刚划入已完成的菜品
  /// 退回上一步（待传菜）。期望版本取当前行的权威 revision，冲突由 outbox 兜底。
  Future<void> revokeUndoBatch(KdsAdvanceUndoBatch batch) async {
    final controller = _controller;
    final key = _sessionKey;
    if (controller == null || key == null || batch.items.isEmpty) return;
    for (final item in batch.items) {
      int? revision;
      for (final line in controller.state.lines) {
        if (line.detailId == item.detailId) {
          revision = line.revision;
          break;
        }
      }
      KdsFileLogger.info(
          '[OP] 撤回划菜 detail=${item.detailId} qty=${item.quantity} from=${item.destQueue}');
      await _sendWithController(
        controller,
        key,
        type: KdsV2CommandType.revokeItem,
        target: KdsV2CommandTarget(
          detailId: item.detailId,
          fromQueue: item.destQueue,
        ),
        quantity: item.quantity,
        expectedRevision: revision,
      );
    }
    undoBatch.value = null;
    channelSwitchSuggestion.value = null;
  }

  Future<void> _handleNewOrder(
      KdsV2Controller controller, String sessionKey) async {
    final prefs = await ref.read(appPrefsProvider.future);
    if (!identical(_controller, controller) || _sessionKey != sessionKey) {
      return;
    }
    if (prefs.newOrderSoundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.alert).catchError((_) {}));
    }
  }

  Future<bool> setPrepFlowEnabled(bool enabled) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('KDS 尚未连接收银端，无法同步待配菜流程设置');
    }
    KdsFileLogger.info('[OP] 同步配菜流程设置 → ${enabled ? '开启' : '关闭'}');
    await controller.updateConfig({
      'enable_prep_workflow': enabled ? 1 : 0,
      'prep_enabled': enabled ? 1 : 0,
    });
    final prefs = await ref.read(appPrefsProvider.future);
    await prefs.setPrepFlowEnabled(enabled);
    return true;
  }

  void _detach() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _snapshotSaveTimer?.cancel();
    _snapshotSaveTimer = null;
    // 重连/切页前立即落盘当前状态：避免最后 2s 防抖窗口内的已完成行
    // 未落盘，重连 restoreSnapshot 用旧快照覆盖导致"正常流程消失"。
    final detaching = _controller;
    if (detaching != null && ref.read(sessionProvider).isLoggedIn) {
      unawaited(_flushSnapshotSave(detaching));
    }
    final isLoggedIn = ref.read(sessionProvider).isLoggedIn;
    _scheduler.pause();
    if (!isLoggedIn) {
      unawaited(_snapshotStore?.clear());
      _outboxQueue.clear();
      _overlays.clear();
      _scheduler.clear();
      unawaited(_clearOutbox());
      _optimisticAdvanceCounts.clear();
    }
    _eventSub?.cancel();
    _connectedSub?.cancel();
    _eventSub = null;
    _transport?.dispose();
    _transport = null;
    _controller = null;
    _sessionKey = null;
    _lastEventAtMs = null;
    _countDriftLoggedAt.clear();
    undoBatch.value = null;
    if (!isLoggedIn) {
      state = const KdsV2State();
    }
  }

  void _dispose() {
    _scheduler.dispose();
    _transport?.dispose();
    _pollTimer?.cancel();
    _snapshotSaveTimer?.cancel();
    _eventSub?.cancel();
    _connectedSub?.cancel();
    channelSwitchSuggestion.dispose();
    refundAlerts.dispose();
  }
}
