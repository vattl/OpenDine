import 'package:flutter/material.dart';

import '../domain/pos_models.dart';

enum PosRawPrintAlignment { left, center, right }

class PosRawPrintLine {
  const PosRawPrintLine({
    required this.text,
    this.alignment = PosRawPrintAlignment.left,
    this.bold = false,
    this.fontSize = 18,
    this.isDivider = false,
    this.isCut = false,
  });

  final String text;
  final PosRawPrintAlignment alignment;
  final bool bold;
  final double fontSize;
  final bool isDivider;
  final bool isCut;
}

/// Mirrors the server's ticket-tag parser for the legacy print-content API.
List<PosRawPrintLine> parsePosRawPrintContent(String rawContent) {
  if (rawContent.trim().isEmpty) return const [];
  final normalized = rawContent
      .replaceAll('\r\n', '<BR>')
      .replaceAll('\n', '<BR>');
  return normalized
      .split(RegExp(r'<BR>', caseSensitive: false))
      .map((rawLine) {
        final trimmed = rawLine.trim();
        if (trimmed.toUpperCase() == '<CUT>') {
          return const PosRawPrintLine(text: '', isCut: true);
        }

        final contains = (String tag) =>
            RegExp('<$tag>', caseSensitive: false).hasMatch(rawLine);
        final isDoubleCenter = contains('CB');
        // 飞鹅：<B> 为「放大一倍」（非加粗），加粗仅 <BOLD>；<R>/<DB> 非官方标签不处理。
        final isEnlarged = contains('B');
        final alignment = isDoubleCenter || contains('C')
            ? PosRawPrintAlignment.center
            : contains('RIGHT')
            ? PosRawPrintAlignment.right
            : PosRawPrintAlignment.left;
        final text = rawLine
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll('\r', '');
        final isDivider = RegExp(r'^[-=*#_─~]{4,}$').hasMatch(text.trim());
        return PosRawPrintLine(
          text: text,
          alignment: alignment,
          bold: isDoubleCenter || contains('BOLD'),
          fontSize: isDoubleCenter
              ? 28
              : isEnlarged
              ? 28
              : 18,
          isDivider: isDivider,
        );
      })
      .toList(growable: false);
}

Future<bool> showCheckoutPrintPreviewChoice(BuildContext context) async {
  final choice = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('checkout-print-preview-choice-dialog'),
        title: const Text('是否预览打印结果？'),
        content: const Text('打印指令发送后，可将接口返回的小票内容解析为预览。'),
        actions: [
          TextButton(
            key: const Key('checkout-print-preview-choice-skip'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('不预览，直接打印'),
          ),
          FilledButton(
            key: const Key('checkout-print-preview-choice-show'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('预览结果'),
          ),
        ],
      ),
    ),
  );
  return choice ?? false;
}

Future<void> showPosRawPrintResultDialog(
  BuildContext context, {
  required PosPrintResult result,
}) {
  final lines = parsePosRawPrintContent(result.content);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('checkout-print-result-dialog'),
      title: const Text('本次打印结果'),
      content: SizedBox(
        width: 420,
        height: 480,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              result.printSuccess ? '打印指令已发送' : '打印机未完成打印',
              style: TextStyle(
                color: result.printSuccess
                    ? const Color(0xff18864b)
                    : const Color(0xffb45309),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (result.orderNo.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('订单号：${result.orderNo}'),
            ],
            const Divider(height: 24),
            Expanded(
              child: lines.isEmpty
                  ? const Center(child: Text('本次接口未返回可预览的小票内容。'))
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xfffafafa),
                        border: Border.all(color: const Color(0xffd1d5db)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        itemCount: lines.length,
                        itemBuilder: (_, index) =>
                            _RawPrintLineView(line: lines[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          key: const Key('checkout-print-result-close'),
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

class _RawPrintLineView extends StatelessWidget {
  const _RawPrintLineView({required this.line});

  final PosRawPrintLine line;

  @override
  Widget build(BuildContext context) {
    if (line.isCut) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('— — — 切纸 — — —', textAlign: TextAlign.center),
      );
    }
    if (line.isDivider) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(line.text, textAlign: TextAlign.center),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: SelectableText(
        line.text,
        textAlign: switch (line.alignment) {
          PosRawPrintAlignment.left => TextAlign.left,
          PosRawPrintAlignment.center => TextAlign.center,
          PosRawPrintAlignment.right => TextAlign.right,
        },
        style: TextStyle(
          fontFamily: 'NSimSun',
          fontSize: line.fontSize,
          height: 1.35,
          fontWeight: line.bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
    );
  }
}
