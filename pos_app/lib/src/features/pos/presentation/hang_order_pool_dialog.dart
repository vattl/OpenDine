import 'package:flutter/material.dart';

import '../data/pos_repository.dart';
import 'pos_notice_dialog.dart';

Future<void> showHangOrderPoolDialog(
  BuildContext context, {
  required PosRepository repository,
  required ValueChanged<HangOrderSummary> onUnhangOrder,
  void Function(HangOrderSummary item)? onCancelOrder,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => HangOrderPoolDialog(
      repository: repository,
      onUnhangOrder: onUnhangOrder,
      onCancelOrder: onCancelOrder,
    ),
  );
}

class HangOrderPoolDialog extends StatefulWidget {
  const HangOrderPoolDialog({
    super.key,
    required this.repository,
    required this.onUnhangOrder,
    this.onCancelOrder,
  });

  final PosRepository repository;
  final ValueChanged<HangOrderSummary> onUnhangOrder;
  final void Function(HangOrderSummary item)? onCancelOrder;

  @override
  State<HangOrderPoolDialog> createState() => _HangOrderPoolDialogState();
}

class _HangOrderPoolDialogState extends State<HangOrderPoolDialog> {
  bool _loading = true;
  String? _error;
  List<HangOrderSummary> _items = const [];
  String? _operatingOrderNo;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    try {
      final list = await widget.repository.getHangList();
      if (!mounted) return;
      setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    await _fetchData();
  }

  Future<void> _handleUnhang(HangOrderSummary item) async {
    setState(() => _operatingOrderNo = item.orderNo);
    try {
      final success = await widget.repository.unhangOrder(orderNo: item.orderNo);
      if (!mounted) return;
      if (success) {
        Navigator.of(context).pop();
        widget.onUnhangOrder(item);
      } else {
        await showPosNotice(
          context,
          title: '取单失败',
          message: '未能取回该订单，可能已被其他收银端操作，请刷新后重试。',
          tone: PosNoticeTone.error,
        );
        _loadData();
      }
    } catch (e) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '取单失败',
        message: e.toString().replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
      _loadData();
    } finally {
      if (mounted) {
        setState(() => _operatingOrderNo = null);
      }
    }
  }

  Future<void> _handleCancel(HangOrderSummary item) async {
    final confirmed = await showPosNotice(
      context,
      title: '作废挂单确认',
      message: '确定要作废订单 ${item.orderNo}（桌号: ${item.tableNumber.isNotEmpty ? item.tableNumber : "外带单"}）吗？作废后不可恢复。',
      tone: PosNoticeTone.warning,
      primaryLabel: '确认作废',
      secondaryLabel: '取消',
    );
    if (!confirmed || !mounted) return;

    if (widget.onCancelOrder != null) {
      Navigator.of(context).pop();
      widget.onCancelOrder!(item);
      return;
    }

    setState(() => _operatingOrderNo = item.orderNo);
    try {
      await widget.repository.clearTable(item.tableNumber);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已作废订单 ${item.orderNo}')),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      await showPosNotice(
        context,
        title: '作废失败',
        message: e.toString().replaceFirst('Exception: ', ''),
        tone: PosNoticeTone.error,
      );
      _loadData();
    } finally {
      if (mounted) {
        setState(() => _operatingOrderNo = null);
      }
    }
  }

  Widget _buildDurationBadge(int minutes) {
    Color bg;
    Color fg;
    String label;
    if (minutes > 30) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFDC2626);
      label = '$minutes分钟 (超时)';
    } else if (minutes >= 15) {
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFFD97706);
      label = '$minutes分钟';
    } else {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF475569);
      label = '$minutes分钟';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 820,
          minWidth: 680,
          maxHeight: 620,
          minHeight: 400,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2FE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFF0284C7),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '门店挂单池',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 8),
                            if (!_loading && _error == null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '共 ${_items.length} 笔挂单',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '点击【取单结账】将立即载入单据所有菜品并滑出收款界面',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('hang-pool-refresh-button'),
                    tooltip: '刷新挂单池',
                    onPressed: _loading ? null : _loadData,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: const Key('hang-pool-close-button'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Divider(height: 24),
              Expanded(
                child: _buildContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text('加载挂单池失败：$_error', style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(
              '当前门店无任何挂起订单',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: DataTable(
        horizontalMargin: 12,
        columnSpacing: 16,
        headingRowHeight: 42,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 64,
        columns: const [
          DataColumn(label: Text('桌号 / 单号', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('人数 / 金额', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('挂单时长', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('挂单原因', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('操作', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: [
          for (final item in _items)
            DataRow(
              key: ValueKey(item.orderNo),
              cells: [
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        item.tableNumber.isNotEmpty ? item.tableNumber : '外带单',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0284C7),
                        ),
                      ),
                      Text(
                        item.orderNo,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                DataCell(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${item.numberOfDiners} 人',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                      Text(
                        '¥${item.settAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(_buildDurationBadge(item.hangMinutes)),
                DataCell(
                  Text(
                    item.hangReason?.isNotEmpty == true ? item.hangReason! : '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        key: Key('unhang-btn-${item.orderNo}'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _operatingOrderNo == item.orderNo
                            ? null
                            : () => _handleUnhang(item),
                        child: _operatingOrderNo == item.orderNo
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('取单结账', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        key: Key('cancel-hang-btn-${item.orderNo}'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFFECACA)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _operatingOrderNo == item.orderNo
                            ? null
                            : () => _handleCancel(item),
                        child: const Text('作废', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
