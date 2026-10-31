import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:kds_app/core/storage/kds_file_logger.dart';
import 'package:kds_app/core/storage/kds_live_log.dart';
import 'package:kds_app/core/theme/kds_theme.dart';
import 'package:kds_app/features/auth/session_provider.dart';
import 'package:kds_app/features/diagnostics/kds_inspector_modal.dart';

enum LogFilter { all, ws, warnError }

class LiveLogState {
  const LiveLogState({
    this.entries = const [],
    this.filter = LogFilter.all,
    this.autoScroll = true,
  });

  final List<KdsLiveLogEntry> entries;
  final LogFilter filter;
  final bool autoScroll;

  LiveLogState copyWith({
    List<KdsLiveLogEntry>? entries,
    LogFilter? filter,
    bool? autoScroll,
  }) {
    return LiveLogState(
      entries: entries ?? this.entries,
      filter: filter ?? this.filter,
      autoScroll: autoScroll ?? this.autoScroll,
    );
  }

  List<KdsLiveLogEntry> get visibleEntries {
    return switch (filter) {
      LogFilter.all => entries,
      LogFilter.ws => entries.where((e) => e.isWs).toList(),
      LogFilter.warnError =>
        entries.where((e) => e.level == 'W' || e.level == 'E').toList(),
    };
  }
}

class LiveLogController extends Notifier<LiveLogState> {
  StreamSubscription<KdsLiveLogEntry>? _sub;

  @override
  LiveLogState build() {
    _sub?.cancel();
    _sub = KdsLiveLog.stream.listen((entry) {
      final next = [...state.entries, entry];
      if (next.length > KdsLiveLog.maxEntries) {
        next.removeRange(0, next.length - KdsLiveLog.maxEntries);
      }
      state = state.copyWith(entries: next);
    });
    ref.onDispose(() => _sub?.cancel());
    return LiveLogState(entries: List<KdsLiveLogEntry>.from(KdsLiveLog.buffer));
  }

  void setFilter(LogFilter filter) => state = state.copyWith(filter: filter);

  void setAutoScroll(bool value) => state = state.copyWith(autoScroll: value);

  void clear() {
    KdsLiveLog.clear();
    state =
        state.copyWith(entries: List<KdsLiveLogEntry>.from(KdsLiveLog.buffer));
  }
}

final liveLogControllerProvider =
    NotifierProvider<LiveLogController, LiveLogState>(LiveLogController.new);

class KdsLiveLogPage extends ConsumerStatefulWidget {
  const KdsLiveLogPage({super.key});

  @override
  ConsumerState<KdsLiveLogPage> createState() => _KdsLiveLogPageState();
}

class _KdsLiveLogPageState extends ConsumerState<KdsLiveLogPage> {
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // 访问审计：打开日志页
    KdsFileLogger.info('[PAGE] 打开实时日志页');
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottomIfNeeded(bool autoScroll) {
    if (!autoScroll || !_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final logState = ref.watch(liveLogControllerProvider);
    final ctrl = ref.read(liveLogControllerProvider.notifier);
    final wsOnline = ref.watch(wsConnectedProvider);
    final visible = logState.visibleEntries;

    ref.listen<LiveLogState>(liveLogControllerProvider, (prev, next) {
      if (prev?.entries.length != next.entries.length) {
        _scrollToBottomIfNeeded(next.autoScroll);
      }
    });

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E1E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2D2D2D),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            const Text('实时日志'),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: wsOnline ? KdsColors.wsOnline : Colors.grey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                wsOnline ? 'WS 在线' : 'WS 离线',
                style: const TextStyle(fontSize: 12, color: Colors.white),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: '全链路探测中心',
            icon: const Icon(Icons.radar_rounded, color: Color(0xFF00D2FC)),
            onPressed: () => showKdsInspectorModal(context),
          ),
          IconButton(
            tooltip: '复制全部',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () => _copyAll(visible),
          ),
          IconButton(
            tooltip: '清空',
            icon: const Icon(Icons.delete_outline),
            onPressed: ctrl.clear,
          ),
        ],
      ),
      body: Column(
        children: [
          Material(
            color: const Color(0xFF2D2D2D),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  _FilterChip(
                    label: '全部',
                    selected: logState.filter == LogFilter.all,
                    onTap: () => ctrl.setFilter(LogFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: 'WS',
                    selected: logState.filter == LogFilter.ws,
                    onTap: () => ctrl.setFilter(LogFilter.ws),
                  ),
                  const SizedBox(width: 8),
                  _FilterChip(
                    label: '告警',
                    selected: logState.filter == LogFilter.warnError,
                    onTap: () => ctrl.setFilter(LogFilter.warnError),
                  ),
                  const Spacer(),
                  Text(
                    '${visible.length} 条',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('自动滚底', style: TextStyle(fontSize: 12)),
                    selected: logState.autoScroll,
                    onSelected: ctrl.setAutoScroll,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? const Center(
                    child: Text(
                      '暂无日志\n登录后 WS 连接、下单推送会在此显示',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.5),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final entry = visible[index];
                      return _LogLine(
                        entry: entry,
                        onLongPress: () => _copyLine(entry),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyLine(KdsLiveLogEntry entry) async {
    final text = _formatLine(entry);
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制该行'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _copyAll(List<KdsLiveLogEntry> entries) async {
    if (entries.isEmpty) return;
    final text = entries.map(_formatLine).join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${entries.length} 条日志')),
      );
    }
  }

  String _formatLine(KdsLiveLogEntry entry) {
    final t = entry.time;
    final ts =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 100).toString()}';
    return '$ts [${entry.level}] ${entry.message}';
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      selectedColor: KdsColors.headerTakeout.withValues(alpha: 0.35),
    );
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.entry, this.onLongPress});

  final KdsLiveLogEntry entry;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = entry.time;
    final ts =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}.${(t.millisecond ~/ 100).toString()}';
    final color = switch (entry.level) {
      'E' => const Color(0xFFFF6B6B),
      'W' => const Color(0xFFFFB347),
      'D' => const Color(0xFF888888),
      _ => entry.isWs ? const Color(0xFF7EC8E3) : const Color(0xFFE8E8E8),
    };

    return GestureDetector(
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: SelectableText.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$ts ',
                style: const TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
              TextSpan(
                text: '[${entry.level}] ',
                style: TextStyle(
                    color: color.withValues(alpha: 0.85),
                    fontSize: 11,
                    fontFamily: 'monospace'),
              ),
              TextSpan(
                text: entry.message,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
