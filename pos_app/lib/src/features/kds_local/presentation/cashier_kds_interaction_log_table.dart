import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/cashier_kds_interaction_log.dart';

/// Request-level audit for traffic that entered through the cashier LAN proxy.
class CashierKdsInteractionLogTable extends StatefulWidget {
  const CashierKdsInteractionLogTable({
    super.key,
    required this.logs,
    required this.droppedLogCount,
    this.onRefresh,
  });

  final List<CashierKdsInteractionLog> logs;
  final int droppedLogCount;
  final Future<void> Function()? onRefresh;

  @override
  State<CashierKdsInteractionLogTable> createState() =>
      _CashierKdsInteractionLogTableState();
}

class _CashierKdsInteractionLogTableState
    extends State<CashierKdsInteractionLogTable> {
  final _keywordController = TextEditingController();
  bool _problemOnly = false;

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  List<CashierKdsInteractionLog> get _filtered {
    final keyword = _keywordController.text.trim().toLowerCase();
    return widget.logs
        .where((log) {
          if (log.stage != KdsInteractionStage.proxyHttpForward &&
              log.stage != KdsInteractionStage.proxyWebSocketForward) {
            return false;
          }
          if (_problemOnly && !log.status.isProblem) return false;
          if (keyword.isEmpty) return true;
          return <String?>[
            log.deviceCode,
            log.traceId,
            log.action,
            '${log.metadata['method'] ?? ''}',
            '${log.metadata['path'] ?? ''}',
            log.errorSummary,
          ].whereType<String>().any(
            (value) => value.toLowerCase().contains(keyword),
          );
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final logs = _filtered;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '代理转发接口请求',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      const Text('仅记录经收银端 LAN 代理转发的真实 HTTP 与 WebSocket 请求。'),
                    ],
                  ),
                ),
                IconButton(
                  key: const Key('kds-proxy-request-refresh'),
                  tooltip: '手动刷新',
                  onPressed: widget.onRefresh == null
                      ? null
                      : () => widget.onRefresh!(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (widget.droppedLogCount > 0) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '本次运行有 ${widget.droppedLogCount} 条请求审计写入失败；代理请求未被阻断。',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 360,
                  child: TextField(
                    controller: _keywordController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      labelText: '设备 / 接口路径 / request_id',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                FilterChip(
                  selected: _problemOnly,
                  onSelected: (value) => setState(() => _problemOnly = value),
                  avatar: const Icon(Icons.error_outline, size: 18),
                  label: const Text('仅看异常'),
                ),
                Text('共 ${logs.length} 条'),
              ],
            ),
            const SizedBox(height: 12),
            if (logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('暂无代理转发请求')),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 44,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 64,
                  columns: const [
                    DataColumn(label: Text('接收时间')),
                    DataColumn(label: Text('KDS 设备')),
                    DataColumn(label: Text('方法')),
                    DataColumn(label: Text('接口')),
                    DataColumn(label: Text('转发结果')),
                    DataColumn(label: Text('耗时')),
                    DataColumn(label: Text('request_id')),
                  ],
                  rows: [for (final log in logs) _row(context, log)],
                ),
              ),
          ],
        ),
      ),
    );
  }

  DataRow _row(BuildContext context, CashierKdsInteractionLog log) {
    final method = '${log.metadata['method'] ?? _methodFromAction(log.action)}';
    final path = '${log.metadata['path'] ?? _pathFromAction(log.action)}';
    return DataRow(
      onSelectChanged: (_) => _showDetail(context, log),
      cells: [
        DataCell(Text(_formatTime(log.occurredAtMs))),
        DataCell(Text(log.deviceCode ?? '—')),
        DataCell(Text(method)),
        DataCell(SelectableText(path)),
        DataCell(_statusChip(context, log)),
        DataCell(Text(log.durationMs == null ? '—' : '${log.durationMs} ms')),
        DataCell(SelectableText(_shortId(log.traceId))),
      ],
    );
  }

  Widget _statusChip(BuildContext context, CashierKdsInteractionLog log) {
    final scheme = Theme.of(context).colorScheme;
    final color = log.status.isProblem
        ? scheme.errorContainer
        : scheme.primaryContainer;
    final status = log.httpStatus == null
        ? log.status.label
        : '${log.httpStatus} ${log.status.label}';
    return Chip(
      visualDensity: VisualDensity.compact,
      backgroundColor: color,
      label: Text(status),
    );
  }

  Future<void> _showDetail(
    BuildContext context,
    CashierKdsInteractionLog log,
  ) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('代理请求详情'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: SelectionArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detail('接收时间', _formatTime(log.occurredAtMs)),
                _detail('request_id', log.traceId),
                _detail('KDS 设备', log.deviceCode ?? '—'),
                _detail('方法', '${log.metadata['method'] ?? ''}'),
                _detail('接口', '${log.metadata['path'] ?? ''}'),
                _detail('转发结果', log.status.label),
                if (log.httpStatus != null)
                  _detail('HTTP 状态', '${log.httpStatus}'),
                if (log.durationMs != null)
                  _detail('耗时', '${log.durationMs} ms'),
                if (log.errorSummary != null)
                  _detail('错误摘要', log.errorSummary!),
                _detail(
                  '审计元数据',
                  const JsonEncoder.withIndent('  ').convert(log.metadata),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(value),
      ],
    ),
  );

  static String _methodFromAction(String action) {
    final separator = action.indexOf(' ');
    return separator < 0 ? action : action.substring(0, separator);
  }

  static String _pathFromAction(String action) {
    final separator = action.indexOf(' ');
    return separator < 0 ? action : action.substring(separator + 1);
  }

  static String _shortId(String value) => value.length <= 22
      ? value
      : '${value.substring(0, 10)}…${value.substring(value.length - 8)}';

  static String _formatTime(int milliseconds) {
    final value = DateTime.fromMillisecondsSinceEpoch(milliseconds).toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    String three(int number) => number.toString().padLeft(3, '0');
    return '${two(value.hour)}:${two(value.minute)}:${two(value.second)}.${three(value.millisecond)}';
  }
}
