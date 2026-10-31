import 'package:flutter/material.dart';

import '../../../core/cashier_operation_audit.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 本地核心操作审计日志查看页。
///
/// 数据来自 CashierOperationAuditStore（cashier_audit.db），
/// 展示收银端核心操作（下单/结账/退款/充值/当班/营业开关/配置变更等）。
class CashierOperationAuditPage extends StatefulWidget {
  const CashierOperationAuditPage({super.key});

  @override
  State<CashierOperationAuditPage> createState() =>
      _CashierOperationAuditPageState();
}

class _CashierOperationAuditPageState extends State<CashierOperationAuditPage> {
  static const _pageSize = 60;

  final List<CashierOperationAuditEntry> _entries = [];
  String? _moduleFilter;
  String? _resultFilter;
  bool _loading = true;
  bool _hasMore = true;
  bool _loadMorePending = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _entries.clear();
      _hasMore = true;
    });
    final entries = CashierOperationAuditStore.instance.query(
      module: _moduleFilter,
      result: _resultFilter,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _entries.addAll(entries);
      _hasMore = entries.length >= _pageSize;
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadMorePending || !_hasMore) return;
    _loadMorePending = true;
    final last = _entries.isEmpty ? null : _entries.last;
    final more = CashierOperationAuditStore.instance.query(
      module: _moduleFilter,
      result: _resultFilter,
      limit: _pageSize,
      beforeMs: last?.occurredAtMs,
    );
    if (!mounted) return;
    setState(() {
      _entries.addAll(more);
      _hasMore = more.length >= _pageSize;
      _loadMorePending = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.cashier;
    return Scaffold(
      backgroundColor: theme.canvas,
      appBar: AppBar(
        backgroundColor: theme.surface,
        foregroundColor: theme.ink,
        title: const Text('操作日志（本地）'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _reload,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(theme),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? _buildEmpty(theme)
                    : _buildList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(CashierTokens theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: _filterChip(
              theme: theme,
              label: '全部模块',
              value: _moduleFilter,
              options: const [
                'auth', 'shop', 'pos', 'order', 'member', 'shift',
                'settings', 'dish', 'print', 'db',
              ],
              onSelected: (value) {
                setState(() => _moduleFilter = value);
                _reload();
              },
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _filterChip(
              theme: theme,
              label: '全部结果',
              value: _resultFilter,
              options: const ['success', 'failed'],
              onSelected: (value) {
                setState(() => _resultFilter = value);
                _reload();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required CashierTokens theme,
    required String label,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onSelected,
  }) {
    return PopupMenuButton<String?>(
      initialValue: value,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem<String?>(value: null, child: Text(label)),
        for (final option in options)
          PopupMenuItem<String?>(value: option, child: Text(option)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.border, width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              value == null ? label : '$label：$value',
              style: TextStyle(fontSize: 13, color: theme.ink),
            ),
            Icon(Icons.arrow_drop_down, size: 18, color: theme.inkMuted),
          ],
        ),
      ),
    );
  }

  Widget _buildList(CashierTokens theme) {
    return ListView.separated(
      itemCount: _entries.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 1),
      itemBuilder: (context, index) {
        if (index == _entries.length) {
          if (!_hasMore) return const SizedBox(height: 24);
          _loadMore();
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final entry = _entries[index];
        return _buildTile(theme, entry);
      },
    );
  }

  Widget _buildTile(CashierTokens theme, CashierOperationAuditEntry entry) {
    final failed = entry.result != 'success';
    return InkWell(
      onTap: () => _showDetail(entry),
      child: Container(
        color: theme.surface,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: failed
                              ? theme.danger.withValues(alpha: 0.12)
                              : theme.selected.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${entry.module}.${entry.action}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: failed ? theme.danger : theme.selected,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(entry.occurredAt),
                        style: TextStyle(fontSize: 11, color: theme.inkMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (entry.actorName != null && entry.actorName!.isNotEmpty)
                        '操作人 ${entry.actorName}',
                      if (entry.targetType != null)
                        '${entry.targetType} ${entry.targetId ?? ''}',
                      if (entry.amountFen != null)
                        '¥${(entry.amountFen! / 100).toStringAsFixed(2)}',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: theme.ink),
                  ),
                ],
              ),
            ),
            Icon(
              failed ? Icons.error_outline : Icons.check_circle_outline,
              size: 16,
              color: failed ? theme.danger : theme.selected,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(CashierTokens theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 44, color: theme.inkMuted),
          const SizedBox(height: 8),
          Text(
            '暂无操作日志\n登录后执行下单、结账、退款、当班等操作会产生记录',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: theme.inkMuted, height: 1.6),
          ),
        ],
      ),
    );
  }

  void _showDetail(CashierOperationAuditEntry entry) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${entry.module}.${entry.action}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow('结果', entry.result),
              _detailRow('操作人', entry.actorName ?? '-'),
              _detailRow('门店ID', '${entry.shopId}'),
              _detailRow(
                '目标',
                entry.targetType == null
                    ? '-'
                    : '${entry.targetType} ${entry.targetId ?? ''}',
              ),
              _detailRow(
                '金额',
                entry.amountFen == null
                    ? '-'
                    : '¥${(entry.amountFen! / 100).toStringAsFixed(2)}',
              ),
              _detailRow('错误码', entry.errorCode ?? '-'),
              if (entry.errorMsg != null && entry.errorMsg!.isNotEmpty)
                _detailRow('错误信息', entry.errorMsg!),
              _detailRow('发生时间', _formatTime(entry.occurredAt)),
              if (entry.detail != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '详情：\n${entry.detailJson}',
                    style: const TextStyle(fontSize: 12, height: 1.5),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label：',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
        style: const TextStyle(fontSize: 12, height: 1.5),
      ),
    );
  }

  String _formatTime(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
