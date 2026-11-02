import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../domain/pos_models.dart';

/// 退菜确认结果：库存动作（对齐服务端 v1.2.203 `stock_action`）与原因。
class RefundDishResult {
  const RefundDishResult({
    required this.quantity,
    required this.stockAction,
    required this.reason,
  });

  final int quantity;
  final PosRefundStockAction stockAction;
  final String reason;
}

/// 退菜对话框：退菜数量 + 库存处理三选一 + 原因快捷标签/备注。
class RefundDishDialog extends StatefulWidget {
  const RefundDishDialog({super.key, required this.line});

  final PosOrderLine line;

  @override
  State<RefundDishDialog> createState() => _RefundDishDialogState();
}

class _RefundDishDialogState extends State<RefundDishDialog> {
  static const _reasonPresets = ['客人取消', '做错口味', '上错菜', '食材缺货', '等待太久'];

  late final TextEditingController _quantityController;
  final _reasonController = TextEditingController();
  PosRefundStockAction _action = PosRefundStockAction.restore;
  String? _selectedPreset;

  @override
  void initState() {
    super.initState();
    _quantityController = TextEditingController(
      text: widget.line.isComboHeader ? '${widget.line.quantity}' : '1',
    );
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  void _selectAction(PosRefundStockAction action) {
    setState(() {
      _action = action;
      // 缺货估清与「食材缺货」原因联动，减少收银员二次输入
      if (action == PosRefundStockAction.outOfStock &&
          _reasonController.text.trim().isEmpty) {
        _selectedPreset = '食材缺货';
        _reasonController.text = '食材缺货';
      }
    });
  }

  void _selectPreset(String preset) {
    setState(() {
      if (_selectedPreset == preset) {
        _selectedPreset = null;
        _reasonController.clear();
      } else {
        _selectedPreset = preset;
        _reasonController.text = preset;
      }
    });
  }

  int? get _quantity => int.tryParse(_quantityController.text.trim());

  String get _unit =>
      widget.line.unit.trim().isEmpty ? '份' : widget.line.unit.trim();

  bool get _quantityValid {
    final quantity = _quantity;
    return quantity != null &&
        quantity >= 1 &&
        quantity <= widget.line.quantity &&
        (!widget.line.isComboHeader || quantity == widget.line.quantity);
  }

  String get _refundAmountLabel {
    final quantity = _quantity;
    if (!_quantityValid || quantity == null) return '—';
    return '¥${(widget.line.unitPrice * quantity).toStringAsFixed(2)}';
  }

  void _adjustQuantity(int delta) {
    final current = _quantity ?? 1;
    final next = (current + delta).clamp(1, widget.line.quantity);
    setState(() {
      _quantityController.value = TextEditingValue(
        text: '$next',
        selection: TextSelection.collapsed(offset: '$next'.length),
      );
    });
  }

  void _confirm() {
    final quantity = _quantity;
    if (!_quantityValid || quantity == null) return;
    Navigator.of(context).pop(
      RefundDishResult(
        quantity: quantity,
        stockAction: _action,
        reason: _reasonController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: context.cashier.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      elevation: 24,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: isDark
            ? BorderSide(color: context.cashier.border)
            : BorderSide.none,
      ),
      child: SizedBox(
        key: const Key('refund-dish-dialog'),
        width: math.min(720, media.width - 48),
        height: math.min(780, media.height - 48),
        child: Column(
          children: [
            _buildHeader(context),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSummary(),
                      if (widget.line.isComboHeader) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: context.cashier.warningBackground,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '套餐不可拆分退菜。本次将退回整个套餐，并同步退回其全部子菜。',
                            style: TextStyle(
                              color: context.cashier.warning,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      const _SectionTitle(title: '库存处理'),
                      const SizedBox(height: 10),
                      for (final action in PosRefundStockAction.values) ...[
                        _ActionOption(
                          action: action,
                          selected: _action == action,
                          onTap: () => _selectAction(action),
                        ),
                        if (action != PosRefundStockAction.values.last)
                          const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 18),
                      const _SectionTitle(title: '退菜原因（选填）'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final preset in _reasonPresets)
                            _ReasonChip(
                              label: preset,
                              selected: _selectedPreset == preset,
                              onTap: () => _selectPreset(preset),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 56,
                        child: TextField(
                          key: const Key('refund-reason-input'),
                          controller: _reasonController,
                          maxLength: 50,
                          maxLines: 1,
                          onChanged: (_) =>
                              setState(() => _selectedPreset = null),
                          decoration: InputDecoration(
                            labelText: '补充说明',
                            hintText: '例如：客人等太久退掉',
                            counterText: '',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildQuantityStepper() {
    final quantity = _quantity;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 168,
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? context.cashier.subtle : Colors.white,
        border: Border.all(
          color: _quantityValid
              ? (isDark ? context.cashier.border : const Color(0xffd9d9d9))
              : const Color(0xffc62828),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 44,
            child: IconButton(
              key: const Key('refund-quantity-decrement'),
              tooltip: '减少退菜数量',
              padding: EdgeInsets.zero,
              onPressed:
                  !widget.line.isComboHeader && quantity != null && quantity > 1
                  ? () => _adjustQuantity(-1)
                  : null,
              icon: const Icon(Icons.remove, size: 22),
            ),
          ),
          const VerticalDivider(width: 1, indent: 9, endIndent: 9),
          Expanded(
            child: TextField(
              key: const Key('refund-quantity-input'),
              controller: _quantityController,
              enabled: !widget.line.isComboHeader,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 12,
                ),
                suffixText: _unit,
                suffixStyle: const TextStyle(
                  color: Color(0xff666666),
                  fontSize: 14,
                ),
              ),
            ),
          ),
          const VerticalDivider(width: 1, indent: 9, endIndent: 9),
          SizedBox(
            width: 44,
            child: IconButton(
              key: const Key('refund-quantity-increment'),
              tooltip: '增加退菜数量',
              padding: EdgeInsets.zero,
              color: const Color(0xffc62828),
              onPressed:
                  !widget.line.isComboHeader &&
                      quantity != null &&
                      quantity < widget.line.quantity
                  ? () => _adjustQuantity(1)
                  : null,
              icon: const Icon(Icons.add, size: 22),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final invalid = !_quantityValid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? context.cashier.subtle : const Color(0xfff5f5f5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.line.specification.isEmpty
                      ? widget.line.name
                      : '${widget.line.name}（${widget.line.specification}）',
                  key: const Key('refund-dish-name'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              _buildQuantityStepper(),
              const SizedBox(width: 16),
              SizedBox(
                width: 104,
                child: Text(
                  _refundAmountLabel,
                  key: const Key('refund-amount'),
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (invalid) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '数量应为 1–${widget.line.quantity} $_unit',
                style: const TextStyle(
                  color: Color(0xffc62828),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ColoredBox(
        color: const Color(0xff2d2d2d),
        child: Stack(
          children: [
            Center(
              child: Text(
                '${widget.line.isComboHeader ? '退套餐' : '退菜'} · ${widget.line.name} × ${widget.line.quantity}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: 10,
              child: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 20),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? context.cashier.border : const Color(0xffe0e0e0),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 58,
              child: OutlinedButton(
                key: const Key('refund-dish-cancel'),
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.cashier.ink,
                  side: BorderSide(
                    color: isDark
                        ? context.cashier.border
                        : const Color(0xff888888),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
                child: const Text('取消'),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 58,
              child: FilledButton.icon(
                key: const Key('refund-dish-confirm'),
                onPressed: _quantityValid ? _confirm : null,
                icon: const Icon(Icons.remove_circle_outline, size: 26),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xffc62828),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
                label: Text(
                  _quantityValid
                      ? '确认退 ${_quantity!} $_unit（${_action.label}）'
                      : '请输入有效数量',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
    title,
    style: TextStyle(
      color: context.cashier.ink,
      fontSize: 18,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _ActionOption extends StatelessWidget {
  const _ActionOption({
    required this.action,
    required this.selected,
    required this.onTap,
  });

  final PosRefundStockAction action;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      key: Key('refund-action-${action.wireValue}'),
      color: selected
          ? (isDark ? const Color(0x33c62828) : const Color(0xffffe9e9))
          : (isDark ? context.cashier.surface : const Color(0xfff7f7f7)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? const Color(0xffc62828)
              : (isDark ? context.cashier.border : Colors.transparent),
          width: 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected
                    ? const Color(0xffc62828)
                    : const Color(0xff9e9e9e),
                size: 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      action.label,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: selected
                            ? const Color(0xffc62828)
                            : context.cashier.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.description,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Color(0xff777777),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  const _ReasonChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Material(
        color: selected
            ? (isDark ? context.cashier.ink : const Color(0xff2d2d2d))
            : (isDark ? context.cashier.subtle : const Color(0xfff0f0f0)),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? (isDark ? Colors.black : Colors.white)
                      : context.cashier.ink,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
