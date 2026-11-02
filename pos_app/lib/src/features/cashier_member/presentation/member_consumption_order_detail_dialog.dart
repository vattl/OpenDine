import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_design_tokens.dart';
import '../data/cashier_member_repository.dart';
import '../domain/cashier_member.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class MemberConsumptionOrderDetailDialog extends StatefulWidget {
  const MemberConsumptionOrderDetailDialog({
    super.key,
    required this.record,
    required this.repository,
  });

  final MemberConsumptionRecord record;
  final CashierMemberRepository repository;

  @override
  State<MemberConsumptionOrderDetailDialog> createState() =>
      _MemberConsumptionOrderDetailDialogState();
}

class _MemberConsumptionOrderDetailDialogState
    extends State<MemberConsumptionOrderDetailDialog> {
  late Future<MemberConsumptionDetail> detail;

  @override
  void initState() {
    super.initState();
    detail = widget.repository.loadConsumptionDetail(widget.record);
  }

  void _retry() {
    setState(() {
      detail = widget.repository.loadConsumptionDetail(widget.record);
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    return Dialog(
      key: const Key('member-consumption-order-detail-dialog'),
      insetPadding: const EdgeInsets.all(32),
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: math.min(920, viewport.width - 64),
        height: math.min(650, viewport.height - 64),
        child: Column(
          children: [
            _DetailHeader(
              orderNo: widget.record.orderNo,
              onClose: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: FutureBuilder<MemberConsumptionDetail>(
                future: detail,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const _DetailLoading();
                  }
                  if (snapshot.hasError) {
                    return _DetailError(onRetry: _retry);
                  }
                  final value = snapshot.data!;
                  return _DetailBody(detail: value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.orderNo, required this.onClose});

  final String orderNo;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      color: context.cashier.ink,
      padding: const EdgeInsets.only(left: 24, right: 8),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Text(
            '订单明细',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              orderNo,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xffd4d4d4), fontSize: 15),
            ),
          ),
          IconButton(
            key: const Key('member-consumption-order-detail-close'),
            tooltip: '关闭订单明细',
            onPressed: onClose,
            icon: const Icon(Icons.close, color: Colors.white, size: 24),
          ),
        ],
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.detail});

  final MemberConsumptionDetail detail;

  @override
  Widget build(BuildContext context) {
    final record = detail.record;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              _SummaryItem(
                label: '订单号',
                value: record.orderNo,
              ),
              const SizedBox(width: 12),
              _SummaryItem(
                label: '就餐类型',
                value: _orderTypeLabel(record.orderType),
              ),
              const SizedBox(width: 12),
              _SummaryItem(
                label: '桌号',
                value: record.tableNumber.isEmpty ? '--' : record.tableNumber,
              ),
              const SizedBox(width: 12),
              _SummaryItem(
                label: '支付方式',
                value: _paymentLabel(record.paymentMethod),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _LineHeader(),
          Expanded(
            child: detail.lines.isEmpty
                ? Center(
                    child: Text(
                      '该订单暂无菜品明细',
                      style: TextStyle(
                        fontSize: 16,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const Key('member-consumption-order-detail-list'),
                    itemCount: detail.lines.length,
                    itemBuilder: (context, index) => _LineRow(
                      line: detail.lines[index],
                      shaded: index.isOdd,
                    ),
                  ),
          ),
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: const Color(0xfffff7f7),
              border: Border.all(color: const Color(0xffffdddd)),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '实付金额：',
                  style: TextStyle(
                    fontSize: 16,
                    color: context.cashier.ink,
                  ),
                ),
                Text(
                  _money(record.amount),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: context.cashier.danger,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.cashier.canvas,
          borderRadius: BorderRadius.circular(CashierMetrics.controlRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: context.cashier.inkMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.cashier.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineHeader extends StatelessWidget {
  const _LineHeader();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: context.cashier.inkMuted,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    );
    return Container(
      height: 48,
      color: context.cashier.row,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _LineCell(flex: 5, child: Text('菜品', style: style)),
          _LineCell(flex: 4, child: Text('规格', style: style)),
          _LineCell(flex: 3, child: Text('单价', style: style)),
          _LineCell(flex: 2, child: Text('数量', style: style)),
          _LineCell(flex: 3, child: Text('小计', style: style)),
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.shaded});

  final MemberConsumptionLine line;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: context.cashier.ink, fontSize: 14);
    return Container(
      key: Key('member-consumption-detail-line-${line.id}'),
      height: 56,
      color: shaded ? context.cashier.row : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          _LineCell(
            flex: 5,
            child: Text(
              line.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          _LineCell(
            flex: 4,
            child: Text(
              _specificationLabel(line.specification),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style.copyWith(color: context.cashier.inkMuted),
            ),
          ),
          _LineCell(flex: 3, child: Text(_money(line.unitPrice), style: style)),
          _LineCell(
            flex: 2,
            child: Text('${line.quantity}${line.unit}', style: style),
          ),
          _LineCell(
            flex: 3,
            child: Text(
              _money(line.totalPrice),
              style: style.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineCell extends StatelessWidget {
  const _LineCell({required this.flex, required this.child});

  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Center(child: child),
    );
  }
}

class _DetailLoading extends StatelessWidget {
  const _DetailLoading();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: context.cashier.selected),
          const SizedBox(height: 14),
          const Text('正在加载订单明细…', style: TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: context.cashier.danger,
          ),
          const SizedBox(height: 14),
          const Text('订单明细加载失败', style: TextStyle(fontSize: 16)),
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('member-consumption-order-detail-retry'),
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              minimumSize: const Size(150, 48),
              backgroundColor: context.cashier.ink,
            ),
            child: const Text('重新加载', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

String _money(double amount) => '¥${amount.toStringAsFixed(2)}';

String _paymentLabel(String value) {
  return switch (value.trim().toLowerCase()) {
    'wechat' => '微信支付',
    'alipay' => '支付宝',
    'cash' => '现金支付',
    'balance' => '会员余额',
    '' => '--',
    _ => value,
  };
}

String _orderTypeLabel(String value) {
  final type = value.trim();
  if (type.isEmpty) return '--';
  return switch (type.toLowerCase()) {
    'dinein' || 'dine_in' || 'dine-in' => '堂食',
    'takeout' || 'delivery' => '外卖',
    'pickup' || 'packed' || 'packing' => '自提',
    _ => type,
  };
}

String _specificationLabel(String value) {
  final text = value.trim();
  if (text.isEmpty) return '--';
  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      final values = <String>[];
      _collectSpecificationValues(jsonDecode(text), values);
      if (values.isNotEmpty) return values.join(' / ');
    } on FormatException {
      // Fall through for historical non-standard specification strings.
    }
  }
  final values = text
      .split(RegExp(r'\s*(?:/|,|，|;|；)\s*'))
      .map((part) {
        final normalized = part
            .replaceAll(RegExp(r'^[\s\{\}\[\]"]+|[\s\{\}\[\]"]+$'), '')
            .trim();
        final colon = normalized.indexOf(RegExp(r'[:：]'));
        return colon < 0 ? normalized : normalized.substring(colon + 1).trim();
      })
      .where((part) => part.isNotEmpty)
      .toSet()
      .toList(growable: false);
  return values.isEmpty ? '--' : values.join(' / ');
}

void _collectSpecificationValues(Object? value, List<String> result) {
  if (value is Map) {
    for (final item in value.values) {
      _collectSpecificationValues(item, result);
    }
    return;
  }
  if (value is Iterable) {
    for (final item in value) {
      _collectSpecificationValues(item, result);
    }
    return;
  }
  final text = '$value'.trim();
  if (text.isNotEmpty && text != 'null' && !result.contains(text)) {
    result.add(text);
  }
}
