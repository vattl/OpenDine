import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../domain/pos_models.dart';

class OrderDiscountResult {
  const OrderDiscountResult({
    required this.discountAmount,
    required this.reason,
  });

  final double discountAmount;
  final String reason;
}

class OrderDiscountDialog extends StatefulWidget {
  const OrderDiscountDialog({super.key, required this.order});

  final PosOrder order;

  @override
  State<OrderDiscountDialog> createState() => _OrderDiscountDialogState();
}

class _OrderDiscountDialogState extends State<OrderDiscountDialog> {
  static const presets = <({String label, double rate, String key})>[
    (label: '95折', rate: 0.95, key: '95'),
    (label: '9折', rate: 0.9, key: '9'),
    (label: '88折', rate: 0.88, key: '88'),
    (label: '8折', rate: 0.8, key: '8'),
  ];
  static const commonReasons = <String>['熟客', '新客', '活动', '员工', '客诉'];

  final fixedController = TextEditingController();
  final noteController = TextEditingController();
  double? selectedRate;
  String? selectedPresetLabel;
  String? selectedReason;
  bool fixedMode = false;
  bool wipeZero = false;

  @override
  void dispose() {
    fixedController.dispose();
    noteController.dispose();
    super.dispose();
  }

  double get grossAmount {
    final gross = widget.order.grossAmount > 0
        ? widget.order.grossAmount
        : widget.order.total +
              widget.order.discountAmount +
              widget.order.wipeZeroAmount;
    return _money(math.max(0, gross));
  }

  double? get fixedAmount =>
      double.tryParse(fixedController.text.trim().replaceAll(',', '.'));

  String? get fixedError {
    if (!fixedMode || fixedController.text.trim().isEmpty) return null;
    final amount = fixedAmount;
    if (amount == null || amount <= 0) return '请输入大于 0 的优惠金额';
    if (amount > grossAmount)
      return '优惠金额不能超过 ¥${grossAmount.toStringAsFixed(2)}';
    return null;
  }

  double get baseDiscount {
    if (selectedRate != null) {
      return _money(grossAmount * (1 - selectedRate!));
    }
    if (fixedMode && fixedError == null && fixedAmount != null) {
      return _money(fixedAmount!);
    }
    return 0;
  }

  double get wipeZeroAmount {
    if (!wipeZero) return 0;
    final payable = math.max(0, grossAmount - baseDiscount);
    return _money(payable - payable.floorToDouble());
  }

  double get finalDiscount =>
      _money(math.min(grossAmount, baseDiscount + wipeZeroAmount));

  double get payableAmount => _money(math.max(0, grossAmount - finalDiscount));

  bool get canSubmit {
    final hasDiscount =
        selectedRate != null ||
        (fixedMode && fixedAmount != null && fixedError == null) ||
        wipeZero;
    return hasDiscount && finalDiscount > 0;
  }

  String get reason {
    final parts = <String>[
      if (selectedPresetLabel != null) selectedPresetLabel!,
      if (fixedMode && fixedAmount != null)
        '固定优惠¥${fixedAmount!.toStringAsFixed(2)}',
      if (wipeZero) '抹零',
      if (selectedReason != null) selectedReason!,
      if (noteController.text.trim().isNotEmpty) noteController.text.trim(),
    ];
    return parts.isEmpty ? '整单优惠' : parts.join(' · ');
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
        side: isDark ? BorderSide(color: context.cashier.border) : BorderSide.none,
      ),
      child: SizedBox(
        key: const Key('discount-dialog'),
        width: math.min(820, media.width - 48),
        height: math.min(960, media.height - 32),
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 20, 32, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildAmountSummary(),
                    const SizedBox(height: 16),
                    const _SectionTitle(title: '快捷折扣'),
                    const SizedBox(height: 10),
                    _buildPresets(),
                    const SizedBox(height: 16),
                    _buildManualOptions(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const _SectionTitle(title: '优惠原因'),
                        const SizedBox(width: 20),
                        Expanded(child: _buildReasons()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 58,
                      child: TextField(
                        key: const Key('discount-note-input'),
                        controller: noteController,
                        maxLength: 80,
                        maxLines: 1,
                        onChanged: (_) => setState(() {}),
                        decoration: _inputDecoration(
                          label: '补充备注（选填）',
                          hint: '例如：店长审批、生日关怀',
                        ).copyWith(counterText: ''),
                      ),
                    ),
                    const Spacer(),
                    _buildSettlementPreview(),
                  ],
                ),
              ),
            ),
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return SizedBox(
      height: 78,
      child: ColoredBox(
        color: const Color(0xff2d2d2d),
        child: Stack(
          children: [
            const Center(
              child: Text(
                '整单折扣',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: 13,
              child: IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 34),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountSummary() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? context.cashier.subtle : const Color(0xfff5f5f5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: _AmountItem(
              label: '订单原价',
              value: '¥${grossAmount.toStringAsFixed(2)}',
            ),
          ),
          Container(
            width: 1,
            height: 42,
            color: isDark ? context.cashier.border : const Color(0xffd8d8d8),
          ),
          Expanded(
            child: _AmountItem(
              label: '当前优惠',
              value: '¥${widget.order.discountAmount.toStringAsFixed(2)}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPresets() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * 3) / 4;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: presets
              .map((preset) {
                final selected = !fixedMode && selectedRate == preset.rate;
                return SizedBox(
                  width: width,
                  height: 62,
                  child: Material(
                    color: selected
                        ? const Color(0xffdcecff)
                        : const Color(0xff2d2d2d),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      key: Key('discount-preset-${preset.key}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => setState(() {
                        fixedMode = false;
                        selectedRate = preset.rate;
                        selectedPresetLabel = preset.label;
                      }),
                      child: Center(
                        child: Text(
                          preset.label,
                          style: TextStyle(
                            color: selected
                                ? const Color(0xff238af2)
                                : Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              })
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildManualOptions() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _OptionPanel(
            key: const Key('discount-fixed-mode'),
            selected: fixedMode,
            icon: Icons.payments_outlined,
            title: '固定优惠',
            subtitle: '直接减免指定金额',
            onTap: () => setState(() {
              fixedMode = true;
              selectedRate = null;
              selectedPresetLabel = null;
            }),
            child: fixedMode
                ? TextField(
                    key: const Key('discount-fixed-input'),
                    controller: fixedController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d{0,7}([.,]\d{0,2})?'),
                      ),
                    ],
                    onChanged: (_) => setState(() {}),
                    decoration: _inputDecoration(
                      label: '优惠金额',
                      hint: '0.00',
                      errorText: fixedError,
                      prefixText: '¥ ',
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: _OptionPanel(
            key: const Key('discount-wipe-zero'),
            selected: wipeZero,
            icon: Icons.horizontal_rule_rounded,
            title: '抹零',
            subtitle: '应收金额向下抹至整数',
            onTap: () => setState(() => wipeZero = !wipeZero),
            trailing: Switch(
              value: wipeZero,
              onChanged: (value) => setState(() => wipeZero = value),
              activeTrackColor: const Color(0xff238af2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReasons() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: commonReasons
          .map((item) {
            final selected = selectedReason == item;
            return SizedBox(
              height: 48,
              child: ChoiceChip(
                key: Key('discount-reason-$item'),
                selected: selected,
                showCheckmark: false,
                label: Text(item),
                onSelected: (_) =>
                    setState(() => selectedReason = selected ? null : item),
                labelStyle: TextStyle(
                  color: selected
                      ? const Color(0xff238af2)
                      : const Color(0xff333333),
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 15),
                backgroundColor: Colors.white,
                selectedColor: const Color(0xffdcecff),
                side: BorderSide(
                  color: selected
                      ? const Color(0xff238af2)
                      : const Color(0xffcfcfcf),
                  width: selected ? 1.5 : 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            );
          })
          .toList(growable: false),
    );
  }

  Widget _buildSettlementPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xfffff4f4),
        border: Border.all(color: const Color(0xffffd0d0)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '本次优惠  ¥${finalDiscount.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Color(0xff555555),
                fontSize: 21,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Text(
            '应收金额',
            style: TextStyle(color: Color(0xff555555), fontSize: 21),
          ),
          const SizedBox(width: 14),
          Text(
            '¥${payableAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Color(0xffe65353),
              fontSize: 34,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 14, 32, 18),
      decoration: BoxDecoration(
        color: context.cashier.surface,
        border: Border(top: BorderSide(color: isDark ? context.cashier.border : const Color(0xffe2e2e2))),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 58,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.cashier.ink,
                  side: BorderSide(color: isDark ? context.cashier.border : const Color(0xff888888)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('取消', style: TextStyle(fontSize: 26)),
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: SizedBox(
              height: 58,
              child: FilledButton(
                key: const Key('discount-confirm'),
                onPressed: canSubmit
                    ? () => Navigator.of(context).pop(
                        OrderDiscountResult(
                          discountAmount: finalDiscount,
                          reason: reason,
                        ),
                      )
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: context.cashier.ink,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  disabledBackgroundColor: isDark ? context.cashier.subtle : const Color(0xffb5b5b5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  '确认优惠',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 5, height: 28, color: const Color(0xffe65353)),
        const SizedBox(width: 10),
        Text(
          title,
          style: TextStyle(
            color: context.cashier.ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _AmountItem extends StatelessWidget {
  const _AmountItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xff888888), fontSize: 16),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: context.cashier.ink,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _OptionPanel extends StatelessWidget {
  const _OptionPanel({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.child,
    this.trailing,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? (isDark ? context.cashier.selectedBackground : const Color(0xffeef6ff))
          : (isDark ? context.cashier.surface : Colors.white),
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: selected
              ? (isDark ? context.cashier.selected : const Color(0xff238af2))
              : (isDark ? context.cashier.border : const Color(0xffd1d1d1)),
          width: selected ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    color: selected
                        ? const Color(0xff238af2)
                        : const Color(0xff555555),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: context.cashier.ink,
                            fontSize: 21,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xff888888),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              if (child != null) ...[const SizedBox(height: 14), child!],
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDecoration({
  required String label,
  required String hint,
  String? errorText,
  String? prefixText,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    errorText: errorText,
    prefixText: prefixText,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xffcfcfcf)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xff238af2), width: 1.8),
    ),
  );
}

double _money(num value) => (value * 100).round() / 100;
