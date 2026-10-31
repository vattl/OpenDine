import 'package:flutter/material.dart';
import 'package:kds_app/core/config/kds_connection_mode.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';
import 'package:kds_app/core/layout/kds_display_scope.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/shared/widgets/kds_filter_chip.dart';
import 'package:kds_app/shared/widgets/kds_ws_indicator.dart';

/// 看板顶栏 + 筛选条 — 对齐 UI设计代码
class BoardShell extends StatelessWidget {
  const BoardShell({
    super.key,
    required this.body,
    required this.queue,
    required this.dining,
    required this.isDishView,
    required this.extra,
    required this.visibleQueues,
    required this.onQueueChanged,
    required this.onDiningChanged,
    required this.onViewChanged,
    required this.onExtraSelected,
    this.collapsed = false,
    this.onCollapseToggle,
    this.wsConnected = true,
    this.activeChannel = KdsActiveChannel.lan,
    this.onChannelSwitch,
    this.lastEventAtMs,
    this.onRefresh,
    this.onSettings,
    this.onLogs,
    this.onInspector,
    this.onQueueTasks,
    this.pendingSyncCount = 0,
    this.onLogout,
    this.onSearch,
    this.onClearSearch,
    this.searchQuery = '',
    this.sortMode = BoardSortMode.fifo,
    this.onSortChanged,
    this.cardScale,
    this.onCardScaleChanged,
    this.onCardScaleChangeEnd,
    this.statsLine,
    this.queueCounts = const {},
    this.extraCounts = const {},
    this.diningCounts = const {},
    this.onHelp,
  });

  final Widget body;
  final BoardQueue queue;
  final BoardDining dining;
  final bool isDishView;
  final BoardExtraFilter? extra;
  final List<BoardQueue> visibleQueues;
  final ValueChanged<BoardQueue> onQueueChanged;
  final ValueChanged<BoardDining> onDiningChanged;
  final ValueChanged<bool> onViewChanged;

  /// null = 选「全部」；否则选中对应筛选项（单选）
  final ValueChanged<BoardExtraFilter?> onExtraSelected;
  final bool collapsed;
  final VoidCallback? onCollapseToggle;
  final bool wsConnected;
  final KdsActiveChannel activeChannel;
  final VoidCallback? onChannelSwitch;

  /// 最近一次业务事件的本地毫秒时间，叠加在 WS 指示灯旁；null 不展示。
  final int? lastEventAtMs;
  final VoidCallback? onRefresh;
  final VoidCallback? onSettings;
  final VoidCallback? onLogs;
  final VoidCallback? onInspector;
  final VoidCallback? onQueueTasks;
  final int pendingSyncCount;
  final VoidCallback? onLogout;
  final VoidCallback? onSearch;
  final VoidCallback? onClearSearch;
  final String searchQuery;
  final BoardSortMode sortMode;
  final ValueChanged<BoardSortMode>? onSortChanged;

  /// 卡片缩放（0.7–1.6）；两者同时提供时筛选条显示缩放滑块
  final double? cardScale;
  final ValueChanged<double>? onCardScaleChanged;

  /// 拖动结束（用于持久化）；null 时每次 onChanged 即最终值
  final ValueChanged<double>? onCardScaleChangeEnd;
  final String? statsLine;
  final Map<String, int> queueCounts;
  final Map<String, int> extraCounts;
  final Map<String, int> diningCounts;
  final VoidCallback? onHelp;

  static const _diningOrder = [
    BoardDining.all,
    BoardDining.dineIn,
    BoardDining.pack,
    BoardDining.takeout,
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KdsColors.shellBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!collapsed)
            _TopBar(
              queue: queue,
              visibleQueues: visibleQueues,
              queueCounts: queueCounts,
              onQueueChanged: onQueueChanged,
              wsConnected: wsConnected,
              activeChannel: activeChannel,
              onChannelSwitch: onChannelSwitch,
              lastEventAtMs: lastEventAtMs,
              onRefresh: onRefresh,
              onSettings: onSettings,
              onLogs: onLogs,
              onInspector: onInspector,
              onQueueTasks: onQueueTasks,
              pendingSyncCount: pendingSyncCount,
              onLogout: onLogout,
              onSearch: onSearch,
              onClearSearch: onClearSearch,
              searchQuery: searchQuery,
              statsLine: statsLine,
              onHelp: onHelp,
            ),
          if (!collapsed)
            _FilterBar(
              dining: dining,
              extraCounts: extraCounts,
              diningCounts: diningCounts,
              isDishView: isDishView,
              extra: extra,
              onDiningChanged: onDiningChanged,
              onViewChanged: onViewChanged,
              onExtraSelected: onExtraSelected,
              sortMode: sortMode,
              onSortChanged: onSortChanged,
              onCollapseToggle: onCollapseToggle,
              cardScale: cardScale,
              onCardScaleChanged: onCardScaleChanged,
              onCardScaleChangeEnd: onCardScaleChangeEnd,
            ),
          if (collapsed)
            Material(
              color: KdsColors.filterBarBg,
              child: Align(
                alignment: Alignment.centerRight,
                child: KdsCollapseButton(
                    collapsed: true, onPressed: onCollapseToggle),
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.queue,
    required this.visibleQueues,
    required this.queueCounts,
    required this.onQueueChanged,
    required this.wsConnected,
    required this.activeChannel,
    this.onChannelSwitch,
    this.lastEventAtMs,
    this.onRefresh,
    this.onSettings,
    this.onLogs,
    this.onInspector,
    this.onQueueTasks,
    this.pendingSyncCount = 0,
    this.onLogout,
    this.onSearch,
    this.onClearSearch,
    this.searchQuery = '',
    this.statsLine,
    this.onHelp,
  });

  final BoardQueue queue;
  final List<BoardQueue> visibleQueues;
  final Map<String, int> queueCounts;
  final ValueChanged<BoardQueue> onQueueChanged;
  final bool wsConnected;
  final KdsActiveChannel activeChannel;
  final VoidCallback? onChannelSwitch;
  final int? lastEventAtMs;
  final VoidCallback? onRefresh;
  final VoidCallback? onSettings;
  final VoidCallback? onLogs;
  final VoidCallback? onInspector;
  final VoidCallback? onQueueTasks;
  final int pendingSyncCount;
  final VoidCallback? onLogout;
  final VoidCallback? onSearch;
  final VoidCallback? onClearSearch;
  final String searchQuery;
  final String? statsLine;
  final VoidCallback? onHelp;

  @override
  Widget build(BuildContext context) {
    final display = context.kdsDisplay;
    return Material(
      color: KdsColors.topBarBg,
      child: SizedBox(
        height: display.topBarHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: display.dp(16)),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final q in visibleQueues)
                        KdsMainTab(
                          label: q.label,
                          selected: queue == q,
                          onTap: () => onQueueChanged(q),
                          badge: q == BoardQueue.done
                              ? null
                              : queueCounts[q.apiValue],
                        ),
                      if (statsLine != null) ...[
                        const SizedBox(width: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: KdsColors.segmentBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            statsLine!,
                            style: KdsTypography.chipLabelInactive
                                .copyWith(fontSize: 14),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InputChip(
                    label: Text('「$searchQuery」',
                        style: const TextStyle(fontSize: 13)),
                    onDeleted: onClearSearch,
                    backgroundColor: KdsColors.segmentBg,
                    deleteIconColor: KdsColors.textPrimary,
                    labelStyle: const TextStyle(color: KdsColors.textPrimary),
                  ),
                ),
              KdsCircleIconButton(
                  icon: Icons.search, onPressed: onSearch, tooltip: '搜索'),
              const SizedBox(width: 12),
              if (onRefresh != null) ...[
                const SizedBox(width: 12),
                KdsCircleIconButton(
                  key: const ValueKey('board-manual-refresh'),
                  icon: Icons.refresh,
                  onPressed: onRefresh,
                  tooltip: '手动全量刷新',
                ),
              ],
              const SizedBox(width: 12),
              _ActiveChannelBadge(
                channel: activeChannel,
                onTap: onChannelSwitch,
              ),
              const SizedBox(width: 10),
              KdsWsIndicator(
                connected: wsConnected,
                lastEventAtMs: lastEventAtMs,
              ),
              const SizedBox(width: 12),
              KdsCircleIconButton(
                icon: Icons.settings_outlined,
                onPressed: onSettings,
                tooltip: '设置',
              ),
              const SizedBox(width: 20),
              const Text('老肥餐饮系统', style: KdsTypography.brandTitle),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveChannelBadge extends StatelessWidget {
  const _ActiveChannelBadge({required this.channel, this.onTap});

  final KdsActiveChannel channel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isLan = channel == KdsActiveChannel.lan;
    final label = isLan ? '局域网模式' : '云端模式';
    final color = isLan ? const Color(0xFF43A047) : const Color(0xFF42A5F5);

    return Semantics(
      liveRegion: true,
      button: onTap != null,
      label: '当前连接：$label${onTap == null ? '' : '，点击切换连接通道'}',
      child: Tooltip(
        message: onTap == null
            ? '当前实际活动通道：${channel.label}'
            : '当前实际活动通道：${channel.label}，点击切换',
        child: InkWell(
          key: ValueKey('active-channel-${channel.value}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.72)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isLan ? Icons.lan_outlined : Icons.cloud_outlined,
                  size: 16,
                  color: color,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.swap_horiz, size: 15, color: color),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.dining,
    required this.extraCounts,
    required this.diningCounts,
    required this.isDishView,
    required this.extra,
    required this.onDiningChanged,
    required this.onViewChanged,
    required this.onExtraSelected,
    this.sortMode = BoardSortMode.fifo,
    this.onSortChanged,
    this.onCollapseToggle,
    this.cardScale,
    this.onCardScaleChanged,
    this.onCardScaleChangeEnd,
  });

  final BoardDining dining;
  final Map<String, int> extraCounts;
  final Map<String, int> diningCounts;
  final bool isDishView;
  final BoardExtraFilter? extra;
  final ValueChanged<BoardDining> onDiningChanged;
  final ValueChanged<bool> onViewChanged;
  final ValueChanged<BoardExtraFilter?> onExtraSelected;
  final BoardSortMode sortMode;
  final ValueChanged<BoardSortMode>? onSortChanged;
  final VoidCallback? onCollapseToggle;
  final double? cardScale;
  final ValueChanged<double>? onCardScaleChanged;
  final ValueChanged<double>? onCardScaleChangeEnd;

  @override
  Widget build(BuildContext context) {
    final display = context.kdsDisplay;
    return Material(
      color: KdsColors.filterBarBg,
      clipBehavior: Clip.none,
      child: SizedBox(
        height: display.filterBarHeight + display.dp(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 窄屏时收起缩放滑块，避免筛选条溢出
            final showZoom = cardScale != null &&
                onCardScaleChanged != null &&
                constraints.maxWidth >= 1000;
            return Padding(
              padding: EdgeInsets.fromLTRB(
                display.dp(16),
                display.dp(14),
                display.dp(16),
                display.dp(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  KdsSegmentControl<BoardDining>(
                    items: BoardShell._diningOrder,
                    selected: dining,
                    onChanged: onDiningChanged,
                    labelOf: (d) {
                      final count = diningCounts[d.apiValue] ?? 0;
                      return count > 0 && d != BoardDining.all
                          ? '${d.label} $count'
                          : d.label;
                    },
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      child: Row(
                        children: [
                          KdsFilterChip(
                            label: '全部',
                            selected: extra == null,
                            onTap: () => onExtraSelected(null),
                          ),
                          for (final e in BoardExtraFilter.values)
                            KdsFilterChip(
                              label: e.label,
                              selected: extra == e,
                              onTap: () => onExtraSelected(e),
                              badge: extraCounts[e.apiValue],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (showZoom) ...[
                    const Icon(Icons.zoom_out,
                        size: 20, color: KdsColors.textSecondary),
                    SizedBox(
                      width: 110,
                      child: Slider(
                        key: const ValueKey('card-scale-slider'),
                        value: cardScale!,
                        min: 0.7,
                        max: 1.6,
                        onChanged: onCardScaleChanged,
                        onChangeEnd: onCardScaleChangeEnd,
                      ),
                    ),
                    const Icon(Icons.zoom_in,
                        size: 20, color: KdsColors.textSecondary),
                    const SizedBox(width: 6),
                  ],
                  KdsSortButton(
                    label: sortMode.label,
                    onSelected: (v) {
                      final mode =
                          BoardSortMode.values.firstWhere((m) => m.name == v);
                      onSortChanged?.call(mode);
                    },
                    options: [
                      for (final m in BoardSortMode.values) (m.name, m.label),
                    ],
                  ),
                  const SizedBox(width: 6),
                  KdsViewToggle(
                      isDishView: isDishView, onChanged: onViewChanged),
                  KdsCollapseButton(onPressed: onCollapseToggle),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
