import 'package:flutter/material.dart';

import '../data/cashier_settings_repository.dart';
import '../domain/receipt_preview_models.dart';

/// 仅以已持久化业务数据调用 exact 预览，不传模板草稿或样例上下文。
Future<void> showCashierExactPrintPreviewDialog({
  required BuildContext context,
  required CashierSettingsRepository repository,
  required String scenario,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _CashierExactPrintPreviewDialog(
      repository: repository,
      scenario: scenario,
    ),
  );
}

class _CashierExactPrintPreviewDialog extends StatefulWidget {
  const _CashierExactPrintPreviewDialog({
    required this.repository,
    required this.scenario,
  });

  final CashierSettingsRepository repository;
  final String scenario;

  @override
  State<_CashierExactPrintPreviewDialog> createState() =>
      _CashierExactPrintPreviewDialogState();
}

class _CashierExactPrintPreviewDialogState
    extends State<_CashierExactPrintPreviewDialog> {
  final _orderController = TextEditingController();
  final _shiftController = TextEditingController();
  final _detailController = TextEditingController();
  final _serveQtyController = TextEditingController(text: '1');
  final _ruleController = TextEditingController();
  final _deviceController = TextEditingController();
  bool _loading = false;
  String? _error;
  PrintPreviewResult? _result;

  bool get _isShift => widget.scenario == 'SHIFT';
  bool get _requiresDetail =>
      widget.scenario == 'EXPEDITE' || widget.scenario == 'LABEL';

  @override
  void dispose() {
    _orderController.dispose();
    _shiftController.dispose();
    _detailController.dispose();
    _serveQtyController.dispose();
    _ruleController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  int? _optionalInt(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : int.tryParse(value);
  }

  Future<void> _preview() async {
    final businessValue = (_isShift ? _shiftController : _orderController).text
        .trim();
    if (businessValue.isEmpty) {
      setState(() {
        _error = _isShift ? '请输入已持久化的真实班次 ID。' : '请输入真实订单 ID 或订单号。';
      });
      return;
    }
    if (_requiresDetail && _optionalInt(_detailController) == null) {
      setState(() => _error = '当前场景必须选择真实订单明细 ID。');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final value = await widget.repository.fetchExactPrintPreview(
        scenario: widget.scenario,
        orderId: _isShift ? null : int.tryParse(businessValue),
        orderNo: _isShift || int.tryParse(businessValue) != null
            ? null
            : businessValue,
        shiftId: _isShift ? int.tryParse(businessValue) : null,
        detailId: _optionalInt(_detailController),
        serveQty: widget.scenario == 'EXPEDITE'
            ? _optionalInt(_serveQtyController)
            : null,
        ruleId: _optionalInt(_ruleController),
        deviceId: _optionalInt(_deviceController),
      );
      if (mounted) setState(() => _result = value);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.fact_check_outlined, color: Color(0xFF2563EB)),
          SizedBox(width: 8),
          Text('精确预览（真实打印链路）'),
        ],
      ),
      content: SizedBox(
        width: 760,
        height: 600,
        child: Column(
          children: [
            Text(
              _isShift
                  ? '选择真实班次后，按当前门店的生效规则模拟实际交接班打印；不会创建打印任务。'
                  : '选择真实订单后，按当前门店所有生效规则和设备模拟实际打印；不会创建打印任务。',
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: _isShift ? _shiftController : _orderController,
                    decoration: InputDecoration(
                      labelText: _isShift ? '真实班次 ID *' : '真实订单 ID 或订单号 *',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                if (_requiresDetail)
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _detailController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '订单明细 ID *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                if (widget.scenario == 'EXPEDITE')
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _serveQtyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '传菜数量',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _ruleController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '规则 ID（可选）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _deviceController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '设备 ID（可选）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _preview,
                  icon: _loading
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.visibility_outlined),
                  label: Text(_loading ? '渲染中' : '精确预览'),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              _WarningPanel(result: _result!),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _result!.tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) =>
                      _TicketSourceCard(ticket: _result!.tickets[index]),
                ),
              ),
            ] else
              const Expanded(child: Center(child: Text('填写真实业务标识后生成预览结果'))),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _WarningPanel extends StatelessWidget {
  const _WarningPanel({required this.result});
  final PrintPreviewResult result;

  @override
  Widget build(BuildContext context) {
    final warnings = [
      ...result.bindingWarnings,
      ...result.capabilityWarnings,
    ].toSet().toList();
    if (warnings.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '渲染警告',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF9A3412),
            ),
          ),
          ...warnings.map(
            (item) => Text(
              '• $item',
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketSourceCard extends StatelessWidget {
  const _TicketSourceCard({required this.ticket});
  final PrintTicket ticket;

  @override
  Widget build(BuildContext context) {
    final source = [
      if (ticket.deviceName?.isNotEmpty == true) '设备：${ticket.deviceName}',
      if (ticket.deviceId != null) '设备 ID：${ticket.deviceId}',
      if (ticket.ruleId != null) '规则：${ticket.ruleId}',
      if (ticket.templateCode?.isNotEmpty == true) '模板：${ticket.templateCode}',
      if (ticket.templateId != null) '模板 ID：${ticket.templateId}',
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ticket.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (source.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  source.join('  ·  '),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
            const Divider(height: 14),
            SelectableText(
              ticket.plainText.isEmpty ? ticket.rawContent : ticket.plainText,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
