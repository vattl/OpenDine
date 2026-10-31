import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kds_app/core/theme/kds_theme.dart';

/// WebSocket 连接状态指示灯。
///
/// 传入 [lastEventAtMs] 时叠加"最近业务事件"新鲜度：
/// 连接正常但超过 [_staleThreshold] 没有业务事件时，指示灯变黄并显示
/// 无事件时长，用于现场区分"socket 连着但收银端没有推送"。
class KdsWsIndicator extends StatefulWidget {
  const KdsWsIndicator({
    super.key,
    required this.connected,
    this.size = 10,
    this.onTap,
    this.lastEventAtMs,
  });

  final bool connected;
  final double size;
  final VoidCallback? onTap;

  /// 最近一次收到业务事件的本地毫秒时间；null 表示不展示事件新鲜度。
  final int? lastEventAtMs;

  static const staleThreshold = Duration(seconds: 90);

  @override
  State<KdsWsIndicator> createState() => _KdsWsIndicatorState();
}

class _KdsWsIndicatorState extends State<KdsWsIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant KdsWsIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.lastEventAtMs == null) != (widget.lastEventAtMs == null)) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    _ticker?.cancel();
    _ticker = null;
    if (widget.lastEventAtMs != null) {
      // 周期刷新"无事件时长"文案；事件到达本身会触发父级重建。
      _ticker = Timer.periodic(const Duration(seconds: 15), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _formatClock(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _formatAge(int ageSec) {
    if (ageSec < 120) return '${ageSec}s';
    return '${ageSec ~/ 60}分钟';
  }

  @override
  Widget build(BuildContext context) {
    final lastEventAtMs = widget.lastEventAtMs;
    final ageSec = lastEventAtMs == null
        ? null
        : ((DateTime.now().millisecondsSinceEpoch - lastEventAtMs) ~/ 1000)
            .clamp(0, 1 << 31);
    final stale = widget.connected &&
        ageSec != null &&
        ageSec >= KdsWsIndicator.staleThreshold.inSeconds;
    final dotColor = !widget.connected
        ? KdsColors.wsOffline
        : (stale ? KdsColors.rushGold : KdsColors.wsOnline);

    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: dotColor,
        boxShadow: widget.connected
            ? [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.45),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );

    final tooltip = StringBuffer(
        widget.connected ? 'WS 已连接' : 'WS 未连接');
    if (lastEventAtMs != null) {
      tooltip.write(' · 最近业务事件 ${_formatClock(lastEventAtMs)}');
      if (stale) tooltip.write('（${_formatAge(ageSec)}无事件）');
    }
    if (widget.onTap != null) tooltip.write(' · 点击查看日志');

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        if (lastEventAtMs != null && ageSec != null) ...[
          const SizedBox(width: 5),
          Text(
            stale ? '${_formatAge(ageSec)}无事件' : _formatClock(lastEventAtMs),
            style: TextStyle(
              fontSize: 11,
              fontWeight: stale ? FontWeight.w700 : FontWeight.w400,
              color: stale ? KdsColors.rushGold : KdsColors.topBarMuted,
            ),
          ),
        ],
      ],
    );

    return Tooltip(
      message: tooltip.toString(),
      child: widget.onTap == null
          ? content
          : Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                customBorder: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: content,
                ),
              ),
            ),
    );
  }
}
