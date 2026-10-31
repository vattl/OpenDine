import 'package:flutter/material.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/pos_repository.dart';
import '../domain/pos_models.dart';

Future<PosReceiptPrintType?> showPosReceiptPrintDialog(
  BuildContext context, {
  required PosOrder order,
  required bool settled,
}) {
  return showDialog<PosReceiptPrintType>(
    context: context,
    barrierColor: context.cashier.overlayScrim,
    builder: (_) => _PosReceiptPrintDialog(order: order, settled: settled),
  );
}

class _PosReceiptPrintDialog extends StatefulWidget {
  const _PosReceiptPrintDialog({required this.order, required this.settled});

  final PosOrder order;
  final bool settled;

  @override
  State<_PosReceiptPrintDialog> createState() => _PosReceiptPrintDialogState();
}

class _PosReceiptPrintDialogState extends State<_PosReceiptPrintDialog> {
  PosReceiptPrintType selected = PosReceiptPrintType.front;

  List<_ReceiptOption> get options => [
    const _ReceiptOption(
      type: PosReceiptPrintType.front,
      title: '前台小票',
      description: '打印当前订单完整明细，用于前台核对',
      badge: '前台打印机',
      icon: Icons.receipt_long_outlined,
    ),
    const _ReceiptOption(
      type: PosReceiptPrintType.kitchen,
      title: '厨房小票',
      description: '补打本单厨房制作联，按出品档口分单',
      badge: '厨房打印机',
      icon: Icons.soup_kitchen_outlined,
    ),
    _ReceiptOption(
      type: PosReceiptPrintType.preCheckout,
      title: '预结单',
      description: widget.settled ? '订单已结账，无需再打印预结单' : '未结账核对凭证，不展示实付渠道',
      badge: widget.settled ? '结账后不可用' : '当前可打印',
      icon: Icons.request_quote_outlined,
      enabled: !widget.settled,
    ),
    _ReceiptOption(
      type: PosReceiptPrintType.checkout,
      title: '结账单',
      description: widget.settled ? '打印本单最终收款凭证' : '订单完成结账后方可打印',
      badge: widget.settled ? '当前可打印' : '暂不可用',
      icon: Icons.task_alt_outlined,
      enabled: widget.settled,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Dialog(
      key: const Key('receipt-print-dialog'),
      backgroundColor: tokens.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      elevation: 24,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 540,
          maxHeight: MediaQuery.sizeOf(context).height - 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '选择打印小票',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: tokens.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${widget.order.tableNumber}号桌 · 订单 ${widget.order.orderNo}',
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: const Key('receipt-print-close'),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    style: IconButton.styleFrom(
                      backgroundColor: tokens.subtle,
                      foregroundColor: tokens.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.border),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '请选择本次要打印的票据',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: tokens.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (var index = 0; index < options.length; index++) ...[
                      _ReceiptOptionTile(
                        option: options[index],
                        selected: selected == options[index].type,
                        autofocus: index == 0,
                        onSelected: () =>
                            setState(() => selected = options[index].type),
                      ),
                      if (index != options.length - 1)
                        const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.warningBackground,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        widget.settled
                            ? '提示：订单已结账，可打印最终结账凭证。'
                            : '提示：预结单仅用于结账前核对，不作为收款凭证。',
                        style: TextStyle(fontSize: 12, color: tokens.warning),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 22),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    key: const Key('receipt-print-cancel'),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    key: const Key('receipt-print-confirm'),
                    onPressed: () => Navigator.of(context).pop(selected),
                    child: const Text('确认打印'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptOption {
  const _ReceiptOption({
    required this.type,
    required this.title,
    required this.description,
    required this.badge,
    required this.icon,
    this.enabled = true,
  });

  final PosReceiptPrintType type;
  final String title;
  final String description;
  final String badge;
  final IconData icon;
  final bool enabled;
}

class _ReceiptOptionTile extends StatelessWidget {
  const _ReceiptOptionTile({
    required this.option,
    required this.selected,
    required this.autofocus,
    required this.onSelected,
  });

  final _ReceiptOption option;
  final bool selected;
  final bool autofocus;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final foreground = option.enabled ? tokens.ink : tokens.disabledForeground;
    final borderColor = selected ? tokens.selected : tokens.border;
    return Semantics(
      button: true,
      selected: selected,
      enabled: option.enabled,
      label: '${option.title}，${option.description}，${option.badge}',
      child: Material(
        color: option.enabled
            ? (selected ? tokens.selectedBackground : tokens.surface)
            : tokens.disabledBackground,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('receipt-print-option-${option.type.name}'),
          autofocus: autofocus,
          onTap: option.enabled ? onSelected : null,
          focusColor: tokens.selectedBackground,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 78),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: option.enabled
                          ? tokens.selectedBackground
                          : tokens.disabledBackground,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      option.icon,
                      color: option.enabled
                          ? tokens.selected
                          : tokens.disabledForeground,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          option.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          option.description,
                          style: TextStyle(
                            fontSize: 12,
                            color: option.enabled
                                ? tokens.inkMuted
                                : tokens.disabledForeground,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: option.enabled
                          ? tokens.successBackground
                          : tokens.subtle,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      option.badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: option.enabled
                            ? tokens.success
                            : tokens.disabledForeground,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                    color: selected
                        ? tokens.selected
                        : tokens.disabledForeground,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
