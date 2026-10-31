import 'package:flutter/material.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';
import 'package:kds_app/core/theme/kds_theme.dart';

class KdsQueueTasksDialog extends StatelessWidget {
  const KdsQueueTasksDialog({
    super.key,
    required this.tasks,
    required this.pendingCount,
  });

  final List<KdsV2OptimisticOverlay> tasks;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final ordered = [...tasks]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final contentHeight =
        (MediaQuery.sizeOf(context).height * 0.68).clamp(280.0, 520.0);
    return AlertDialog(
      key: const ValueKey('queue-tasks-dialog'),
      backgroundColor: KdsColors.shellBg,
      surfaceTintColor: Colors.transparent,
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 16, 12),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      title: Row(
        children: [
          const Icon(Icons.pending_actions_outlined, color: KdsColors.rushGold),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              '队列任务',
              style: TextStyle(
                color: KdsColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _CountBadge(count: pendingCount),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: contentHeight,
        child: ordered.isEmpty
            ? const _EmptyQueueState()
            : ListView.separated(
                key: const ValueKey('queue-tasks-list'),
                itemCount: ordered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _QueueTaskCard(task: ordered[index]),
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close),
          label: const Text('关闭'),
        ),
      ],
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: count > 0
              ? KdsColors.rushGold.withValues(alpha: 0.16)
              : KdsColors.segmentBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: count > 0 ? KdsColors.rushGold : KdsColors.textMuted,
          ),
        ),
        child: Text(
          count > 0 ? '$count 项待处理' : '0 项待处理',
          style: TextStyle(
            color: count > 0 ? KdsColors.rushGold : KdsColors.textSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _EmptyQueueState extends StatelessWidget {
  const _EmptyQueueState();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.task_alt, size: 52, color: KdsColors.wsOnline),
            SizedBox(height: 14),
            Text(
              '队列为空',
              style: TextStyle(
                color: KdsColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '所有操作均已获得权威端确认，无待同步或待查证任务。',
              textAlign: TextAlign.center,
              style: TextStyle(color: KdsColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
}

class _QueueTaskCard extends StatelessWidget {
  const _QueueTaskCard({required this.task});

  final KdsV2OptimisticOverlay task;

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(task.status);
    final route = task.fromQueue == null
        ? null
        : '${_queueLabel(task.fromQueue!)} → ${_queueLabel(task.toQueue)}';
    return Container(
      key: ValueKey('queue-task-${task.commandId}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: KdsColors.topBarBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _commandLabel(task.commandType),
                  style: const TextStyle(
                    color: KdsColors.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _StatusBadge(label: task.status.label, color: statusColor),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_targetLabel(task.target)}${task.quantity == null ? '' : ' · 数量 ${task.quantity}'}${route == null ? '' : ' · $route'}',
            style:
                const TextStyle(color: KdsColors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 6),
          Text(
            '${_clock(task.createdAt)} · ${_channelLabel(task.originChannel)} · 已尝试 ${task.retryCount} 次',
            style: const TextStyle(color: KdsColors.textMuted, fontSize: 12),
          ),
          if (task.requiresResolution) ...[
            const SizedBox(height: 6),
            const Text(
              '等待云端账本裁决，系统不会盲目重发',
              style: TextStyle(color: KdsColors.rushGold, fontSize: 13),
            ),
          ],
          if (task.lastError case final error?
              when error.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '最近错误：$error',
              style: const TextStyle(color: Color(0xFFFFAB91), fontSize: 13),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            '命令 ID：${task.commandId}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: KdsColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );
}

Color _statusColor(KdsOverlayStatus status) => switch (status) {
      KdsOverlayStatus.persisting => KdsColors.textSecondary,
      KdsOverlayStatus.pending => KdsColors.rushGold,
      KdsOverlayStatus.sending => const Color(0xFF29B6F6),
      KdsOverlayStatus.unknown => const Color(0xFFFFA726),
      KdsOverlayStatus.conflict => const Color(0xFFEF5350),
    };

String _commandLabel(KdsV2CommandType type) => switch (type) {
      KdsV2CommandType.advanceItem || KdsV2CommandType.advanceOrder => '划菜',
      KdsV2CommandType.revokeItem => '撤回划菜',
      KdsV2CommandType.lackItem => '缺货',
      KdsV2CommandType.refundItem => '退款',
      KdsV2CommandType.rushItem || KdsV2CommandType.rushOrder => '催菜',
      KdsV2CommandType.holdItem => '挂起菜品',
      KdsV2CommandType.releaseItem => '恢复菜品',
      KdsV2CommandType.completeOrder => '完成订单',
      KdsV2CommandType.archiveOrder => '归档订单',
      KdsV2CommandType.archiveClear => '清理归档',
    };

String _targetLabel(KdsV2CommandTarget target) {
  if (target.detailId != null) return '菜品明细 #${target.detailId}';
  if (target.detailIds.isNotEmpty) return '${target.detailIds.length} 个菜品明细';
  if (target.orderId != null) return '订单 #${target.orderId}';
  return '未标明目标';
}

String _queueLabel(String? queue) => switch (queue) {
      'pending_prep' => '待配菜',
      'pending_cook' => '待制作',
      'ready_serve' => '待传菜',
      'done' => '已完成',
      null || '' => '下一队列',
      _ => queue,
    };

String _channelLabel(String? channel) => switch (channel) {
      'cloud' => '云端',
      'lan' => '收银代理',
      _ => '通道待定',
    };

String _clock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}:${value.second.toString().padLeft(2, '0')}';
