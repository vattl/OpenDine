import 'package:flutter/material.dart';

import '../domain/print_payload_parser.dart';
import '../domain/receipt_preview_models.dart';
import 'cashier_receipt_preview_dialog.dart';

/// 打开「打印任务记录 → 查看打印内容」预览弹窗。
///
/// 修复（2026-09-04）：原先使用固定 18/24/28 逻辑字号 + 无纸宽换算的简化渲染，
/// 与真实 ESC/POS 出纸（倍宽倍高、32/48 列同宽网格）不一致。
/// 现改为：与后端 PrintTicketParser 同源的 payload 解析（[parsePrintPayloadElements]）
/// + 与高保真预览同一渲染组件（[ThermalPaperSimulator]），保证一比一预览。
Future<void> showCashierPrintJobPayloadPreviewDialog(
  BuildContext context, {
  required String jobId,
  required String payloadText,
  String? scenarioName,
}) {
  final elements = parsePrintPayloadElements(payloadText);
  final plainText = printPayloadToPlainText(payloadText);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _PrintJobPayloadPreviewDialog(
      jobId: jobId,
      payloadText: payloadText,
      scenarioName: scenarioName,
      elements: elements,
      plainText: plainText,
    ),
  );
}

class _PrintJobPayloadPreviewDialog extends StatefulWidget {
  const _PrintJobPayloadPreviewDialog({
    required this.jobId,
    required this.payloadText,
    this.scenarioName,
    required this.elements,
    required this.plainText,
  });

  final String jobId;
  final String payloadText;
  final String? scenarioName;
  final List<PrintElement> elements;
  final String plainText;

  @override
  State<_PrintJobPayloadPreviewDialog> createState() =>
      _PrintJobPayloadPreviewDialogState();
}

class _PrintJobPayloadPreviewDialogState
    extends State<_PrintJobPayloadPreviewDialog> {
  /// 打印任务记录本身不携带纸宽元数据，默认 58mm（传菜单/后厨单常用），
  /// 用户可手动切换 58mm/80mm 查看对应列宽的真实排版。
  bool _is80mm = false;

  @override
  Widget build(BuildContext context) {
    final ticket = PrintTicket(
      ticketIndex: 0,
      title: widget.scenarioName ?? '打印内容',
      rawContent: widget.payloadText,
      plainText: widget.plainText,
      elements: widget.elements,
    );

    return Dialog(
      key: const Key('printing-job-payload-preview-dialog'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 600),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  const Text(
                    '打印内容预览',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '任务 #${widget.jobId}'
                      '${widget.scenarioName != null && widget.scenarioName!.isNotEmpty ? ' · ${widget.scenarioName}' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF9CA3AF),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // 纸宽切换：58mm（32 列）/ 80mm（48 列）
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                children: [
                  const Text(
                    '纸宽',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                  ),
                  const SizedBox(width: 10),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('58mm（32列）')),
                      ButtonSegment(value: true, label: Text('80mm（48列）')),
                    ],
                    selected: {_is80mm},
                    onSelectionChanged: (selection) {
                      setState(() => _is80mm = selection.first);
                    },
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      textStyle: WidgetStatePropertyAll(
                        TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 小票纸面（与真实打印一比一的统一渲染）
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: KeyedSubtree(
                    key: const Key('printing-job-paper'),
                    child: ThermalPaperSimulator(
                      ticket: ticket,
                      is80mm: _is80mm,
                    ),
                  ),
                ),
              ),
            ),

            // 底部操作
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('关闭'),
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
