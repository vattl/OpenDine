import 'package:flutter/material.dart';

Future<String?> showPosHangOrderDialog(
  BuildContext context, {
  required String tableNumber,
  required String orderNo,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (context) => PosHangOrderDialog(
      tableNumber: tableNumber,
      orderNo: orderNo,
    ),
  );
}

class PosHangOrderDialog extends StatefulWidget {
  const PosHangOrderDialog({
    super.key,
    required this.tableNumber,
    required this.orderNo,
  });

  final String tableNumber;
  final String orderNo;

  static const List<String> quickReasons = [
    '顾客忘带手机',
    '临时加菜',
    '顾客暂离',
    '等待同行人',
    '菜品调整',
  ];

  @override
  State<PosHangOrderDialog> createState() => _PosHangOrderDialogState();
}

class _PosHangOrderDialogState extends State<PosHangOrderDialog> {
  late final TextEditingController _controller;
  String? _selectedQuickReason;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectQuickReason(String reason) {
    setState(() {
      if (_selectedQuickReason == reason) {
        _selectedQuickReason = null;
        _controller.clear();
      } else {
        _selectedQuickReason = reason;
        _controller.text = reason;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.pause_circle_outline,
              color: Color(0xFFD97706),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '挂起当前订单 - ${widget.tableNumber}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (widget.orderNo.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '单号: ${widget.orderNo}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '挂单后桌台将释放，商品明细与金额安全封存，可随时通过顶部【取单】继续结账。',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '快捷选择挂单原因：',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final reason in PosHangOrderDialog.quickReasons)
                  ChoiceChip(
                    key: Key('hang-reason-chip-$reason'),
                    label: Text(reason),
                    selected: _selectedQuickReason == reason,
                    onSelected: (_) => _selectQuickReason(reason),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: _selectedQuickReason == reason
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              key: const Key('hang-reason-input'),
              controller: _controller,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '挂单备注说明（可选）',
                hintText: '如：顾客忘带手机回去取，稍后结账',
                border: OutlineInputBorder(),
                isDense: true,
                counterText: '',
              ),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton(
          key: const Key('hang-dialog-cancel-button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const Key('hang-dialog-confirm-button'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0284C7),
          ),
          onPressed: () {
            final reason = _controller.text.trim();
            Navigator.of(context).pop(reason);
          },
          child: const Text('确认挂单并清台'),
        ),
      ],
    );
  }
}
