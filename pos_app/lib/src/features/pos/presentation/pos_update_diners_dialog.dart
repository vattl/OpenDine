import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../cashier_shell/presentation/cashier_tokens.dart';

Future<int?> showPosUpdateDinersDialog(
  BuildContext context, {
  required String tableNumber,
  required String orderNo,
  required int currentDiners,
}) {
  return showDialog<int>(
    context: context,
    barrierDismissible: true,
    builder: (context) => PosUpdateDinersDialog(
      tableNumber: tableNumber,
      orderNo: orderNo,
      currentDiners: currentDiners,
    ),
  );
}

class PosUpdateDinersDialog extends StatefulWidget {
  const PosUpdateDinersDialog({
    super.key,
    required this.tableNumber,
    required this.orderNo,
    required this.currentDiners,
  });

  final String tableNumber;
  final String orderNo;
  final int currentDiners;

  static const List<int> quickCounts = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];

  @override
  State<PosUpdateDinersDialog> createState() => _PosUpdateDinersDialogState();
}

class _PosUpdateDinersDialogState extends State<PosUpdateDinersDialog> {
  late int _diners;
  late final TextEditingController _customController;
  bool _customMode = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _diners = widget.currentDiners > 0 ? widget.currentDiners : 1;
    _customController = TextEditingController(text: '');
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _setDiners(int value) {
    if (value < 1 || value > 999) return;
    setState(() {
      _diners = value;
      _customController.text = '';
      _errorText = null;
    });
  }

  void _onCustomChanged(String text) {
    final parsed = int.tryParse(text.trim());
    if (parsed == null || parsed < 1 || parsed > 999) {
      setState(() {
        _errorText = '人数必须在 1 ~ 999 之间';
      });
    } else {
      setState(() {
        _diners = parsed;
        _errorText = null;
      });
    }
  }

  void _confirm() {
    if (_diners < 1 || _diners > 999) {
      setState(() {
        _errorText = '就餐人数必须在 1 ~ 999 之间';
      });
      return;
    }
    Navigator.of(context).pop(_diners);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cashier = context.cashier;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xffe0f2fe),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.people_outline,
              color: Color(0xff0284c7),
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '修改就餐人数 - ${widget.tableNumber}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  '原就餐人数: ${widget.currentDiners} 人 | 单号: ${widget.orderNo}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 步进器主展区
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: BoxDecoration(
                color: isDark ? cashier.row : const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? cashier.border : const Color(0xffe2e8f0),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    key: const Key('pos-diners-stepper-minus'),
                    onPressed: _diners > 1 ? () => _setDiners(_diners - 1) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                    iconSize: 36,
                    color: const Color(0xff0284c7),
                    tooltip: '减少1人',
                  ),
                  const SizedBox(width: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$_diners',
                        key: const Key('pos-diners-display-text'),
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: Color(0xff0284c7),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '人',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cashier.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 24),
                  IconButton(
                    key: const Key('pos-diners-stepper-plus'),
                    onPressed: _diners < 999 ? () => _setDiners(_diners + 1) : null,
                    icon: const Icon(Icons.add_circle_outline),
                    iconSize: 36,
                    color: const Color(0xff0284c7),
                    tooltip: '增加1人',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 快捷选择网格
            Text(
              '常用人数快捷选择',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cashier.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in PosUpdateDinersDialog.quickCounts)
                  InkWell(
                    key: Key('pos-diners-quick-$count'),
                    onTap: () {
                      setState(() => _customMode = false);
                      _setDiners(count);
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 58,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _diners == count && !_customMode
                            ? const Color(0xff0284c7)
                            : (isDark ? cashier.surface : const Color(0xfff1f5f9)),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _diners == count && !_customMode
                              ? const Color(0xff0284c7)
                              : (isDark ? cashier.border : const Color(0xffcbd5e1)),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _diners == count && !_customMode
                              ? Colors.white
                              : cashier.ink,
                        ),
                      ),
                    ),
                  ),
                InkWell(
                  key: const Key('pos-diners-quick-custom'),
                  onTap: () => setState(() => _customMode = !_customMode),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 78,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _customMode
                          ? const Color(0xff0284c7)
                          : (isDark ? cashier.surface : const Color(0xfff1f5f9)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _customMode
                            ? const Color(0xff0284c7)
                            : (isDark ? cashier.border : const Color(0xffcbd5e1)),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '自定义',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _customMode ? Colors.white : cashier.ink,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            if (_customMode) ...[
              const SizedBox(height: 14),
              TextField(
                key: const Key('pos-update-diners-input'),
                controller: _customController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '输入实际就餐人数 (1 ~ 999)',
                  suffixText: '人',
                  errorText: _errorText,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                onChanged: _onCustomChanged,
              ),
            ],
            if (!_customMode && _errorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          key: const Key('pos-update-diners-confirm-button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xff0284c7),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _errorText == null ? _confirm : null,
          child: Text('确认修改为 $_diners 人'),
        ),
      ],
    );
  }
}
