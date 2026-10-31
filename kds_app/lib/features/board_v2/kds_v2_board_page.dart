import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:kds_app/core/api/api_exception.dart';
import 'package:kds_app/core/board/kds_line_wait_time.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/lan_v2/kds_dual_mode_transport.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';
import 'package:kds_app/core/board/kds_spec_text.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/core/storage/app_prefs.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/features/board_v2/kds_queue_tasks_dialog.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_logic.dart';
import 'package:kds_app/features/board_v2/kds_undo_toast.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/diagnostics/kds_inspector_modal.dart';
import 'package:kds_app/features/shell/board_shell.dart';

class KdsV2BoardPage extends ConsumerStatefulWidget {
  const KdsV2BoardPage({super.key});

  @override
  ConsumerState<KdsV2BoardPage> createState() => _KdsV2BoardPageState();
}

class _KdsV2BoardPageState extends ConsumerState<KdsV2BoardPage> {
  late final KdsV2BoardNotifier _boardNotifier;
  bool _channelDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _boardNotifier = ref.read(kdsV2BoardProvider.notifier);
    _boardNotifier.channelSwitchSuggestion.addListener(_onSwitchSuggested);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSwitchSuggested());
  }

  @override
  void dispose() {
    _boardNotifier.channelSwitchSuggestion.removeListener(_onSwitchSuggested);
    super.dispose();
  }

  void _onSwitchSuggested() {
    final suggestion = _boardNotifier.channelSwitchSuggestion.value;
    if (!mounted || suggestion == null || _channelDialogOpen) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _channelDialogOpen) return;
      _showChannelSwitchDialog(suggestion, automaticSuggestion: true);
    });
  }

  Future<void> _showManualChannelDialog(KdsActiveChannel activeChannel) async {
    final target = activeChannel == KdsActiveChannel.cloud
        ? KdsActiveChannel.lan
        : KdsActiveChannel.cloud;
    await _showChannelSwitchDialog(
      KdsChannelSwitchSuggestion(
        targetChannel: target,
        reason: '手动选择连接通道',
        detectedAt: DateTime.now(),
      ),
      automaticSuggestion: false,
    );
  }

  Future<void> _showChannelSwitchDialog(
    KdsChannelSwitchSuggestion suggestion, {
    required bool automaticSuggestion,
  }) async {
    if (!mounted || _channelDialogOpen) return;
    _channelDialogOpen = true;
    final target = suggestion.targetChannel;
    final targetLabel = target == KdsActiveChannel.lan ? '局域网代理' : '云端';
    final title = automaticSuggestion
        ? target == KdsActiveChannel.lan
            ? '云端响应异常，切换到局域网代理？'
            : '云端连接已恢复，切换回云端？'
        : '切换到$targetLabel？';
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(
            '${suggestion.reason}。\n\n'
            '确认后会先校验门店、权威游标和数据版本，再切换 HTTP 与实时连接；'
            '取消则保持当前通道，待确认操作不会被清空。',
          ),
          actions: [
            TextButton(
              key: const ValueKey('channel-switch-stay'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('保持当前通道'),
            ),
            FilledButton.icon(
              key: ValueKey('channel-switch-confirm-${target.value}'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: Icon(target == KdsActiveChannel.lan
                  ? Icons.lan_outlined
                  : Icons.cloud_outlined),
              label: Text('切换到$targetLabel'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) {
        if (automaticSuggestion) {
          _boardNotifier.dismissChannelSwitchSuggestion(target);
        }
        return;
      }
      try {
        await _boardNotifier.switchActiveChannel(target);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('正在安全切换到$targetLabel…')),
        );
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未能切换到$targetLabel：$error')),
        );
      }
    } finally {
      _channelDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(kdsV2BoardProvider);
    final session = ref.watch(sessionProvider);
    final workflows = session.device?.workflows ?? const [];
    final prefs = ref.watch(appPrefsProvider).asData?.value;
    final prepVal = state.config['enable_prep_workflow'] ??
        state.config['prep_enabled'] ??
        prefs?.prepFlowEnabled ??
        true;
    final prepFlowEnabled = prepVal is bool
        ? prepVal
        : (prepVal is num ? prepVal != 0 : '$prepVal' == '1');

    return KdsV2ThreeFlowBoard(
      state: state,
      workflows: workflows,
      activeChannel: session.activeChannel,
      wsConnected: state.connected,
      statsLine: _statsLabel(state),
      fixedDishOrderEnabled: prefs?.fixedDishOrderEnabled ?? true,
      mergeSameDishNameEnabled: prefs?.mergeSameDishNameEnabled ?? true,
      prepFlowEnabled: prepFlowEnabled,
      advanceQuantityDialogEnabled:
          prefs?.advanceQuantityDialogEnabled ?? false,
      addDishIndependentEnabled: prefs?.addDishIndependentEnabled ?? false,
      refundAlerts: ref.watch(kdsV2BoardProvider.notifier).refundAlerts,
      onDismissRefundAlert:
          ref.watch(kdsV2BoardProvider.notifier).dismissRefundAlert,
      cardScale: (prefs?.cardScalePercent ?? 100) / 100,
      onCardScalePersisted: (scale) async {
        final store = await ref.read(appPrefsProvider.future);
        await store.setCardScalePercent((scale * 100).round());
      },
      onRefresh: () => ref.read(kdsV2BoardProvider.notifier).refresh(),
      onSettings: () => context.push('/settings'),
      onLogs: () => context.push('/logs'),
      onInspector: () => showKdsInspectorModal(context),
      onQueueTasks: () {
        KdsFileLogger.info('[PAGE] 打开队列任务');
        showDialog<void>(
          context: context,
          builder: (_) => Consumer(
            builder: (context, dialogRef, __) {
              final current = dialogRef.watch(kdsV2BoardProvider);
              return KdsQueueTasksDialog(
                tasks: current.overlays,
                pendingCount: current.pendingSyncCount,
              );
            },
          ),
        );
      },
      onLogout: () async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('退出设备登录？'),
            content: const Text('退出后将清除本地会话缓存并返回登录页，您可以输入门店 PIN 码重新登录。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: const Text('退出并重登'),
              ),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          await ref.read(sessionProvider.notifier).logout();
          if (context.mounted) context.go('/login');
        }
      },
      onChannelSwitch: () => _showManualChannelDialog(session.activeChannel),
    );
  }

  String? _statsLabel(KdsV2State state) {
    if (state.stats.isEmpty) return null;
    return state.stats.entries
        .take(2)
        .map((e) => '${e.key}: ${e.value}')
        .join(' · ');
  }
}

List<KdsV2LineSlice> _slicesForQueue(
  KdsV2State state,
  String queue, {
  bool includePrep = false,
}) {
  final targetQueues = (queue == 'pending_cook' && includePrep)
      ? const {'pending_cook', 'pending_prep'}
      : {queue};
  return state.lines
      .expand((detail) => detail.slices)
      .where((slice) =>
          targetQueues.contains(slice.queue) &&
          slice.quantity > 0 &&
          (slice.isOptimistic ||
              !state.optimisticHiddenSlices
                  .contains('${slice.detailId}:${slice.queue}')))
      .toList();
}

/// 渠道前缀：自提/打包、外卖；堂食为 null
String? _channelPrefix(String channel) => switch (channel) {
      'pickup' || 'pack' => '自提',
      'takeout' || 'delivery' => '外卖',
      _ => null,
    };

/// 卡片或明细行标识：堂食单显示台号，自提和外卖单仅显示取餐码（cloud_order_id）
String lineTableOrPickupCode(KdsV2LineSlice line,
    [Iterable<KdsV2LineSlice>? group]) {
  final prefix = _channelPrefix(line.channel);
  if (prefix == null) {
    final table = '${line.raw['table_number'] ?? ''}'.trim();
    if (table.isNotEmpty) return table;
    final code = kdsPickupCode(line, group);
    return code != null ? '堂食 $code' : '堂食';
  }
  final code = kdsPickupCode(line, group);
  return code != null ? '$prefix $code' : prefix;
}

/// 订单卡片表头：堂食单显示台号（无台号显示「未提供台号」），自提和外卖单仅显示取餐码（cloud_order_id）
String orderHeaderLabel(KdsV2LineSlice line,
    [Iterable<KdsV2LineSlice> group = const []]) {
  final prefix = _channelPrefix(line.channel);
  if (prefix == null) {
    final table = '${line.raw['table_number'] ?? ''}'.trim();
    return table.isEmpty ? '未提供台号' : table;
  }
  final code = kdsPickupCode(line, group);
  return code != null ? '$prefix $code' : prefix;
}

/// 角标数量从本地权威行投影推导，与卡片列表保持同一数据源和过滤规则。
/// 菜品视图下统计活动菜品卡片数，订单视图下统计订单数。
Map<String, int> _localQueueCounts(
  KdsV2State state, {
  BoardDining dining = BoardDining.all,
  BoardExtraFilter? extra,
  bool includePrepInCook = false,
  bool isDishView = true,
  bool fixedDishOrderEnabled = true,
  bool mergeSameDishNameEnabled = true,
}) {
  final result = <String, int>{};
  final targetSlicesByQueue = <String, List<KdsV2LineSlice>>{};
  for (final line in state.lines) {
    for (final slice in line.slices) {
      if (slice.quantity <= 0) continue;
      if (!slice.isOptimistic &&
          state.optimisticHiddenSlices
              .contains('${slice.detailId}:${slice.queue}')) {
        continue;
      }
      if (!_matchesDining(slice, dining)) continue;
      if (extra != null && !_matchesExtra(slice, extra, state.config)) {
        continue;
      }
      final queueKey = (slice.queue == 'pending_prep' && includePrepInCook)
          ? 'pending_cook'
          : slice.queue;
      targetSlicesByQueue.putIfAbsent(queueKey, () => []).add(slice);
    }
  }
  for (final entry in targetSlicesByQueue.entries) {
    final count = countBoardSlices(
      slices: entry.value,
      isDishView: isDishView,
      isDone: entry.key == 'done',
      fixedDishOrderEnabled: fixedDishOrderEnabled,
      mergeSameDishNameEnabled: mergeSameDishNameEnabled,
    );
    if (count > 0) {
      result[entry.key] = count;
    }
  }
  return result;
}

/// 履约渠道归并到餐饮筛选项键（BoardDining.apiValue）
String _diningCountKey(String channel) => switch (channel) {
      'dine_in' => 'dine_in',
      'takeout' || 'delivery' => 'takeout',
      'pack' || 'pickup' => 'pack',
      _ => channel,
    };

/// 命令失败提示人性化：避免向收银员暴露原始异常串
String friendlyCommandError(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 409 || error.code == 4090) {
      return '数据已被其他设备更新，请重试';
    }
    if (error.isNetworkError) return '网络异常，请检查连接后重试';
    if (error.message.trim().isNotEmpty) return error.message;
    return '操作失败，请重试';
  }
  if (error is TimeoutException) return '操作超时，请重试';
  if (error is FormatException) return '数据格式异常，请刷新页面后重试';
  return '操作失败，请重试';
}

/// 划菜/推进失败防呆警示：播放警告音与高反差提示，防止厨师误认为已划走而重复出餐
void showKdsAdvanceFailureNotice(BuildContext context, Object error, {String action = '划菜'}) {
  HapticFeedback.heavyImpact();
  unawaited(SystemSound.play(SystemSoundType.alert).catchError((_) {}));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: const Color(0xFFC62828),
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
      content: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$action失败（${friendlyCommandError(error)}）：卡片已恢复原状，请勿提前出餐！',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 格式化已完成菜品的总耗时（从下单到出餐/传菜一共花费的时间，耗时固定冻结，不随时间累加）
String formatKdsCompletionDuration(Map<String, dynamic> raw) {
  // 超过 24 小时视为异常（服务端时间字段错乱/历史脏数据），显示为占位，
  // 避免把 27859 分钟这类离谱值直接展示给后厨。
  String? minutesOrNull(int seconds) {
    final minutes = (seconds / 60).ceil();
    if (minutes > 24 * 60) return '—';
    return '$minutes分钟';
  }

  final completedWait = raw['completed_wait_seconds'];
  if (completedWait is num && completedWait >= 0) {
    return minutesOrNull(completedWait.toInt()) ?? '—';
  }

  // 1. 获取出餐/完成时间
  DateTime? completedAt;
  for (final key in const [
    'completed_at_ms',
    'queue_completed_at',
    'served_at',
    'completed_at',
    'archived_at',
    'cooked_at',
    'updated_at_ms',
  ]) {
    final val = raw[key];
    if (val is num && val > 0) {
      completedAt = DateTime.fromMillisecondsSinceEpoch(val.toInt());
      break;
    }
    if (val is String && val.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(val.trim().replaceFirst(' ', 'T'));
      if (parsed != null) {
        completedAt = parsed;
        break;
      }
    }
  }

  // 2. 获取下单时间
  DateTime? startAt;
  for (final key in const [
    'order_time',
    'first_order_time',
    'created_at_ms',
    'created_at',
    'ticket_created_at',
    'add_dish_time',
  ]) {
    final val = raw[key];
    if (val is num && val > 0) {
      startAt = DateTime.fromMillisecondsSinceEpoch(val.toInt());
      break;
    }
    if (val is String && val.trim().isNotEmpty) {
      final parsed = DateTime.tryParse(val.trim().replaceFirst(' ', 'T'));
      if (parsed != null) {
        startAt = parsed;
        break;
      }
    }
  }

  if (completedAt != null && startAt != null) {
    final elapsedSeconds = completedAt.difference(startAt).inSeconds;
    if (elapsedSeconds >= 0) {
      return minutesOrNull(elapsedSeconds) ?? '—';
    }
  }

  if (raw['wait_seconds'] is num) {
    final wait = (raw['wait_seconds'] as num).toInt();
    return minutesOrNull(wait) ?? '—';
  }

  return '0分钟';
}

bool _matchesDining(KdsV2LineSlice slice, BoardDining dining) {
  if (dining == BoardDining.all) return true;
  // 优先细分渠道 fulfillment_channel，回退 fulfillment_bucket
  return switch (dining) {
    BoardDining.dineIn => slice.channel == 'dine_in',
    BoardDining.takeout =>
      const {'takeout', 'delivery'}.contains(slice.channel),
    BoardDining.pack => const {'pack', 'pickup'}.contains(slice.channel),
    BoardDining.all => true,
  };
}

bool _matchesExtra(
    KdsV2LineSlice slice, BoardExtraFilter extra, Map<String, dynamic> config) {
  final raw = slice.raw;
  return switch (extra) {
    BoardExtraFilter.overdue => KdsLineWaitTime.isOverdue(
        raw,
        waitSeconds: slice.waitSecondsAt(DateTime.now().millisecondsSinceEpoch),
      ),
    BoardExtraFilter.rush =>
      raw['rushed'] == true || raw['order_rushed'] == true,
    BoardExtraFilter.addDish =>
      raw['add_dish'] == true || raw['is_add_dish'] == true,
    BoardExtraFilter.hold => raw['held'] == true,
  };
}

int _compareSlices(KdsV2LineSlice a, KdsV2LineSlice b, BoardSortMode mode,
    Map<String, dynamic> config) {
  // 催单强制置顶：无论处于何种排序模式（含默认 FIFO），催菜切片永远作为最高优先级排在首位
  final aRushed = a.raw['rushed'] == true || a.raw['order_rushed'] == true;
  final bRushed = b.raw['rushed'] == true || b.raw['order_rushed'] == true;
  if (aRushed != bRushed) {
    return bRushed ? 1 : -1;
  }

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final priority = switch (mode) {
    BoardSortMode.overdueFirst => (KdsLineWaitTime.isOverdue(
        b.raw,
        waitSeconds: b.waitSecondsAt(nowMs),
      )
              ? 1
              : 0)
          .compareTo(KdsLineWaitTime.isOverdue(
        a.raw,
        waitSeconds: a.waitSecondsAt(nowMs),
      )
              ? 1
              : 0),
    BoardSortMode.rushFirst => (b.raw['rushed'] == true ? 1 : 0)
        .compareTo(a.raw['rushed'] == true ? 1 : 0),
    BoardSortMode.fifo => 0,
  };
  if (priority != 0) return priority;
  final aCreated = (a.raw['created_at_ms'] as num?)?.toInt() ?? 0;
  final bCreated = (b.raw['created_at_ms'] as num?)?.toInt() ?? 0;
  final byCreated = aCreated.compareTo(bCreated);
  return byCreated != 0 ? byCreated : a.detailId.compareTo(b.detailId);
}

class KdsV2ThreeFlowBoard extends ConsumerStatefulWidget {
  const KdsV2ThreeFlowBoard({
    super.key,
    required this.state,
    required this.workflows,
    this.activeChannel = KdsActiveChannel.lan,
    this.wsConnected,
    this.statsLine,
    this.onRefresh,
    this.onSettings,
    this.onLogs,
    this.onInspector,
    this.onQueueTasks,
    this.onLogout,
    this.onChannelSwitch,
    this.fixedDishOrderEnabled = true,
    this.mergeSameDishNameEnabled = true,
    this.prepFlowEnabled = true,
    this.advanceQuantityDialogEnabled = false,
    this.cardScale = 1.0,
    this.onCardScalePersisted,
    this.addDishIndependentEnabled = false,
    this.refundAlerts,
    this.onDismissRefundAlert,
  });

  final bool addDishIndependentEnabled;
  final ValueNotifier<List<KdsRefundAlertItem>>? refundAlerts;
  final void Function(String id)? onDismissRefundAlert;

  final KdsV2State state;
  final List<KdsWorkflow> workflows;
  final KdsActiveChannel activeChannel;
  final bool? wsConnected;
  final String? statsLine;
  final VoidCallback? onRefresh;
  final VoidCallback? onSettings;

  /// 打开实时日志页（顶栏日志按钮 / WS 指示灯点击）
  final VoidCallback? onLogs;

  /// 打开全链路探测窗口
  final VoidCallback? onInspector;
  final VoidCallback? onQueueTasks;
  final VoidCallback? onLogout;
  final VoidCallback? onChannelSwitch;
  final bool fixedDishOrderEnabled;
  final bool mergeSameDishNameEnabled;
  final bool prepFlowEnabled;

  /// 划菜数量弹窗开关：true=单击卡片先选数量；false=单击整卡划出、长按选数量
  final bool advanceQuantityDialogEnabled;

  /// 卡片缩放（0.7–1.6）
  final double cardScale;

  /// 拖动结束后的持久化回调
  final ValueChanged<double>? onCardScalePersisted;

  @override
  ConsumerState<KdsV2ThreeFlowBoard> createState() =>
      _KdsV2ThreeFlowBoardState();
}

class _KdsV2ThreeFlowBoardState extends ConsumerState<KdsV2ThreeFlowBoard> {
  BoardQueue? _queue;
  BoardDining _dining = BoardDining.all;
  BoardExtraFilter? _extra;
  BoardSortMode _sortMode = BoardSortMode.fifo;
  bool _isDishView = true;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    // 访问审计：打开看板
    KdsFileLogger.info('[PAGE] 打开看板');
  }

  /// 拖动滑块过程中的实时值；null 时跟随 widget.cardScale（持久值）
  double? _cardScaleLive;

  double get _cardScale => _cardScaleLive ?? widget.cardScale;

  List<BoardQueue> get _visibleQueues {
    final configured = widget.state.config['visible_queues'];
    if (configured is List) {
      final allowed = configured.map((value) => '$value').toSet();
      final queues = BoardQueue.values
          .where((queue) => allowed.contains(queue.apiValue))
          .toList();
      return widget.prepFlowEnabled
          ? queues
          : queues.where((queue) => queue != BoardQueue.pendingPrep).toList();
    }
    // 断链恢复时 device/me 可能尚未同步回 workflows；只要已有本地快照，
    // 仍展示完整看板，不能因为权限元数据暂时为空而跳到“已完成”空页。
    final queues = widget.workflows.isEmpty
        ? BoardQueue.values.toList()
        : boardQueuesForWorkflows(widget.workflows);
    return widget.prepFlowEnabled
        ? queues
        : queues.where((queue) => queue != BoardQueue.pendingPrep).toList();
  }

  bool get _hasPrepQueue => _visibleQueues.contains(BoardQueue.pendingPrep);

  BoardQueue get _selectedQueue {
    final visible = _visibleQueues;
    if (visible.contains(_queue)) return _queue!;
    return visible.isNotEmpty ? visible.first : BoardQueue.done;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final selected = _selectedQueue;
    final fallbackPrep = !_hasPrepQueue;
    final shell = BoardShell(
      queue: selected,
      visibleQueues: _visibleQueues,
      queueCounts: _localQueueCounts(
        state,
        dining: _dining,
        extra: _extra,
        includePrepInCook: fallbackPrep,
        isDishView: _isDishView,
        fixedDishOrderEnabled: widget.fixedDishOrderEnabled,
        mergeSameDishNameEnabled: widget.mergeSameDishNameEnabled,
      ),
      dining: _dining,
      diningCounts: _diningCounts(
        state,
        selected,
        isDishView: _isDishView,
        fixedDishOrderEnabled: widget.fixedDishOrderEnabled,
        mergeSameDishNameEnabled: widget.mergeSameDishNameEnabled,
      ),
      isDishView: _isDishView,
      extra: _extra,
      extraCounts: _extraCounts(
        state,
        selected,
        dining: _dining,
        isDishView: _isDishView,
        fixedDishOrderEnabled: widget.fixedDishOrderEnabled,
        mergeSameDishNameEnabled: widget.mergeSameDishNameEnabled,
      ),
      sortMode: _sortMode,
      collapsed: _collapsed,
      wsConnected: widget.wsConnected ?? state.connected,
      activeChannel: widget.activeChannel,
      lastEventAtMs: state.lastEventAtMs,
      statsLine: widget.statsLine,
      onQueueChanged: (queue) {
        KdsFileLogger.info('[UI] 切换队列 → ${queue.label}');
        setState(() => _queue = queue);
      },
      onDiningChanged: (dining) {
        KdsFileLogger.info('[UI] 筛选就餐方式 → ${dining.label}');
        setState(() => _dining = dining);
      },
      onViewChanged: (dishView) {
        KdsFileLogger.info('[UI] 切换视图 → ${dishView ? '菜品' : '订单'}');
        setState(() => _isDishView = dishView);
      },
      onExtraSelected: (extra) {
        KdsFileLogger.info('[UI] 筛选额外项 → ${extra?.label ?? '全部'}');
        setState(() => _extra = extra);
      },
      onSortChanged: (sort) {
        KdsFileLogger.info('[UI] 排序方式 → ${sort.label}');
        setState(() => _sortMode = sort);
      },
      onCollapseToggle: () => setState(() => _collapsed = !_collapsed),
      cardScale: _cardScale,
      onCardScaleChanged: (scale) => setState(() => _cardScaleLive = scale),
      onCardScaleChangeEnd: (scale) {
        // 保留实时值，避免持久化读回前视觉回跳
        widget.onCardScalePersisted?.call(scale);
      },
      onRefresh: widget.onRefresh,
      onSettings: widget.onSettings,
      onLogs: widget.onLogs,
      onInspector: widget.onInspector,
      onQueueTasks: widget.onQueueTasks,
      pendingSyncCount: state.pendingSyncCount,
      onLogout: widget.onLogout,
      onChannelSwitch: widget.onChannelSwitch,
      body: _body(context, ref, state, selected),
    );
    // 划菜撤回提示条：从看板底部浮现的悬浮条（不遮挡顶部队列切换、
    // 筛选等交互；5s 倒计时结束自动消失）；无提示时组件为空不渲染。
    return Stack(
      children: [
        shell,
        const Positioned(
          left: 0,
          right: 0,
          bottom: 20,
          child: Center(child: _AdvanceUndoToast()),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, KdsV2State state,
      BoardQueue selected) {
    if (state.loading && state.lines.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null && state.lines.isEmpty) {
      return _EmptyState(
        icon: Icons.signal_wifi_connected_no_internet_4,
        title: '等待收银端快照',
        message: state.error!,
        onRetry: () => ref.read(kdsV2BoardProvider.notifier).refresh(),
      );
    }
    return Stack(
      children: [
        Column(
          children: [
            _RefundAlertBannerList(
              alertsNotifier: widget.refundAlerts,
              onDismiss: widget.onDismissRefundAlert,
            ),
            if (state.allChannelsUnavailable)
              Semantics(
                liveRegion: true,
                label: '云端和局域网均不可用，操作将安全保存在本机并等待网络恢复',
                child: Container(
                  key: const ValueKey('all-channels-offline-banner'),
                  width: double.infinity,
                  color: const Color(0xFFC62828),
                  padding:
                      const EdgeInsets.symmetric(vertical: 7, horizontal: 20),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_off_outlined,
                          size: 18, color: Colors.white),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '云端和局域网均不可用：划菜操作仍可继续，将安全保存在本机，网络恢复后自动同步',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.isStale)
              Semantics(
                liveRegion: true,
                label: '云端连接异常，当前展示缓存数据，操作将进入待确认队列',
                child: Container(
                  key: const ValueKey('stale-cloud-cache-banner'),
                  width: double.infinity,
                  color: KdsColors.rushGold,
                  padding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.cloud_off_outlined,
                        size: 18,
                        color: Colors.black87,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '云端暂不可达：正在展示 ${state.cacheAgeSeconds ?? 0} 秒前的缓存数据，操作将进入待确认队列',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.rejectedLineCount > 0)
              Container(
                width: double.infinity,
                color: const Color(0xffff9800),
                padding:
                    const EdgeInsets.symmetric(vertical: 7, horizontal: 20),
                child: Text(
                  '数据告警：发现 ${state.rejectedLineCount} 条无效菜品数据，已隔离；请联系管理员检查订单映射。',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Expanded(
              child: KdsV2QueueColumn(
                key: ValueKey('queue-board-${selected.apiValue}'),
                queue: selected.apiValue,
                label: selected.label,
                state: state,
                dining: _dining,
                extra: _extra,
                sortMode: _sortMode,
                isDishView: _isDishView,
                fixedDishOrderEnabled: widget.fixedDishOrderEnabled,
                mergeSameDishNameEnabled: widget.mergeSameDishNameEnabled,
                advanceQuantityDialogEnabled:
                    widget.advanceQuantityDialogEnabled,
                cardScale: _cardScale,
                includePrep: !_hasPrepQueue,
                addDishIndependentEnabled: widget.addDishIndependentEnabled,
              ),
            ),
          ],
        ),
        if (state.pendingSyncCount > 0)
          Positioned(
            right: 16,
            bottom: 16,
            child: _PendingSyncFloatingIndicator(
              count: state.pendingSyncCount,
              waitingForNetwork: state.allChannelsUnavailable || state.isStale,
            ),
          ),
      ],
    );
  }

  Map<String, int> _diningCounts(
    KdsV2State state,
    BoardQueue queue, {
    bool isDishView = true,
    bool fixedDishOrderEnabled = true,
    bool mergeSameDishNameEnabled = true,
  }) {
    final result = <String, int>{};
    final slicesByDining = <String, List<KdsV2LineSlice>>{};
    for (final slice in _slicesForQueue(state, queue.apiValue,
        includePrep: !_hasPrepQueue)) {
      // 与筛选口径一致：优先 fulfillment_channel 细分渠道，
      // 计数归并到筛选项键（pickup→pack、delivery→takeout）
      final key = _diningCountKey(slice.channel);
      slicesByDining.putIfAbsent(key, () => []).add(slice);
    }
    for (final entry in slicesByDining.entries) {
      final count = countBoardSlices(
        slices: entry.value,
        isDishView: isDishView,
        isDone: queue == BoardQueue.done,
        fixedDishOrderEnabled: fixedDishOrderEnabled,
        mergeSameDishNameEnabled: mergeSameDishNameEnabled,
      );
      if (count > 0) {
        result[entry.key] = count;
      }
    }
    return result;
  }

  Map<String, int> _extraCounts(
    KdsV2State state,
    BoardQueue queue, {
    BoardDining dining = BoardDining.all,
    bool isDishView = true,
    bool fixedDishOrderEnabled = true,
    bool mergeSameDishNameEnabled = true,
  }) {
    final result = <String, int>{};
    final slices = _slicesForQueue(state, queue.apiValue,
            includePrep: !_hasPrepQueue)
        .where((slice) => _matchesDining(slice, dining));
    for (final filter in BoardExtraFilter.values) {
      final matching =
          slices.where((s) => _matchesExtra(s, filter, state.config));
      final count = countBoardSlices(
        slices: matching,
        isDishView: isDishView,
        isDone: queue == BoardQueue.done,
        fixedDishOrderEnabled: fixedDishOrderEnabled,
        mergeSameDishNameEnabled: mergeSameDishNameEnabled,
      );
      if (count > 0) {
        result[filter.apiValue] = count;
      }
    }
    return result;
  }
}

class _PendingSyncFloatingIndicator extends StatelessWidget {
  const _PendingSyncFloatingIndicator({
    required this.count,
    required this.waitingForNetwork,
  });

  final int count;
  final bool waitingForNetwork;

  @override
  Widget build(BuildContext context) {
    final label = waitingForNetwork ? '$count 项待恢复同步' : '正在同步 $count 项';
    return Semantics(
      liveRegion: true,
      label: label,
      child: IgnorePointer(
        child: Material(
          key: const ValueKey('pending-sync-floating-indicator'),
          color: KdsColors.topBarBg,
          elevation: 6,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  waitingForNetwork
                      ? Icons.cloud_off_outlined
                      : Icons.cloud_upload_outlined,
                  size: 17,
                  color: waitingForNetwork
                      ? KdsColors.rushGold
                      : KdsColors.wsOnline,
                ),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: const TextStyle(
                    color: KdsColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class KdsV2QueueColumn extends ConsumerWidget {
  const KdsV2QueueColumn({
    super.key,
    required this.queue,
    required this.label,
    required this.state,
    this.dining = BoardDining.all,
    this.extra,
    this.sortMode = BoardSortMode.fifo,
    this.isDishView = true,
    this.fixedDishOrderEnabled = true,
    this.mergeSameDishNameEnabled = true,
    this.advanceQuantityDialogEnabled = false,
    this.cardScale = 1.0,
    this.includePrep = false,
    this.addDishIndependentEnabled = false,
  });
  final bool addDishIndependentEnabled;
  final String queue;
  final String label;
  final KdsV2State state;
  final BoardDining dining;
  final BoardExtraFilter? extra;
  final BoardSortMode sortMode;
  final bool isDishView;
  final bool fixedDishOrderEnabled;
  final bool mergeSameDishNameEnabled;
  final bool advanceQuantityDialogEnabled;
  final bool includePrep;

  /// 卡片缩放因子（0.7–1.6），1.0 为默认尺寸
  final double cardScale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = _slicesForQueue(state, queue, includePrep: includePrep)
        .where((slice) => _matchesDining(slice, dining))
        .where((slice) =>
            extra == null || _matchesExtra(slice, extra!, state.config))
        .toList()
      ..sort((a, b) => _compareSlices(a, b, sortMode, state.config));
    if (queue == 'done') lines.sort(compareCompletedSlices);
    final groups = <String, List<KdsV2LineSlice>>{};
    final cards = <Widget>[];
    final allowed = _allowedCommands(state.config, queue);
    final isDone = queue == 'done';
    final isFiltered = dining != BoardDining.all || extra != null;
    // 已完成必须以最近一次划菜时间倒序展示。固定菜位会把 catalog
    // 顺序重新套回去，掩盖该时间顺序，因此只在进行中队列使用固定菜位。
    if (isDishView && fixedDishOrderEnabled && !isDone) {
      for (final line in lines) {
        groups.putIfAbsent(line.mergeKey, () => []).add(line);
      }
      {
        for (final item in [...state.catalog]..sort(compareKdsCatalogItems)) {
          final key = '${item.dishId}:dine_in';
          final active = groups.remove(key);
          if (active != null) {
            cards.add(_DishGroupCard(
              key: ValueKey('active-$queue-$key'),
              lines: active,
              enabled: state.canMutate,
              allowedCommands: allowed,
              advanceQuantityDialogEnabled: advanceQuantityDialogEnabled,
              cardScale: cardScale,
              isDone: isDone,
              dining: dining,
              extra: extra,
            ));
          } else if (!isFiltered) {
            cards.add(_PlaceholderCard(
              key: ValueKey('placeholder-$queue-$key'),
              item: item,
            ));
          }
          final channelKeys = groups.keys
              .where((groupKey) => groupKey.startsWith('${item.dishId}:'))
              .toList()
            ..sort();
          for (final channelKey in channelKeys) {
            cards.add(_DishGroupCard(
              key: ValueKey('active-$queue-$channelKey'),
              lines: groups.remove(channelKey)!,
              enabled: state.canMutate,
              allowedCommands: allowed,
              advanceQuantityDialogEnabled: advanceQuantityDialogEnabled,
              cardScale: cardScale,
              isDone: isDone,
              dining: dining,
              extra: extra,
            ));
          }
        }
      }
      final unmatched = groups.entries.toList()
        ..sort((a, b) {
          final byDish = a.value.first.dishId.compareTo(b.value.first.dishId);
          return byDish != 0 ? byDish : a.key.compareTo(b.key);
        });
      for (final entry in unmatched) {
        cards.add(_DishGroupCard(
          key: ValueKey('active-$queue-${entry.key}'),
          lines: entry.value,
          enabled: state.canMutate,
          allowedCommands: allowed,
          advanceQuantityDialogEnabled: advanceQuantityDialogEnabled,
          cardScale: cardScale,
          isDone: isDone,
          dining: dining,
          extra: extra,
        ));
      }
    } else if (isDishView) {
      // 已完成页必须保留每一次划菜记录的独立卡片，即使当前启用了同名合并。
      // 合并会把上一轮和本轮完成的同名菜折叠到一起，操作员无法追溯最近一轮。
      if (mergeSameDishNameEnabled && !isDone) {
        for (final line in lines) {
          groups.putIfAbsent(dishNameMergeKey(line), () => []).add(line);
        }
        for (final entry in groups.entries) {
          cards.add(_DishGroupCard(
            key: ValueKey('detail-group-$queue-${entry.key}'),
            lines: entry.value,
            enabled: state.canMutate,
            allowedCommands: allowed,
            advanceQuantityDialogEnabled: advanceQuantityDialogEnabled,
            cardScale: cardScale,
            isDone: isDone,
            mergeByName: true,
            dining: dining,
            extra: extra,
          ));
        }
      } else {
        for (final line in lines) {
          cards.add(_DishGroupCard(
            key: ValueKey('detail-card-$queue-${line.detailId}'),
            lines: [line],
            enabled: state.canMutate,
            allowedCommands: allowed,
            advanceQuantityDialogEnabled: advanceQuantityDialogEnabled,
            cardScale: cardScale,
            isDone: isDone,
            dining: dining,
            extra: extra,
          ));
        }
      }
    } else {
      // 订单视图：内容驱动高度，走最矮列优先的瀑布流（下方单独构建）
      final addDishSplit = addDishIndependentEnabled;
      final orders = <String, List<KdsV2LineSlice>>{};
      for (final line in lines) {
        final isAdd =
            line.raw['add_dish'] == true || line.raw['is_add_dish'] == true;
        final groupKey = (addDishSplit && isAdd)
            ? '${line.orderId}:add_dish'
            : '${line.orderId}';
        orders.putIfAbsent(groupKey, () => []).add(line);
      }
      if (orders.isEmpty) {
        return const Center(
          child: Text('暂无任务', style: TextStyle(color: KdsColors.textMuted)),
        );
      }
      return _buildOrderMasonry(orders, state, allowed);
    }
    if (cards.isEmpty) {
      return const Center(
        child: Text('暂无任务', style: TextStyle(color: KdsColors.textMuted)),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final scale = cardScale.clamp(0.7, 1.6);
      final columns =
          (constraints.maxWidth / (310 * scale)).floor().clamp(1, 8);
      return GridView.builder(
        padding: const EdgeInsets.all(10),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: KdsSpacing.cardHeight * scale,
        ),
        itemCount: cards.length,
        itemBuilder: (context, index) =>
            _ScaledCard(scale: scale, child: cards[index]),
      );
    });
  }

  /// 订单视图瀑布流：卡片高度由菜品行数内容驱动，最矮列优先保持均衡
  Widget _buildOrderMasonry(
    Map<String, List<KdsV2LineSlice>> orders,
    KdsV2State state,
    Set<KdsV2CommandType> allowed,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      final scale = cardScale.clamp(0.7, 1.6);
      final columns =
          (constraints.maxWidth / (310 * scale)).floor().clamp(1, 8);
      final columnCards = List.generate(columns, (_) => <Widget>[]);
      final columnHeights = List.filled(columns, 0.0);
      for (final entry in orders.entries) {
        final firstLine = entry.value.first;
        final rawOrderId =
            int.tryParse(entry.key.split(':').first) ?? firstLine.orderId;
        final isAddGroup = entry.key.endsWith(':add_dish');
        var details = projectOrderDetails(
          lines: state.lines,
          orderDetails: state.orderDetails,
          orderId: rawOrderId,
          currentQueue: queue,
          includePrep: includePrep,
        );
        if (isAddGroup) {
          details = details
              .where((d) =>
                  d.raw['add_dish'] == true || d.raw['is_add_dish'] == true)
              .toList();
        } else if (addDishIndependentEnabled) {
          details = details
              .where((d) =>
                  d.raw['add_dish'] != true && d.raw['is_add_dish'] != true)
              .toList();
        }
        final card = _OrderGroupCard(
          key: ValueKey('order-card-${entry.key}'),
          lines: entry.value,
          queue: queue,
          orderDetails: details,
          enabled: state.canMutate,
          allowedCommands: allowed,
          advanceQuantityDialogEnabled: advanceQuantityDialogEnabled,
          cardScale: scale,
          includePrep: includePrep,
        );
        var target = 0;
        for (var i = 1; i < columns; i++) {
          if (columnHeights[i] < columnHeights[target]) target = i;
        }
        columnCards[target].add(card);
        columnHeights[target] +=
            _estimateOrderCardHeight(details.length, scale) + 10;
      }
      return SingleChildScrollView(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var columnIndex = 0;
                columnIndex < columnCards.length;
                columnIndex++) ...[
              // 列间水平间距，卡片不贴在一起
              if (columnIndex > 0) const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final card in columnCards[columnIndex])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: card,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  /// 订单卡高度估算（用于瀑布流列均衡）：头部 + 标签进度行 +
  /// 行子卡（超 8 行封顶）+ 底部收尾 + 内边距
  double _estimateOrderCardHeight(int lineCount, double scale) {
    final visibleLines = lineCount > 8 ? 8 : lineCount;
    return (66 + 34 + visibleLines * 72 + 34 + 16) * scale;
  }
}

Set<KdsV2CommandType> _allowedCommands(
    Map<String, dynamic> config, String queue) {
  final raw = config['allowed_commands'];
  if (raw is List) {
    final names = raw.map((e) => '$e').toSet();
    return KdsV2CommandType.values
        .where((command) => names.contains(command.wireName))
        .toSet();
  }
  return const {};
}

/// 按缩放因子整体缩放卡片（文字/标签/按钮/热区同比例）。
/// 关键：用 OverflowBox 打破网格格子的紧约束，让卡片先按
/// 格子÷scale 的逻辑尺寸布局，再从左上角精确缩回格子大小——
/// 否则 SizedBox 会被钳回格子尺寸，导致内容被二次缩小。
class _ScaledCard extends StatelessWidget {
  const _ScaledCard({required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth / scale;
        final height = constraints.maxHeight / scale;
        return OverflowBox(
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          alignment: Alignment.topLeft,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(width: width, height: height, child: child),
          ),
        );
      },
    );
  }
}

class _OrderGroupCard extends ConsumerWidget {
  const _OrderGroupCard({
    super.key,
    required this.lines,
    required this.enabled,
    required this.allowedCommands,
    required this.orderDetails,
    this.queue = '',
    this.advanceQuantityDialogEnabled = false,
    this.cardScale = 1.0,
    this.includePrep = false,
  });

  final List<KdsV2LineSlice> lines;
  final bool enabled;
  final Set<KdsV2CommandType> allowedCommands;
  final List<KdsV2OrderDisplayLine> orderDetails;

  /// 当前队列（决定整单推进按钮文案）
  final String queue;

  /// 划菜数量弹窗开关（行级推进与菜品维度一致）
  final bool advanceQuantityDialogEnabled;

  /// 卡片缩放因子
  final double cardScale;

  /// 无待配菜队列时将待配菜合并进待制作推进
  final bool includePrep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = lines.first;
    var table = orderHeaderLabel(first, lines);
    final isPureAddGroup = lines.every((line) =>
        line.raw['add_dish'] == true || line.raw['is_add_dish'] == true);
    if (isPureAddGroup && !table.contains('加单')) {
      table = '$table (加单)';
    }
    final isDoneQueue = queue == 'done';
    final canAdvance = !isDoneQueue &&
        enabled &&
        lines.any((line) => line.raw['held'] != true) &&
        allowedCommands.contains(KdsV2CommandType.advanceOrder);
    final anyHeld = lines.any((line) => line.raw['held'] == true);
    final anyAddDish = lines.any((line) =>
        line.raw['add_dish'] == true || line.raw['is_add_dish'] == true);
    final orderRushed = first.raw['rushed'] == true ||
        first.raw['order_rushed'] == true ||
        orderDetails.any((detail) => detail.orderRushed);
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final anyOverdue = lines.any((line) => KdsLineWaitTime.isOverdue(
          line.raw,
          waitSeconds: line.waitSecondsAt(nowMs),
        ));
    final channel = first.channel;
    final anyCombo = lines.any((line) => _isComboRaw(line.raw));
    final channelTag = switch (channel) {
      'pickup' => '自',
      'pack' => '打',
      'takeout' || 'delivery' => '外',
      _ => null,
    };
    final actionLabel = switch (queue) {
      'pending_prep' => '整单配菜',
      'pending_cook' => '整单制作',
      'ready_serve' => '整单传菜',
      _ => '整单推进',
    };

    // 进行中：未划菜在上、其余灰色删除线沉底，组内 FIFO。
    // 已完成：当前 done 明细按最近一次划菜时间倒序，避免旧菜压在新菜上。
    final sorted = [...orderDetails]..sort((a, b) {
        final aDone = a.isInCurrentQueue ? 0 : 1;
        final bDone = b.isInCurrentQueue ? 0 : 1;
        if (aDone != bDone) return aDone.compareTo(bDone);
        if (isDoneQueue) {
          final byCompletion =
              completedAtMs(b.raw).compareTo(completedAtMs(a.raw));
          if (byCompletion != 0) return byCompletion;
        }
        final byCreated = (a.createdAtMs ?? 0).compareTo(b.createdAtMs ?? 0);
        return byCreated != 0 ? byCreated : a.detailId.compareTo(b.detailId);
      });

    final totalActive =
        sorted.fold<int>(0, (sum, line) => sum + line.activeQuantity);
    final doneCount = sorted.fold<int>(
        0,
        (sum, line) =>
            sum +
            (line.activeQuantity - line.remainingQuantity).clamp(0, 1 << 31));

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: KdsColors.cardBody,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KdsSpacing.cardOuterRadius)),
      child: Tooltip(
        message: isDoneQueue
            ? '已完成订单'
            : (canAdvance ? '点击卡片$actionLabel' : '当前不可推进'),
        child: Semantics(
          button: true,
          enabled: canAdvance,
          label: isDoneQueue ? '已完成，$table' : '$actionLabel，$table',
          child: InkWell(
            key: ValueKey('order-advance-${first.orderId}'),
            onTap: canAdvance ? () => _advanceOrder(context, ref, first) : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // 内容驱动高度：卡片长度随菜品行数自适应
              mainAxisSize: MainAxisSize.min,
              children: [
                // 头部配色：已完成页面统一深灰；未完成页面按紧急程度分色
                Container(
                  height: KdsSpacing.cardHeaderHeight,
                  color: isDoneQueue
                      ? KdsColors.headerDefault
                      : kdsCardHeaderColor(
                          overdue: anyOverdue,
                          rushed: orderRushed,
                          held: anyHeld,
                          addDish: anyAddDish,
                          combo: anyCombo,
                          channel: channel,
                        ),
                  padding: const EdgeInsets.only(
                    left: KdsCardDesign.headerLabelLeft,
                    right: KdsCardDesign.headerDetailRight,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(table,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KdsTypography.cardHeaderLabel
                                  .copyWith(color: Colors.white)),
                        ),
                      ),
                      if (!isDoneQueue && anyHeld && enabled) ...[
                        _OrderAdvancePill(
                          label: '起菜',
                          enabled: true,
                          onTap: () => _releaseHeldOrder(context, ref),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (!isDoneQueue)
                        _OrderAdvancePill(
                          label: actionLabel,
                          enabled: canAdvance,
                          onTap: () => _advanceOrder(context, ref, first),
                        ),
                      if (isDoneQueue &&
                          enabled &&
                          allowedCommands
                              .contains(KdsV2CommandType.revokeItem)) ...[
                        const SizedBox(width: 8),
                        _OrderRevokePill(
                          enabled: enabled,
                          onTap: () => _revokeOrder(context, ref),
                        ),
                      ],
                    ],
                  ),
                ),
                // 标签 + 传菜进度
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Row(
                    children: [
                      if (channelTag != null) ...[
                        _MiniTag(
                            label: channelTag, color: KdsColors.headerTakeout),
                        const SizedBox(width: 6),
                      ],
                      if (!isDoneQueue && anyAddDish) ...[
                        const _MiniTag(
                            label: '加', color: KdsColors.headerAddDish),
                        const SizedBox(width: 6),
                      ],
                      if (!isDoneQueue && orderRushed) ...[
                        const _MiniTag(label: '催', color: KdsColors.rushGold),
                        const SizedBox(width: 6),
                      ],
                      if (!isDoneQueue && anyOverdue) ...[
                        const _MiniTag(
                            label: '超', color: KdsColors.headerOverdue),
                        const SizedBox(width: 6),
                      ],
                      if (!isDoneQueue && anyHeld) ...[
                        const _MiniTag(
                            label: '等叫', color: Color(0xFF8B5CF6)),
                        const SizedBox(width: 6),
                      ],
                      const Spacer(),
                      Text(
                        '已传$doneCount/$totalActive',
                        style: const TextStyle(
                          color: KdsColors.waitMuted,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                // 逐行子卡（内容驱动高度；超过 8 行时内部滚动防霸屏）
                if (sorted.length <= 8)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                    child: Column(
                      children: [
                        for (var index = 0; index < sorted.length; index++)
                          _OrderLineCard(
                            index: index,
                            line: sorted[index],
                            nowMs: nowMs,
                            scale: cardScale,
                            advanceable: _canAdvanceLine(sorted[index]),
                            isDoneQueue: isDoneQueue,
                            onTap: () => _tapLine(
                              context,
                              ref,
                              sorted[index],
                              _lineSlices(sorted[index]),
                            ),
                            onLongPress: () => _longPressLine(
                              context,
                              ref,
                              sorted[index],
                              _lineSlices(sorted[index]),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 8 * 72 * cardScale,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                      itemCount: sorted.length,
                      itemBuilder: (context, index) => _OrderLineCard(
                        index: index,
                        line: sorted[index],
                        nowMs: nowMs,
                        scale: cardScale,
                        advanceable: _canAdvanceLine(sorted[index]),
                        onTap: () => _tapLine(
                          context,
                          ref,
                          sorted[index],
                          _lineSlices(sorted[index]),
                        ),
                        onLongPress: () => _longPressLine(
                          context,
                          ref,
                          sorted[index],
                          _lineSlices(sorted[index]),
                        ),
                      ),
                    ),
                  ),
                // 底部收尾
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Center(
                    child: Text(
                      '—— 顾客就点了这些 ——',
                      style: TextStyle(
                        color: KdsColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<KdsV2LineSlice> _lineSlices(KdsV2OrderDisplayLine line) => lines
      .where((slice) => slice.detailId == line.detailId && slice.quantity > 0)
      .toList(growable: false);

  Future<void> _releaseHeldOrder(BuildContext context, WidgetRef ref) async {
    final heldSlices = lines.where((s) => s.raw['held'] == true).toList();
    if (heldSlices.isEmpty) return;
    try {
      HapticFeedback.lightImpact();
      final notifier = ref.read(kdsV2BoardProvider.notifier);
      for (final slice in heldSlices) {
        await notifier.send(
          type: KdsV2CommandType.releaseItem,
          target: KdsV2CommandTarget(
            detailId: slice.detailId,
            fromQueue: slice.queue,
          ),
          expectedRevision: slice.revision,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('整单等叫菜品已起菜进入制作'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showKdsAdvanceFailureNotice(context, e, action: '整单起菜');
      }
    }
  }

  Future<void> _advanceOrder(
      BuildContext context, WidgetRef ref, KdsV2LineSlice first) async {
    try {
      unawaited(SystemSound.play(SystemSoundType.click).catchError((_) {}));
      HapticFeedback.lightImpact();

      // 整单推进 = 逐明细推进：只推流程仍停留在当前队列的行，
      // 已进入其他队列（如待传菜）的行不受影响，严格单一流程。
      final advanced =
          await ref.read(kdsV2BoardProvider.notifier).advanceOrderLines(
                orderId: first.orderId,
                fromQueue: first.queue,
                includePrep: includePrep,
              );

      // 推进成功的反馈由顶部 5s 撤回弹窗承担；这里只提示无可推进的边界情况。
      if (context.mounted && advanced == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('该单当前队列无可推进菜品'),
            duration: Duration(milliseconds: 2000),
            behavior: SnackBarBehavior.floating,
            width: 300,
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showKdsAdvanceFailureNotice(context, error, action: '整单推进');
      }
    }
  }

  /// 已完成整单回撤：把本单所有已完成明细退回上一步（落点由收银端决定）。
  Future<void> _revokeOrder(BuildContext context, WidgetRef ref) async {
    final doneSlices = lines
        .where((slice) => slice.queue == 'done' && slice.quantity > 0)
        .toList();
    if (doneSlices.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => AlertDialog(
        title: const Text('回撤整单？'),
        content: Text('将把本单 ${doneSlices.length} 项已完成菜品退回上一流程（待制作/待传菜）。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('回撤', style: TextStyle(color: Color(0xFFCB0B0E))),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final notifier = ref.read(kdsV2BoardProvider.notifier);
      var sent = 0;
      for (final slice in doneSlices) {
        await notifier.send(
          type: KdsV2CommandType.revokeItem,
          target: KdsV2CommandTarget(
            detailId: slice.detailId,
            fromQueue: slice.queue,
          ),
          quantity: slice.quantity,
          expectedRevision: slice.revision,
        );
        sent++;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('已回撤 $sent 项，退回上一流程'),
            duration: const Duration(milliseconds: 2000),
            behavior: SnackBarBehavior.floating,
            width: 320,
          ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('回撤失败：${friendlyCommandError(error)}')),
        );
      }
    }
  }

  /// 行级推进与菜品维度同规则：在当前队列、有权威 revision、
  /// 服务端允许 advanceItem 时才可点
  bool _canAdvanceLine(KdsV2OrderDisplayLine line) {
    final isRefunded =
        line.raw['line_status'] == 'refunded' || line.raw['status'] == 'refunded';
    if (isRefunded) return false;
    return enabled &&
        line.isInCurrentQueue &&
        line.revision != null &&
        allowedCommands.contains(KdsV2CommandType.advanceItem);
  }

  /// 单击行：开关开→弹数量弹窗；开关关→直接推进整行
  Future<void> _tapLine(BuildContext context, WidgetRef ref,
      KdsV2OrderDisplayLine line, List<KdsV2LineSlice> slices) async {
    final isRefunded =
        line.raw['line_status'] == 'refunded' || line.raw['status'] == 'refunded';
    if (isRefunded) return;
    if (line.raw['held'] == true) {
      showKdsHoldBlockedNotice(context);
      return;
    }
    if (!_canAdvanceLine(line)) return;
    if (advanceQuantityDialogEnabled && line.currentQueueQuantity > 1) {
      await _advanceLineWithDialog(context, ref, line, slices);
    } else {
      await _advanceLine(context, ref, line, slices: slices);
    }
  }

  /// 长按行：始终弹数量弹窗（多于 1 份时）
  Future<void> _longPressLine(BuildContext context, WidgetRef ref,
      KdsV2OrderDisplayLine line, List<KdsV2LineSlice> slices) async {
    final isRefunded =
        line.raw['line_status'] == 'refunded' || line.raw['status'] == 'refunded';
    if (isRefunded) return;
    if (line.raw['held'] == true) {
      showKdsHoldBlockedNotice(context);
      return;
    }
    if (!_canAdvanceLine(line) || line.currentQueueQuantity <= 1) return;
    await _advanceLineWithDialog(context, ref, line, slices);
  }

  Future<void> _advanceLineWithDialog(BuildContext context, WidgetRef ref,
      KdsV2OrderDisplayLine line, List<KdsV2LineSlice> slices) async {
    final count = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _QuantitySelectDialog(
        dishName: line.dishName,
        unit: line.unit,
        totalCount: line.currentQueueQuantity,
      ),
    );
    if (count != null && count > 0 && context.mounted) {
      await _advanceLine(context, ref, line, slices: slices, count: count);
    }
  }

  Future<void> _advanceLine(
    BuildContext context,
    WidgetRef ref,
    KdsV2OrderDisplayLine line, {
    List<KdsV2LineSlice> slices = const [],
    int? count,
  }) async {
    if (line.raw['held'] == true) {
      showKdsHoldBlockedNotice(context);
      return;
    }
    try {
      unawaited(SystemSound.play(SystemSoundType.click).catchError((_) {}));
      HapticFeedback.lightImpact();

      final targets = slices.isEmpty
          ? <(String, int)>[(queue, count ?? line.currentQueueQuantity)]
          : _allocateAdvanceQuantities(slices, count);
      for (final (fromQueue, quantity) in targets) {
        if (quantity <= 0) continue;
        await ref.read(kdsV2BoardProvider.notifier).send(
              type: KdsV2CommandType.advanceItem,
              target: KdsV2CommandTarget(
                detailId: line.detailId,
                fromQueue: fromQueue,
              ),
              quantity: quantity,
              expectedRevision: line.revision,
            );
      }

      // 成功反馈由顶部 5s 撤回弹窗承担（服务端确认后弹出）。
    } catch (error) {
      if (context.mounted) {
        showKdsAdvanceFailureNotice(context, error, action: '划菜');
      }
    }
  }

  List<(String, int)> _allocateAdvanceQuantities(
      List<KdsV2LineSlice> slices, int? requested) {
    var remaining = requested ??
        slices.fold<int>(0, (total, slice) => total + slice.quantity);
    final result = <(String, int)>[];
    for (final slice in slices) {
      if (remaining <= 0) break;
      final quantity = remaining.clamp(0, slice.quantity);
      result.add((slice.queue, quantity));
      remaining -= quantity;
    }
    return result;
  }
}

class _DishGroupCard extends ConsumerWidget {
  const _DishGroupCard({
    super.key,
    required this.lines,
    required this.enabled,
    required this.allowedCommands,
    this.advanceQuantityDialogEnabled = false,
    this.cardScale = 1.0,
    this.isDone = false,
    this.mergeByName = false,
    this.dining = BoardDining.all,
    this.extra,
  });
  final List<KdsV2LineSlice> lines;
  final bool enabled;
  final Set<KdsV2CommandType> allowedCommands;

  /// true：单击卡片先弹数量选择；false：单击整卡划出、长按选数量
  final bool advanceQuantityDialogEnabled;

  /// 卡片缩放因子，透传给明细弹窗保持两处卡片尺寸一致
  final double cardScale;

  /// 已完成页面标识（统一灰色、时间显示完成时间）
  final bool isDone;
  final bool mergeByName;
  final BoardDining dining;
  final BoardExtraFilter? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final first = lines.first;
    final total = lines.fold<int>(0, (sum, line) => sum + line.quantity);
    final tables = lines
        .map((line) => lineTableOrPickupCode(line, lines))
        .toSet()
        .join('、');
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final maxWait = lines
        .map((line) => line.waitSecondsAt(nowMs))
        .fold<int>(0, (a, b) => a > b ? a : b);
    // 规格统一走 KdsSpecText 解析：JSON 规格（如 {"辣度":"微辣"}）只显示值，
    // 同组多桌的不同做法合并去重展示，避免只看见第一桌的做法。
    final spec = KdsSpecText.display(
      lines: [for (final line in lines) line.raw],
    );
    final remark = '${first.raw['remark'] ?? ''}'.trim();
    final isAddDish = lines.any((line) =>
        line.raw['add_dish'] == true || line.raw['is_add_dish'] == true);
    final isRushed = lines.any((line) => line.raw['rushed'] == true);
    final isCombo = lines.any((line) => _isComboRaw(line.raw));
    final isHeld = lines.any((line) => line.raw['held'] == true);
    final isOverdue = lines.any((line) => KdsLineWaitTime.isOverdue(
          line.raw,
          waitSeconds: line.waitSecondsAt(nowMs),
        ));
    final overlayStatus =
        lines.firstWhereOrNull((l) => l.overlayStatus != null)?.overlayStatus;
    final tags = isDone
        ? _dishTags(
            addDish: false,
            rushed: false,
            combo: isCombo,
            overdue: false,
            fulfillmentBucket: first.channel,
            held: false,
          )
        : _dishTags(
            addDish: isAddDish,
            rushed: isRushed,
            combo: isCombo,
            overdue: isOverdue,
            fulfillmentBucket: first.channel,
            held: isHeld,
          );
    final canAdvance = !isDone &&
        enabled &&
        !lines.any((line) => line.raw['held'] == true) &&
        allowedCommands.contains(KdsV2CommandType.advanceItem);
    final tapHint = isDone
        ? '已完成'
        : (isHeld
            ? '等叫中（请先起菜）'
            : (!canAdvance
                ? '当前不可划菜'
                : (advanceQuantityDialogEnabled && total > 1)
                    ? '点击选择划出数量 (共$total份)'
                    : (total > 1 ? '点击整卡划菜，长按选择数量 (共$total份)' : '整卡划菜 (1份)')));
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: KdsColors.cardBody,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KdsSpacing.cardOuterRadius)),
      child: Tooltip(
        message: tapHint,
        child: Semantics(
          button: true,
          enabled: canAdvance,
          label: isDone
              ? '已完成，共$total${first.raw['unit'] ?? '份'}'
              : '划菜，共$total${first.raw['unit'] ?? '份'}',
          child: InkWell(
            key: ValueKey(
                'dish-group-advance-${mergeByName ? dishNameMergeKey(first) : first.mergeKey}'),
            onTap: !isDone
                ? () {
                    if (isHeld) {
                      showKdsHoldBlockedNotice(context);
                      return;
                    }
                    if (!canAdvance) return;
                    if (advanceQuantityDialogEnabled && total > 1) {
                      _showQuantityDialog(context, ref, total);
                    } else {
                      _advanceGroup(context, ref);
                    }
                  }
                : null,
            onLongPress: !isDone && total > 1
                ? () {
                    if (isHeld) {
                      showKdsHoldBlockedNotice(context);
                      return;
                    }
                    if (canAdvance) {
                      _showQuantityDialog(context, ref, total);
                    }
                  }
                : null,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: KdsSpacing.cardHeaderHeight,
                    // 头部配色：已完成页面统一深灰；未完成页面：超时/催菜红、加菜蓝、自提/外卖绿、等叫紫
                    color: isDone
                        ? KdsColors.headerDefault
                        : kdsCardHeaderColor(
                            overdue: isOverdue,
                            rushed: isRushed,
                            held: isHeld,
                            addDish: isAddDish,
                            combo: isCombo,
                            channel: first.channel,
                          ),
                    padding: const EdgeInsets.only(
                      left: KdsCardDesign.headerLabelLeft,
                      right: KdsCardDesign.headerDetailRight,
                    ),
                    child: Row(children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            tables,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KdsTypography.cardHeaderLabel
                                .copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                      if (overlayStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              overlayStatus.label,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      if (!isDone && isHeld && enabled)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: TextButton(
                            onPressed: () => _quickReleaseGroup(context, ref),
                            style: TextButton.styleFrom(
                              backgroundColor: Colors.white24,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              minimumSize: const Size(0, 28),
                            ),
                            child: const Text(
                              '起菜',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      if (isDone &&
                          enabled &&
                          allowedCommands.contains(KdsV2CommandType.revokeItem))
                        TextButton(
                          onPressed: () => _revokeGroup(context, ref),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFFFC107),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            minimumSize: const Size(0, KdsSpacing.minTouch),
                          ),
                          child: Text(
                            '回撤',
                            style: KdsTypography.cardDetailLink.copyWith(
                              color: const Color(0xFFFFC107),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      TextButton(
                        onPressed: () => _showDetails(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, KdsSpacing.minTouch),
                        ),
                        child: Text(
                          '详情>',
                          style: KdsTypography.cardDetailLink.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned(
                          left: KdsCardDesign.dishNameRowLeft,
                          right: KdsCardDesign.footerRight,
                          top: KdsCardDesign.dishNameRowTop -
                              KdsSpacing.cardHeaderHeight,
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (var tagIndex = 0;
                                    tagIndex < tags.length;
                                    tagIndex++) ...[
                                  if (tagIndex > 0)
                                    const SizedBox(
                                        width: KdsSpacing.cardTagGap),
                                  tags[tagIndex],
                                ],
                                if (tags.isNotEmpty)
                                  const SizedBox(
                                      width: KdsSpacing.cardTagToNameGap),
                                Expanded(
                                  child: Text(
                                    first.dishName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: KdsTypography.cardDishName,
                                  ),
                                ),
                              ]),
                        ),
                        Positioned(
                          left: KdsCardDesign.specLeft,
                          right: KdsCardDesign.footerRight,
                          top: KdsCardDesign.specTop -
                              KdsSpacing.cardHeaderHeight,
                          child: Text(
                            '做法：${spec ?? '默认'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            // 做法红色加粗凸显，防止厨房强光/远距离下看不清；
                            // 无做法（默认）时保持普通样式，避免满屏红。
                            style: spec == null
                                ? KdsTypography.cardRemark
                                : KdsTypography.cardRemark.copyWith(
                                    color: isDone
                                        ? KdsColors.waitMuted
                                        : KdsColors.headerOverdue,
                                    fontWeight: FontWeight.w800,
                                  ),
                          ),
                        ),
                        Positioned(
                          left: KdsCardDesign.remarkLeft,
                          right: KdsCardDesign.footerRight,
                          top: KdsCardDesign.remarkTop -
                              KdsSpacing.cardHeaderHeight,
                          child: Text(
                            '备注：${remark.isEmpty ? '—' : remark}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: KdsTypography.cardRemark.copyWith(
                              color: isDone
                                  ? KdsColors.waitMuted
                                  : KdsColors.headerOverdue,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Positioned(
                          left: KdsCardDesign.footerLeft,
                          right: KdsCardDesign.footerRight,
                          bottom: KdsCardDesign.footerBottom,
                          height: KdsCardDesign.footerBarHeight,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Icon(
                                Icons.access_time,
                                size: KdsSpacing.cardClockSize,
                                color: KdsColors.waitMuted,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                isDone
                                    ? formatKdsCompletionDuration(first.raw)
                                    : '${(maxWait / 60).ceil()}分钟',
                                style: KdsTypography.cardMeta,
                              ),
                              const Spacer(),
                              if (overlayStatus != null)
                                Padding(
                                  padding: const EdgeInsets.only(
                                      right: 4, bottom: 2),
                                  child: Text(
                                    overlayStatus.label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: switch (overlayStatus) {
                                        KdsOverlayStatus.persisting =>
                                          KdsColors.textMuted,
                                        KdsOverlayStatus.pending =>
                                          const Color(0xFFFFA726),
                                        KdsOverlayStatus.sending =>
                                          const Color(0xFF29B6F6),
                                        KdsOverlayStatus.unknown =>
                                          const Color(0xFFFF7043),
                                        KdsOverlayStatus.conflict =>
                                          const Color(0xFFE53935),
                                      },
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              // 数量仅作展示；整卡点击/长按推进由卡片级 InkWell 承担
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  '$total${first.raw['unit'] ?? '份'}',
                                  style: KdsTypography.cardQuantity.copyWith(
                                    color: isDone
                                        ? KdsColors.waitMuted
                                        : (canAdvance
                                            ? KdsColors.quantityRed
                                            : KdsColors.textMuted),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuantityDialog(
      BuildContext context, WidgetRef ref, int total) async {
    final selectedCount = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _QuantitySelectDialog(
        dishName: lines.first.dishName,
        unit: lines.first.raw['unit'] ?? '份',
        totalCount: total,
      ),
    );
    if (selectedCount != null && selectedCount > 0 && context.mounted) {
      await _advanceGroup(context, ref, count: selectedCount);
    }
  }

  Future<void> _showDetails(BuildContext context) => showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (dialogContext) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 960, maxHeight: 720),
            // 弹窗内容监听看板 provider：划菜 ACK/WS patch 更新状态后
            // 明细数量随之刷新，划完的行自动消失，不再显示过期快照。
            child: _DishGroupDetailsContent(
              queue: lines.first.queue,
              mergeKey: lines.first.mergeKey,
              dishName: lines.first.dishName,
              cardScale: cardScale,
              mergeByName: mergeByName,
              dining: dining,
              extra: extra,
            ),
          ),
        ),
      );

  Future<void> _quickReleaseGroup(BuildContext context, WidgetRef ref) async {
    final heldSlices = lines.where((s) => s.raw['held'] == true).toList();
    if (heldSlices.isEmpty) return;
    try {
      HapticFeedback.lightImpact();
      final notifier = ref.read(kdsV2BoardProvider.notifier);
      for (final slice in heldSlices) {
        await notifier.send(
          type: KdsV2CommandType.releaseItem,
          target: KdsV2CommandTarget(
            detailId: slice.detailId,
            fromQueue: slice.queue,
          ),
          expectedRevision: slice.revision,
        );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已成功起菜，菜品已进入制作队列'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        showKdsAdvanceFailureNotice(context, e, action: '起菜');
      }
    }
  }

  Future<void> _advanceGroup(
    BuildContext context,
    WidgetRef ref, {
    int? count,
  }) async {
    final total = lines.fold<int>(0, (sum, line) => sum + line.quantity);
    final advanceCount = (count ?? total).clamp(1, total);

    final ordered = [...lines]..sort((a, b) {
        final aWait = (a.raw['created_at_ms'] as num?)?.toInt() ??
            (a.raw['wait_start_ms'] as num?)?.toInt() ??
            0;
        final bWait = (b.raw['created_at_ms'] as num?)?.toInt() ??
            (b.raw['wait_start_ms'] as num?)?.toInt() ??
            0;
        final byWait = aWait.compareTo(bWait);
        return byWait != 0 ? byWait : a.detailId.compareTo(b.detailId);
      });

    // 按 FIFO 挑选需要推进的明细行
    var remaining = advanceCount;
    final targetLines = <KdsV2LineSlice>[];
    for (final line in ordered) {
      if (remaining <= 0) break;
      targetLines.add(line);
      remaining -= line.quantity;
    }

    final single = targetLines.length == 1 ? targetLines.single : null;
    try {
      unawaited(SystemSound.play(SystemSoundType.click).catchError((_) {}));
      HapticFeedback.lightImpact();

      await ref.read(kdsV2BoardProvider.notifier).send(
            type: KdsV2CommandType.advanceItem,
            target: KdsV2CommandTarget(
              detailId: single?.detailId,
              detailIds: single == null
                  ? targetLines.map((line) => line.detailId).toList()
                  : const [],
              fromQueue: ordered.first.queue,
            ),
            quantity: advanceCount,
            expectedRevision: single?.revision,
            expectedRevisions: single == null
                ? {
                    for (final line in targetLines)
                      line.detailId: line.revision,
                  }
                : const {},
          );

      // 成功反馈由顶部 5s 撤回弹窗承担（服务端确认后弹出）。
    } catch (error) {
      if (context.mounted) {
        showKdsAdvanceFailureNotice(context, error, action: '整组划菜');
      }
    }
  }

  /// 已完成菜品维度回撤：把本卡合并的各已完成明细退回上一步（落点由收银端决定）。
  Future<void> _revokeGroup(BuildContext context, WidgetRef ref) async {
    final doneSlices = lines
        .where((slice) => slice.queue == 'done' && slice.quantity > 0)
        .toList();
    if (doneSlices.isEmpty) return;

    final total = doneSlices.fold<int>(0, (sum, slice) => sum + slice.quantity);
    final first = doneSlices.first;
    final selectedCount = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _QuantitySelectDialog(
        dishName: first.dishName,
        unit: '${first.raw['unit'] ?? '份'}',
        totalCount: total,
        action: '回撤',
      ),
    );
    if (selectedCount == null || selectedCount <= 0 || !context.mounted) return;

    try {
      final notifier = ref.read(kdsV2BoardProvider.notifier);
      // 按后完成优先（LIFO）挑选需要回撤的明细行
      final ordered = [...doneSlices]..sort((a, b) {
          final aCompleted = (a.raw['completed_at_ms'] as num?)?.toInt() ??
              (a.raw['queue_completed_at'] as num?)?.toInt() ??
              0;
          final bCompleted = (b.raw['completed_at_ms'] as num?)?.toInt() ??
              (b.raw['queue_completed_at'] as num?)?.toInt() ??
              0;
          final byCompleted = bCompleted.compareTo(aCompleted);
          return byCompleted != 0 ? byCompleted : b.detailId.compareTo(a.detailId);
        });

      var remaining = selectedCount;
      var sent = 0;
      for (final slice in ordered) {
        if (remaining <= 0) break;
        final qtyToRevoke =
            remaining >= slice.quantity ? slice.quantity : remaining;
        await notifier.send(
          type: KdsV2CommandType.revokeItem,
          target: KdsV2CommandTarget(
            detailId: slice.detailId,
            fromQueue: slice.queue,
          ),
          quantity: qtyToRevoke,
          expectedRevision: slice.revision,
        );
        remaining -= qtyToRevoke;
        sent++;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text('已回撤 $sent 项，退回上一流程'),
            duration: const Duration(milliseconds: 2000),
            behavior: SnackBarBehavior.floating,
            width: 320,
          ));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('回撤失败：${friendlyCommandError(error)}')),
        );
      }
    }
  }
}

/// 整卡明细弹窗内容：直接监听 kdsV2BoardProvider，按 queue + mergeKey
/// 实时解析当前明细，保证划菜后数量与看板一致。
class _DishGroupDetailsContent extends ConsumerWidget {
  const _DishGroupDetailsContent({
    required this.queue,
    required this.mergeKey,
    required this.dishName,
    this.cardScale = 1.0,
    this.mergeByName = false,
    this.dining = BoardDining.all,
    this.extra,
  });

  final String queue;
  final String mergeKey;
  final String dishName;

  /// 与看板卡片一致的缩放因子
  final double cardScale;
  final bool mergeByName;
  final BoardDining dining;
  final BoardExtraFilter? extra;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(kdsV2BoardProvider);
    // 最早下单优先（FIFO）：与看板先进先出排序口径一致
    final lines = state.lines
        .expand((line) => line.slices)
        .where((slice) =>
            slice.queue == queue &&
            (mergeByName
                ? dishNameMergeKey(slice) ==
                    '${dishName.trim()}:${slice.channel.trim().toLowerCase()}'
                : slice.mergeKey == mergeKey) &&
            slice.quantity > 0 &&
            (slice.isOptimistic ||
                !state.optimisticHiddenSlices
                    .contains('${slice.detailId}:${slice.queue}')) &&
            _matchesDining(slice, dining) &&
            (extra == null || _matchesExtra(slice, extra!, state.config)))
        .toList()
      ..sort((a, b) {
        final aCreated = (a.raw['created_at_ms'] as num?)?.toInt() ?? 0;
        final bCreated = (b.raw['created_at_ms'] as num?)?.toInt() ?? 0;
        final byCreated = aCreated.compareTo(bCreated);
        return byCreated != 0 ? byCreated : a.detailId.compareTo(b.detailId);
      });
    final allowed = _allowedCommands(state.config, queue);
    final enabled = state.canMutate;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 10),
        child: Row(children: [
          Expanded(
              child: Text('$dishName · 逐桌明细',
                  style: Theme.of(context).textTheme.titleLarge)),
          IconButton(
              onPressed: () => Navigator.pop(context),
              tooltip: '关闭',
              icon: const Icon(Icons.close)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: lines.isEmpty
            ? const Center(
                child: Text('该菜品已无明细',
                    style: TextStyle(color: KdsColors.textMuted)),
              )
            : Builder(builder: (context) {
                // 与看板卡片同尺寸同缩放：卡槽 = 310×283 × scale，
                // 内容用与看板一致的 _ScaledCard 整体缩放
                final scale = cardScale.clamp(0.7, 1.6);
                final cardWidth = 310 * scale;
                final cardHeight = KdsSpacing.cardHeight * scale;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final line in lines)
                      SizedBox(
                          key: ValueKey('detail-wrap-${line.detailId}'),
                          width: cardWidth,
                          height: cardHeight,
                          child: _ScaledCard(
                            scale: scale,
                            child: _DetailCard(
                              line: line,
                              enabled: enabled,
                              allowedCommands: allowed,
                            ),
                          )),
                  ]),
                );
              }),
      ),
    ]);
  }
}

class _QuantitySelectDialog extends StatefulWidget {
  const _QuantitySelectDialog({
    required this.dishName,
    required this.unit,
    required this.totalCount,
    this.action = '划出',
  });

  final String dishName;
  final String unit;
  final int totalCount;

  /// 动作文案：划菜为「划出」，退菜为「退」等
  final String action;

  @override
  State<_QuantitySelectDialog> createState() => _QuantitySelectDialogState();
}

class _QuantitySelectDialogState extends State<_QuantitySelectDialog> {
  late int _selectedCount;

  @override
  void initState() {
    super.initState();
    _selectedCount = widget.totalCount;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: KdsColors.cardBody,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.dishName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: KdsColors.cardText,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '当前共 ${widget.totalCount} ${widget.unit}，请选择${widget.action}数量',
                          style: const TextStyle(
                            fontSize: 14,
                            color: KdsColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: KdsColors.textMuted),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0x0A000000),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filledTonal(
                      onPressed: _selectedCount > 1
                          ? () {
                              HapticFeedback.lightImpact();
                              setState(() => _selectedCount--);
                            }
                          : null,
                      icon: const Icon(Icons.remove, size: 28),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(54, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$_selectedCount',
                              style: const TextStyle(
                                fontSize: 44,
                                fontWeight: FontWeight.w900,
                                color: KdsColors.quantityRed,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.unit,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: KdsColors.cardText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: _selectedCount < widget.totalCount
                          ? () {
                              HapticFeedback.lightImpact();
                              setState(() => _selectedCount++);
                            }
                          : null,
                      icon: const Icon(Icons.add, size: 28),
                      style: IconButton.styleFrom(
                        minimumSize: const Size(54, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 1; i <= widget.totalCount && i <= 5; i++)
                    ChoiceChip(
                      label: Text('$i ${widget.unit}'),
                      selected: _selectedCount == i,
                      onSelected: (selected) {
                        if (selected) {
                          HapticFeedback.lightImpact();
                          setState(() => _selectedCount = i);
                        }
                      },
                    ),
                  if (widget.totalCount > 5)
                    ChoiceChip(
                      label: Text('全部(${widget.totalCount}${widget.unit})'),
                      selected: _selectedCount == widget.totalCount,
                      onSelected: (selected) {
                        if (selected) {
                          HapticFeedback.lightImpact();
                          setState(() => _selectedCount = widget.totalCount);
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('取消', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _selectedCount),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(
                        _selectedCount == widget.totalCount
                            ? '全部${widget.action} (${widget.totalCount}${widget.unit})'
                            : '确认${widget.action} $_selectedCount ${widget.unit}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DishTag extends StatelessWidget {
  const _DishTag({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: KdsSpacing.cardTagSize,
        height: KdsSpacing.cardTagSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(KdsSpacing.cardTagRadius),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      );
}

/// 卡片头部配色规则（菜品卡/明细卡/订单卡统一）：
/// 默认深灰；超时/催菜 → 红；加菜 → 蓝；自提/打包/外卖 → 绿；
/// 等叫 → 紫；套餐 → 橙。按紧急程度取优先级最高的一个。
Color kdsCardHeaderColor({
  required bool overdue,
  required bool rushed,
  required bool held,
  required bool addDish,
  required bool combo,
  required String channel,
}) {
  if (overdue || rushed) return KdsColors.headerOverdue;
  if (held) return KdsColors.headerHold;
  if (addDish) return KdsColors.headerAddDish;
  if (combo) return KdsColors.headerCombo;
  return switch (channel) {
    'pickup' => KdsColors.headerTakeout,
    'pack' => KdsColors.headerPack,
    'takeout' || 'delivery' => KdsColors.headerTakeout,
    _ => KdsColors.headerDefault,
  };
}

bool _isComboRaw(Map<String, dynamic> raw) =>
    raw['combo'] == true || raw['is_combo'] == true || raw['set_meal'] == true;

void showKdsHoldBlockedNotice(BuildContext context) {
  HapticFeedback.heavyImpact();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pause_circle_filled, color: Color(0xFFFBBF24), size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '该菜品处于等叫状态，请先点击【起菜】后再制作！',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
        ),
      ),
    );
}

/// 菜名前的特殊标签行：渠道（自/外/打）在前，状态（加/催/套/超/等叫）在后。
/// 渠道映射与收银端口径对齐（FulfillmentType：takeout=外卖、pickup=自提）：
/// - pickup → 自（自提单，取餐码 A 前缀）
/// - takeout / delivery → 外（外卖/配送单，取餐码 B 前缀）
/// - pack → 打（旧版前台打包取值，兼容保留）
List<Widget> _dishTags({
  required bool addDish,
  required bool rushed,
  required bool combo,
  required bool overdue,
  required String fulfillmentBucket,
  bool held = false,
}) {
  return [
    if (fulfillmentBucket == 'pickup')
      const _DishTag(label: '自', color: KdsColors.headerPack),
    if (fulfillmentBucket == 'pack')
      const _DishTag(label: '打', color: KdsColors.headerCombo),
    if (fulfillmentBucket == 'takeout' || fulfillmentBucket == 'delivery')
      const _DishTag(label: '外', color: KdsColors.headerTakeout),
    if (held) const _DishTag(label: '等叫', color: Color(0xFF8B5CF6)),
    if (addDish) const _DishTag(label: '加', color: KdsColors.headerAddDish),
    if (rushed) const _DishTag(label: '催', color: KdsColors.rushGold),
    if (combo) const _DishTag(label: '套', color: KdsColors.headerCombo),
    if (overdue) const _DishTag(label: '超', color: KdsColors.headerOverdue),
  ];
}

/// 订单卡头部 outlined 胶囊按钮（参考设计稿：白描边白字）
class _OrderAdvancePill extends StatelessWidget {
  const _OrderAdvancePill({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? Colors.white : Colors.white54,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// 已完成订单卡头部的「整单回撤」胶囊按钮（区别于推进的描边白）。
class _OrderRevokePill extends StatelessWidget {
  const _OrderRevokePill({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFFFC107), width: 2),
            color: const Color(0x1AFFC107),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '回撤',
            style: TextStyle(
              color: enabled ? const Color(0xFFFFC107) : Colors.white38,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

/// 订单卡内的小号标签（比菜品卡 _DishTag 更紧凑）
class _MiniTag extends StatelessWidget {
  const _MiniTag(
      {required this.label, required this.color, this.faded = false});

  final String label;
  final Color color;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: faded ? color.withValues(alpha: 0.35) : color,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 订单卡逐行子卡：#序号 + 等待时长 + 菜名/标签 + 数量；
/// 已划/已退（不在当前队列）灰色删除线沉底；
/// 可推进行支持单击/长按（与菜品维度同规则）
class _OrderLineCard extends StatelessWidget {
  const _OrderLineCard({
    required this.index,
    required this.line,
    required this.nowMs,
    this.scale = 1.0,
    this.advanceable = false,
    this.isDoneQueue = false,
    this.onTap,
    this.onLongPress,
  });

  final int index;
  final KdsV2OrderDisplayLine line;
  final int nowMs;
  final double scale;
  final bool advanceable;
  final bool isDoneQueue;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final done = !line.isInCurrentQueue;
    final isDoneItem = isDoneQueue || done;
    final waitSeconds = line.createdAtMs == null
        ? null
        : ((nowMs - line.createdAtMs!) ~/ 1000).clamp(0, 1 << 31);
    final overdue = !isDoneItem &&
        waitSeconds != null &&
        KdsLineWaitTime.isOverdue(line.raw, waitSeconds: waitSeconds);
    final nameColor =
        isDoneItem ? KdsOrderSpacing.lineMutedColor : KdsColors.cardText;
    final strike = done ? TextDecoration.lineThrough : null;
    final String? timeDisplay = isDoneItem
        ? formatKdsCompletionDuration(line.raw)
        : (waitSeconds != null ? '${(waitSeconds / 60).ceil()}分钟' : null);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          // 可推进行：单击/长按推进（行级 InkWell 在整卡 InkWell 内层，手势优先）
          onTap: advanceable ? onTap : null,
          onLongPress: advanceable ? onLongPress : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8E8E8)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '#${index + 1}',
                      style: TextStyle(
                        color: KdsColors.waitMuted,
                        fontSize: 13 * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (timeDisplay != null) ...[
                      Icon(
                        Icons.access_time,
                        size: 15 * scale,
                        color: isDoneItem
                            ? KdsColors.waitMuted
                            : (overdue
                                ? KdsOrderSpacing.waitOverdue
                                : KdsColors.waitMuted),
                      ),
                      const SizedBox(width: 2),
                      Text(
                        timeDisplay,
                        style: TextStyle(
                          color: isDoneItem
                              ? KdsColors.waitMuted
                              : (overdue
                                  ? KdsOrderSpacing.waitOverdue
                                  : KdsColors.waitMuted),
                          fontSize: 14 * scale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(height: 4 * scale),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        line.dishName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: 19 * scale,
                          fontWeight: FontWeight.w800,
                          decoration: strike,
                          decorationColor: nameColor,
                        ),
                      ),
                    ),
                    if (line.addDish) ...[
                      const SizedBox(width: 4),
                      _MiniTag(
                          label: '加',
                          color: KdsColors.headerAddDish,
                          faded: done),
                    ],
                    if (line.rushed) ...[
                      const SizedBox(width: 4),
                      _MiniTag(
                          label: '催', color: KdsColors.rushGold, faded: done),
                    ],
                    if (line.raw['held'] == true) ...[
                      const SizedBox(width: 4),
                      _MiniTag(
                        label: '等叫',
                        color: const Color(0xFF8B5CF6),
                        faded: done,
                      ),
                    ],
                    if (overdue) ...[
                      const SizedBox(width: 4),
                      const _MiniTag(
                          label: '超', color: KdsColors.headerOverdue),
                    ],
                    if (line.overlayStatus != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        line.overlayStatus!.label,
                        style: TextStyle(
                          fontSize: 10 * scale,
                          color: switch (line.overlayStatus!) {
                            KdsOverlayStatus.persisting =>
                              const Color(0xFF78909C),
                            KdsOverlayStatus.pending => const Color(0xFFFFA726),
                            KdsOverlayStatus.sending => const Color(0xFF29B6F6),
                            KdsOverlayStatus.unknown => const Color(0xFFFF7043),
                            KdsOverlayStatus.conflict =>
                              const Color(0xFFE53935),
                          },
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      '${line.displayQuantity}${line.unit}',
                      style: TextStyle(
                        color: done
                            ? KdsOrderSpacing.lineMutedColor
                            : KdsColors.quantityRed,
                        fontSize: 17 * scale,
                        fontWeight: FontWeight.w800,
                        decoration: strike,
                      ),
                    ),
                  ],
                ),
                // 规格/辣度（如「微辣,9成熟」），红色显眼提示；无规格不占位
                if (line.specText != null) ...[
                  SizedBox(height: 2 * scale),
                  Text(
                    line.specText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: done
                          ? KdsOrderSpacing.lineMutedColor
                          : KdsColors.quantityRed,
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w800,
                      decoration: strike,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailCard extends ConsumerStatefulWidget {
  const _DetailCard(
      {required this.line,
      required this.enabled,
      required this.allowedCommands});
  final KdsV2LineSlice line;
  final bool enabled;
  final Set<KdsV2CommandType> allowedCommands;

  @override
  ConsumerState<_DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends ConsumerState<_DetailCard> {
  bool _hidden = false;

  bool get _canAdvance =>
      widget.enabled &&
      widget.allowedCommands.contains(KdsV2CommandType.advanceItem);

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final line = widget.line;
    final table = lineTableOrPickupCode(line);
    // 规格统一走 KdsSpecText 解析，JSON 规格只显示可读值（如「微辣」）
    final spec = KdsSpecText.fromLine(line.raw, includeTaste: true);
    final remark = '${line.raw['remark'] ?? ''}'.trim();
    final isDone = line.queue == 'done';
    final waitSeconds =
        line.waitSecondsAt(DateTime.now().millisecondsSinceEpoch);
    final waitMinutes = (waitSeconds / 60).ceil();
    final isAddDish =
        line.raw['add_dish'] == true || line.raw['is_add_dish'] == true;
    final isOverdue = KdsLineWaitTime.isOverdue(
      line.raw,
      waitSeconds: waitSeconds,
    );
    final isRefunded =
        line.raw['line_status'] == 'refunded' || line.raw['status'] == 'refunded';
    final detailTags = isDone
        ? _dishTags(
            addDish: false,
            rushed: false,
            combo: _isComboRaw(line.raw),
            overdue: false,
            fulfillmentBucket: line.channel,
            held: false,
          )
        : _dishTags(
            addDish: isAddDish,
            rushed: line.raw['rushed'] == true,
            combo: _isComboRaw(line.raw),
            overdue: isOverdue,
            fulfillmentBucket: line.channel,
            held: line.raw['held'] == true,
          );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: KdsColors.cardBody,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(KdsSpacing.cardOuterRadius)),
      child: Tooltip(
        message: isDone
            ? '已完成'
            : (isRefunded
                ? '已退菜'
                : (line.raw['held'] == true
                    ? '等叫中（点击起菜）'
                    : (!_canAdvance
                        ? '当前不可划菜'
                        : (line.quantity > 1 ? '点击划菜，长按选择数量' : '点击划菜')))),
        child: InkWell(
          key: ValueKey('detail-advance-${line.detailId}'),
          // 单击卡片直接整行推进；长按弹出数量弹窗按数量推进
          onTap: !isDone && !isRefunded
              ? () {
                  if (line.raw['held'] == true) {
                    showKdsHoldBlockedNotice(context);
                    return;
                  }
                  if (_canAdvance) {
                    _send(
                      context,
                      ref,
                      KdsV2CommandType.advanceItem,
                      // 接口未提供 quantity 时默认只推进 1 份；逐桌明细
                      // 的普通点击语义是整行划菜，必须显式传当前剩余数量。
                      quantity: line.quantity,
                    );
                  }
                }
              : null,
          onLongPress: !isDone && !isRefunded && line.quantity > 1
              ? () {
                  if (line.raw['held'] == true) {
                    showKdsHoldBlockedNotice(context);
                    return;
                  }
                  if (_canAdvance) {
                    _showQuantityDialog(context, ref);
                  }
                }
              : null,
          // 布局尺寸样式与看板整卡卡片（_DishGroupCard）一致：
          // 同卡片高度、同头部、同排版坐标、同文字样式、同底栏
          child: SizedBox(
            height: KdsSpacing.cardHeight,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: KdsSpacing.cardHeaderHeight,
                    // 头部配色：已完成页面统一深灰；未完成页面按规则分色
                    color: isDone
                        ? KdsColors.headerDefault
                        : kdsCardHeaderColor(
                            overdue: isOverdue,
                            rushed: line.raw['rushed'] == true,
                            held: line.raw['held'] == true,
                            addDish: isAddDish,
                            combo: _isComboRaw(line.raw),
                            channel: line.channel,
                          ),
                    padding: const EdgeInsets.only(
                      left: KdsCardDesign.headerLabelLeft,
                      right: KdsCardDesign.headerDetailRight,
                    ),
                    child: Row(children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(table,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: KdsTypography.cardHeaderLabel
                                  .copyWith(color: Colors.white)),
                        ),
                      ),
                      if (line.overlayStatus != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              line.overlayStatus!.label,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      if (!isDone && !isRefunded)
                        PopupMenuButton<KdsV2CommandType>(
                          enabled: widget.enabled,
                          iconColor: Colors.white,
                          tooltip: widget.enabled ? '更多操作' : '断线时操作不可用',
                          onSelected: (type) => _send(context, ref, type),
                          itemBuilder: (_) => [
                            for (final entry in _commands.where((entry) =>
                                widget.allowedCommands.contains(entry.$1) &&
                                entry.$1 != KdsV2CommandType.advanceItem))
                              PopupMenuItem(
                                  value: entry.$1, child: Text(entry.$2)),
                          ],
                        ),
                    ]),
                  ),
                  Expanded(
                    child: Stack(children: [
                      Positioned(
                        left: KdsCardDesign.dishNameRowLeft,
                        right: KdsCardDesign.footerRight,
                        top: KdsCardDesign.dishNameRowTop -
                            KdsSpacing.cardHeaderHeight,
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              for (var tagIndex = 0;
                                  tagIndex < detailTags.length;
                                  tagIndex++) ...[
                                if (tagIndex > 0)
                                  const SizedBox(width: KdsSpacing.cardTagGap),
                                detailTags[tagIndex],
                              ],
                              if (detailTags.isNotEmpty)
                                const SizedBox(
                                    width: KdsSpacing.cardTagToNameGap),
                              Expanded(
                                child: Text(
                                  line.dishName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: KdsTypography.cardDishName,
                                ),
                              ),
                            ]),
                      ),
                      Positioned(
                        left: KdsCardDesign.specLeft,
                        right: KdsCardDesign.footerRight,
                        top:
                            KdsCardDesign.specTop - KdsSpacing.cardHeaderHeight,
                        child: Text(
                          '做法：${spec ?? '默认'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: spec == null
                              ? KdsTypography.cardRemark
                              : KdsTypography.cardRemark.copyWith(
                                  color: isDone
                                      ? KdsColors.waitMuted
                                      : KdsColors.headerOverdue,
                                  fontWeight: FontWeight.w800,
                                ),
                        ),
                      ),
                      Positioned(
                        left: KdsCardDesign.remarkLeft,
                        right: KdsCardDesign.footerRight,
                        top: KdsCardDesign.remarkTop -
                            KdsSpacing.cardHeaderHeight,
                        child: Text(
                          '备注：${remark.isEmpty ? '—' : remark}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: KdsTypography.cardRemark.copyWith(
                            color: isDone
                                ? KdsColors.waitMuted
                                : KdsColors.headerOverdue,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Positioned(
                        left: KdsCardDesign.footerLeft,
                        right: KdsCardDesign.footerRight,
                        bottom: KdsCardDesign.footerBottom,
                        height: KdsCardDesign.footerBarHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: KdsSpacing.cardClockSize,
                              color: KdsColors.waitMuted,
                            ),
                            const SizedBox(width: 2),
                            // 防溢出：超长等待时长省略号截断 / 完成时间点
                            Expanded(
                              child: Text(
                                isDone
                                    ? formatKdsCompletionDuration(line.raw)
                                    : '$waitMinutes分钟',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: KdsTypography.cardMeta,
                              ),
                            ),
                            if (line.overlayStatus != null)
                              Padding(
                                padding:
                                    const EdgeInsets.only(right: 4, bottom: 2),
                                child: Text(
                                  line.overlayStatus!.label,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: switch (line.overlayStatus!) {
                                      KdsOverlayStatus.persisting =>
                                        KdsColors.textMuted,
                                      KdsOverlayStatus.pending =>
                                        const Color(0xFFFFA726),
                                      KdsOverlayStatus.sending =>
                                        const Color(0xFF29B6F6),
                                      KdsOverlayStatus.unknown =>
                                        const Color(0xFFFF7043),
                                      KdsOverlayStatus.conflict =>
                                        const Color(0xFFE53935),
                                    },
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '${line.quantity}${line.raw['unit'] ?? '份'}',
                                style: KdsTypography.cardQuantity.copyWith(
                                  color: isDone
                                      ? KdsColors.waitMuted
                                      : (_canAdvance
                                          ? KdsColors.quantityRed
                                          : KdsColors.textMuted),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]),
                  ),
                ]),
          ),
        ),
      ),
    );
  }

  Future<void> _showQuantityDialog(BuildContext context, WidgetRef ref) async {
    final line = widget.line;
    final selectedCount = await showDialog<int>(
      context: context,
      barrierColor: Colors.black54,
      builder: (dialogContext) => _QuantitySelectDialog(
        dishName: line.dishName,
        unit: '${line.raw['unit'] ?? '份'}',
        totalCount: line.quantity,
      ),
    );
    if (selectedCount != null && selectedCount > 0 && context.mounted) {
      await _send(context, ref, KdsV2CommandType.advanceItem,
          quantity: selectedCount);
    }
  }

  List<(KdsV2CommandType, String)> get _commands {
    final raw = widget.line.raw;
    final isRefunded =
        raw['line_status'] == 'refunded' || raw['status'] == 'refunded';
    if (isRefunded) return const [];

    final servedQty = (raw['served_quantity'] is num)
        ? (raw['served_quantity'] as num).toInt()
        : 0;
    final totalQty = (raw['quantity'] is num)
        ? (raw['quantity'] as num).toInt()
        : widget.line.quantity;
    final isCompleted = widget.line.queue == 'done' ||
        (servedQty > 0 && servedQty >= totalQty) ||
        raw['item_status'] == 2 ||
        raw['status'] == 'DONE';

    return [
      (KdsV2CommandType.advanceItem, '推进明细'),
      (KdsV2CommandType.revokeItem, '撤销明细'),
      (KdsV2CommandType.lackItem, '缺货'),
      (KdsV2CommandType.refundItem, '退菜'),
      (KdsV2CommandType.rushItem, '催菜'),
      if (!isCompleted && raw['held'] != true)
        (KdsV2CommandType.holdItem, '等叫'),
      if (!isCompleted && raw['held'] == true)
        (KdsV2CommandType.releaseItem, '起菜'),
      (KdsV2CommandType.advanceOrder, '推进整单'),
      (KdsV2CommandType.rushOrder, '催整单'),
      (KdsV2CommandType.completeOrder, '完成整单'),
      if (widget.line.queue == 'done')
        (KdsV2CommandType.archiveOrder, '归档整单'),
    ];
  }

  Future<void> _send(
    BuildContext context,
    WidgetRef ref,
    KdsV2CommandType type, {
    int? quantity,
  }) async {
    if (type == KdsV2CommandType.advanceItem && widget.line.raw['held'] == true) {
      showKdsHoldBlockedNotice(context);
      return;
    }
    final isOrder = {
      KdsV2CommandType.advanceOrder,
      KdsV2CommandType.rushOrder,
      KdsV2CommandType.completeOrder,
      KdsV2CommandType.archiveOrder,
    }.contains(type);
    // 整行划出才乐观隐藏；部分数量划出保留卡片等待权威 patch
    final hideOptimistically = type == KdsV2CommandType.advanceItem &&
        (quantity == null || quantity >= widget.line.quantity);
    if (hideOptimistically && mounted) setState(() => _hidden = true);
    try {
      if (type == KdsV2CommandType.refundItem && quantity == null) {
        // 退菜涉及金额：多份先选数量，再二次确认；操作不可撤销
        final line0 = widget.line;
        final unit0 = '${line0.raw['unit'] ?? '份'}';
        var count = 1;
        if (line0.quantity > 1) {
          final selected = await showDialog<int>(
            context: context,
            barrierColor: Colors.black54,
            builder: (dialogContext) => _QuantitySelectDialog(
              dishName: line0.dishName,
              unit: unit0,
              totalCount: line0.quantity,
              action: '退',
            ),
          );
          if (selected == null || !context.mounted) return;
          count = selected;
        }
        if (!context.mounted) return;
        final table0 = lineTableOrPickupCode(line0);
        final confirmed = await _confirmAction(
          context,
          title: '确认退菜？',
          message: '$table0 · ${line0.dishName}\n退 $count $unit0，退菜操作不可撤销。',
          confirmLabel: '确认退菜',
        );
        if (confirmed != true || !context.mounted) return;
        quantity = count;
      }
      if (type == KdsV2CommandType.revokeItem && quantity == null) {
        final line0 = widget.line;
        final unit0 = '${line0.raw['unit'] ?? '份'}';
        final selected = await showDialog<int>(
          context: context,
          barrierColor: Colors.black54,
          builder: (dialogContext) => _QuantitySelectDialog(
            dishName: line0.dishName,
            unit: unit0,
            totalCount: line0.quantity,
            action: '回撤',
          ),
        );
        if (selected == null || selected <= 0 || !context.mounted) return;
        quantity = selected;
      }
      if (type == KdsV2CommandType.completeOrder) {
        final confirmed = await _confirmAction(
          context,
          title: '确认强制完成整单？',
          message: '该操作会将整单所有菜品直接设为已完成，请确认厨房现场状态。',
          confirmLabel: '确认完成',
        );
        if (confirmed != true || !context.mounted) return;
      }
      final line = widget.line;
      final expectedRevision = isOrder ? line.orderRevision : line.revision;
      // 整单推进已改为逐明细 advanceItem（按行 revision 锁定），
      // 不再依赖整单 order_revision
      if (isOrder &&
          type != KdsV2CommandType.advanceOrder &&
          expectedRevision == null) {
        throw const FormatException(
            'KDS v2 order snapshot is missing order_revision');
      }
      unawaited(SystemSound.play(SystemSoundType.click).catchError((_) {}));
      HapticFeedback.lightImpact();

      // 按接口文档限定 from_queue：仅 advance/revoke/refund/advance_order
      // 的 target 含该字段；rush/lack/hold/release/complete/archive 不下发，
      // 避免严格校验的收银端拒收。
      final needsFromQueue = const {
        KdsV2CommandType.advanceItem,
        KdsV2CommandType.revokeItem,
        KdsV2CommandType.refundItem,
        KdsV2CommandType.advanceOrder,
      }.contains(type);
      if (type == KdsV2CommandType.advanceOrder) {
        // 整单推进 = 逐明细推进：只推流程仍停留在当前队列的行，
        // 其他队列（如待传菜）的行不受影响，严格单一流程。
        await ref.read(kdsV2BoardProvider.notifier).advanceOrderLines(
              orderId: line.orderId,
              fromQueue: line.queue,
            );
      } else {
        await ref.read(kdsV2BoardProvider.notifier).send(
              type: type,
              target: KdsV2CommandTarget(
                orderId: isOrder ? line.orderId : null,
                detailId: isOrder ? null : line.detailId,
                fromQueue: needsFromQueue ? line.queue : null,
              ),
              quantity: quantity,
              expectedRevision: expectedRevision,
              // 缺货即估清：同步标记收银端本地目录售罄，
              // 目录刷新后占位卡显示「估清」
              setSoldOut: type == KdsV2CommandType.lackItem ? true : null,
            );
      }

      if (context.mounted) {
        final text = _commandSuccessText(type, line, quantity);
        if (text != null) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text),
              duration: const Duration(milliseconds: 2000),
              behavior: SnackBarBehavior.floating,
              width: 320,
            ),
          );
        }
      }
    } catch (error) {
      if (hideOptimistically && mounted) setState(() => _hidden = false);
      if (context.mounted) {
        if (type == KdsV2CommandType.advanceItem || type == KdsV2CommandType.advanceOrder) {
          showKdsAdvanceFailureNotice(context, error, action: type == KdsV2CommandType.advanceItem ? '划菜' : '整单推进');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyCommandError(error))),
          );
        }
      }
    }
  }

  Future<bool?> _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      );

  String? _commandSuccessText(
      KdsV2CommandType type, KdsV2LineSlice line, int? quantity) {
    final unit = '${line.raw['unit'] ?? '份'}';
    return switch (type) {
      KdsV2CommandType.advanceItem => quantity == null
          ? '已划出明细：${line.dishName} ×${line.quantity}'
          : '已划出 $quantity $unit ${line.dishName}',
      KdsV2CommandType.refundItem =>
        '已退菜 ${quantity ?? 1} $unit ${line.dishName}',
      KdsV2CommandType.revokeItem => quantity == null
          ? '已撤销：${line.dishName}'
          : '已撤销 $quantity $unit ${line.dishName}',
      KdsV2CommandType.lackItem => '已标记缺货（估清）：${line.dishName}',
      KdsV2CommandType.rushItem => '已催菜：${line.dishName}',
      KdsV2CommandType.holdItem => '已设等叫：${line.dishName}',
      KdsV2CommandType.releaseItem => '已起菜：${line.dishName}',
      KdsV2CommandType.advanceOrder => '已提交整单推进',
      KdsV2CommandType.rushOrder => '已催整单',
      KdsV2CommandType.completeOrder => '已强制完成整单',
      KdsV2CommandType.archiveOrder => '已归档整单',
      KdsV2CommandType.archiveClear => null,
    };
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({super.key, required this.item});
  final KdsV2CatalogItem item;
  @override
  Widget build(BuildContext context) => Card(
        color: KdsColors.cardBody,
        child: SizedBox(
          height: KdsSpacing.cardHeight,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: const Color(0xFFE5E5E5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(children: [
                Expanded(
                    child: Text(item.dishName,
                        style: const TextStyle(
                            color: KdsColors.textMuted,
                            fontSize: 19,
                            fontWeight: FontWeight.w800))),
                if (item.soldOut)
                  const Text('估清',
                      style: TextStyle(
                          color: KdsColors.headerOverdue,
                          fontSize: 17,
                          fontWeight: FontWeight.w800))
                else
                  const Text('—',
                      style: TextStyle(
                          color: KdsColors.textMuted,
                          fontSize: 25,
                          fontWeight: FontWeight.w900)),
              ]),
            ),
            const Expanded(
                child: Padding(
              padding: EdgeInsets.all(14),
              child: Text('—',
                  style: TextStyle(
                      color: KdsColors.textMuted,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
            )),
          ]),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon,
      required this.title,
      required this.message,
      required this.onRetry});
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 48, color: KdsColors.textMuted),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(message, style: const TextStyle(color: KdsColors.textMuted)),
          const SizedBox(height: 14),
          FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('重试')),
        ]),
      );
}

/// 划菜撤回提示条：从看板底部浮现的悬浮条，5s 倒计时内可点击「撤回」把
/// 刚划入已完成的菜品退回上一步（待传菜）。
/// 只展示最近一次可撤回的划菜（新划菜直接替换旧的，不支持全部撤回）。
/// 数据源为 provider 的 undoBatch（服务端确认后才推送）。
class _AdvanceUndoToast extends ConsumerStatefulWidget {
  const _AdvanceUndoToast();

  @override
  ConsumerState<_AdvanceUndoToast> createState() => _AdvanceUndoToastState();
}

class _AdvanceUndoToastState extends ConsumerState<_AdvanceUndoToast>
    with SingleTickerProviderStateMixin {
  static const _windowSeconds = 5;

  late final AnimationController _slide;
  late final Animation<Offset> _offset;
  late final Animation<double> _fade;
  KdsAdvanceUndoBatch? _batch;
  Timer? _countdown;
  int _remaining = _windowSeconds;
  ValueNotifier<KdsAdvanceUndoBatch?>? _undo;

  @override
  void initState() {
    super.initState();
    _slide = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 280));
    // 从底部滑入浮现
    _offset = Tween(begin: const Offset(0, 1.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slide, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _slide, curve: Curves.easeOut);
    try {
      _undo = ref.read(kdsV2BoardProvider.notifier).undoBatch;
      _undo!.addListener(_onBatch);
      _batch = _undo!.value;
      if (_batch != null) {
        _slide.forward();
        _startCountdown();
      }
    } catch (_) {
      // 无 ProviderScope（如部分单测直接渲染看板）时禁用撤回弹窗，
      // 不影响看板本身渲染。
      _undo = null;
    }
  }

  void _onBatch() {
    if (!mounted) return;
    setState(() => _batch = _undo!.value);
    if (_batch != null) {
      _slide.forward(from: 0);
      _startCountdown();
    }
  }

  void _startCountdown() {
    _countdown?.cancel();
    _remaining = _windowSeconds;
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _remaining--);
      if (_remaining <= 0) {
        timer.cancel();
        _undo!.value = null;
        setState(() => _batch = null);
      }
    });
  }

  Future<void> _undoNow() async {
    final batch = _batch;
    if (batch == null) return;
    _countdown?.cancel();
    _undo!.value = null;
    await ref.read(kdsV2BoardProvider.notifier).revokeUndoBatch(batch);
  }

  @override
  void dispose() {
    _undo?.removeListener(_onBatch);
    _countdown?.cancel();
    _slide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final batch = _batch;
    if (batch == null) return const SizedBox.shrink();
    final summary = undoBatchSummary(batch);
    return SlideTransition(
      position: _offset,
      child: FadeTransition(
        opacity: _fade,
        child: Material(
          color: const Color(0xFF333333),
          elevation: 10,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 10, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: Color(0xFF0CB960), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '已划出 $summary',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$_remaining s',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                      ),
                      TextButton(
                        onPressed: _undoNow,
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFFFC107),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          minimumSize: const Size(0, 36),
                        ),
                        child: const Text('撤回',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ),
                LinearProgressIndicator(
                  value: _remaining / _windowSeconds,
                  minHeight: 3,
                  backgroundColor: const Color(0x33FFFFFF),
                  color: const Color(0xFFFFC107),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


/// 全局退菜强提醒横幅列表：当收银端或后厨发起退菜时，顶部高亮警示并锁定显示，需后厨人员主动点击关闭，防止继续烹饪造成食材浪费
class _RefundAlertBannerList extends StatelessWidget {
  const _RefundAlertBannerList({
    this.alertsNotifier,
    this.onDismiss,
  });

  final ValueNotifier<List<KdsRefundAlertItem>>? alertsNotifier;
  final void Function(String id)? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (alertsNotifier == null) return const SizedBox.shrink();

    return ValueListenableBuilder<List<KdsRefundAlertItem>>(
      valueListenable: alertsNotifier!,
      builder: (context, alerts, _) {
        if (alerts.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Color(0xFFC62828), // 强警报深红
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final alert in alerts)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 22),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '退菜提醒',
                          style: TextStyle(
                            color: Color(0xFFC62828),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${alert.tableOrPickupCode.isEmpty ? '' : '${alert.tableOrPickupCode} · '}${alert.dishName} x${alert.quantity}${alert.unit} 已退菜，请立即停止烹饪！',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: onDismiss != null
                            ? () => onDismiss!(alert.id)
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFC62828),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: const Size(0, 30),
                        ),
                        child: const Text(
                          '我知道了',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
