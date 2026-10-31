import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/cashier_settings.dart';
import '../domain/receipt_preview_models.dart';
import 'cashier_settings_shared.dart';

/// 打开票据打印效果预览弹窗 (以服务端 /admin/printing/preview 真实数据渲染为主)
Future<void> showCashierReceiptPreviewDialog({
  required BuildContext context,
  String? storeName,
  ReceiptTemplateScenario initialScenario = ReceiptTemplateScenario.standardReceipt,
  String initialPaperSize = '80mm',
  String? initialCustomText,
  int? orderId,
  String? orderNo,
  int? deviceId,
  bool isAddDishes = false,
  List<CashierPrinterDevice> devices = const [],
  required Future<PrintPreviewResult?> Function(
    ReceiptTemplateScenario scenario,
    String paperSize,
    String? customContent,
  ) onFetchPreview,
  Future<void> Function(CashierPrinterDevice device, String testType, String? customContent)? onSendTest,
  Future<void> Function()? onExecutePrint,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => CashierReceiptPreviewDialog(
      storeName: storeName,
      initialScenario: initialScenario,
      initialPaperSize: initialPaperSize,
      initialCustomText: initialCustomText,
      orderId: orderId,
      orderNo: orderNo,
      deviceId: deviceId,
      isAddDishes: isAddDishes,
      devices: devices,
      onFetchPreview: onFetchPreview,
      onSendTest: onSendTest,
      onExecutePrint: onExecutePrint,
    ),
  );
}

/// 预览模式
enum ReceiptPreviewViewMode {
  simulator, // 仿真热敏纸渲染
  plainText, // 纯文本排版
  astInspector, // AST 结构化节点
}

/// 热敏票据打印效果实时预览弹窗 (Thermal Receipt Simulator)
class CashierReceiptPreviewDialog extends StatefulWidget {
  const CashierReceiptPreviewDialog({
    super.key,
    this.storeName,
    this.initialScenario = ReceiptTemplateScenario.standardReceipt,
    this.initialPaperSize = '80mm',
    this.initialCustomText,
    this.orderId,
    this.orderNo,
    this.deviceId,
    this.isAddDishes = false,
    this.devices = const [],
    required this.onFetchPreview,
    this.onSendTest,
    this.onExecutePrint,
  });

  final String? storeName;
  final ReceiptTemplateScenario initialScenario;
  final String initialPaperSize;
  final String? initialCustomText;
  final int? orderId;
  final String? orderNo;
  final int? deviceId;
  final bool isAddDishes;
  final List<CashierPrinterDevice> devices;
  final Future<PrintPreviewResult?> Function(
    ReceiptTemplateScenario scenario,
    String paperSize,
    String? customContent,
  ) onFetchPreview;
  final Future<void> Function(CashierPrinterDevice device, String testType, String? customContent)? onSendTest;
  final Future<void> Function()? onExecutePrint;

  @override
  State<CashierReceiptPreviewDialog> createState() => _CashierReceiptPreviewDialogState();
}

class _CashierReceiptPreviewDialogState extends State<CashierReceiptPreviewDialog> {
  late ReceiptTemplateScenario _scenario;
  late bool _is80mm;
  late TextEditingController _customController;
  CashierPrinterDevice? _selectedDevice;
  bool _sending = false;
  bool _printing = false;

  // 后端真实预览数据
  PrintPreviewResult? _backendResult;
  bool _loadingPreview = false;
  String? _previewError;
  int _activeTicketIndex = 0;
  ReceiptPreviewViewMode _viewMode = ReceiptPreviewViewMode.simulator;

  @override
  void initState() {
    super.initState();
    _scenario = widget.initialScenario;
    _is80mm = widget.initialPaperSize.contains('80');
    _customController = TextEditingController(text: widget.initialCustomText ?? '');
    if (widget.devices.isNotEmpty) {
      _selectedDevice = widget.devices.firstWhere(
        (d) => d.isDefault,
        orElse: () => widget.devices.first,
      );
    }
    _loadBackendPreview();
  }

  Future<void> _loadBackendPreview() async {
    setState(() {
      _loadingPreview = true;
      _previewError = null;
    });

    try {
      final result = await widget.onFetchPreview(
        _scenario,
        _is80mm ? '80mm' : '58mm',
        _scenario == ReceiptTemplateScenario.custom ? _customController.text : null,
      );
      if (!mounted) return;
      if (result != null) {
        setState(() {
          _backendResult = result;
          _is80mm = result.is80mm;
          _activeTicketIndex = 0;
          _loadingPreview = false;
        });
      } else {
        setState(() {
          _loadingPreview = false;
          _previewError = '服务端返回空预览数据';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingPreview = false;
        _previewError = '请求小票预览失败：$e';
      });
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeTicket = (_backendResult != null && _backendResult!.tickets.isNotEmpty)
        ? _backendResult!.tickets[_activeTicketIndex.clamp(0, _backendResult!.tickets.length - 1)]
        : null;

    final currentPlainText = activeTicket?.plainText.isNotEmpty == true
        ? activeTicket!.plainText
        : (activeTicket?.rawContent ?? '');

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: const Color(0xFFF3F4F6),
      child: Container(
        width: 1100,
        height: 800,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 顶部导航与状态栏
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.preview_rounded, color: Color(0xFF2563EB), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            '票据打印效果实时预览 (服务端实时渲染)',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
                          ),
                          const SizedBox(width: 8),
                          if (_loadingPreview) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF2563EB)),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    '正在请求小票预览...',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ] else if (_backendResult != null) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFECFDF5),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFFA7F3D0)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle, color: Color(0xFF059669), size: 12),
                                  SizedBox(width: 4),
                                  Text(
                                    '后端真实解析',
                                    style: TextStyle(fontSize: 11, color: Color(0xFF059669), fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _backendResult != null
                            ? '场景: ${_backendResult!.scenarioName} · 纸张: ${_backendResult!.paperSize} (${_backendResult!.paperWidthChars}列宽 / ${_backendResult!.paperWidthMm}mm) · 门店: ${_backendResult!.shopName.isNotEmpty ? _backendResult!.shopName : (widget.storeName ?? '当前门店')}${widget.orderNo != null ? ' · 订单号: ${widget.orderNo}' : ''}'
                            : (widget.orderNo != null
                                ? '当前关联订单：${widget.orderNo} · 正在拉取后端真实热敏小票'
                                : '对接服务端模板引擎，真实呈现 58mm / 80mm 热敏纸字号、对齐、换行与切刀排版。'),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (widget.onExecutePrint != null) ...[
                  FilledButton.icon(
                    key: const Key('preview-dialog-direct-print-btn'),
                    onPressed: _printing
                        ? null
                        : () async {
                            setState(() => _printing = true);
                            try {
                              await widget.onExecutePrint!();
                              if (mounted) {
                                Navigator.of(context).pop();
                              }
                            } finally {
                              if (mounted) setState(() => _printing = false);
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFD84949),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    icon: _printing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print_rounded, size: 16),
                    label: Text(_printing ? '正在出票...' : '确认无误，立即打印'),
                  ),
                  const SizedBox(width: 10),
                ],
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                  tooltip: '关闭预览',
                ),
              ],
            ),
            const Divider(height: 20, color: Color(0xFFE5E7EB)),

            // 主体区：左侧控制面板 + 右侧热敏纸卷预览
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 左侧控制区
                  SizedBox(
                    width: 420,
                    child: ListView(
                      padding: const EdgeInsets.only(right: 16),
                      children: [
                        // 1. 纸张规格切换
                        const Text(
                          '热敏纸卷规格 (向后端请求对应排版)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _buildPaperSizeChoice(
                                label: '80mm 标准宽纸',
                                sublabel: '48 字符/行 · 常见台面/后厨机',
                                isSelected: _is80mm,
                                onTap: () {
                                  if (!_is80mm) {
                                    setState(() => _is80mm = true);
                                    _loadBackendPreview();
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildPaperSizeChoice(
                                label: '58mm 窄票卷纸',
                                sublabel: '32 字符/行 · 常见手持/便携机',
                                isSelected: !_is80mm,
                                onTap: () {
                                  if (_is80mm) {
                                    setState(() => _is80mm = false);
                                    _loadBackendPreview();
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 2. 票据模板场景选择
                        const Text(
                          '选择预览场景 (scenario)',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ReceiptTemplateScenario.values.map((s) {
                            final selected = _scenario == s;
                            return ChoiceChip(
                              key: Key('preview-chip-${s.code}'),
                              label: Text(
                                s.label,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: selected ? Colors.white : const Color(0xFF374151),
                                ),
                              ),
                              selected: selected,
                              selectedColor: const Color(0xFF2563EB),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: selected ? const Color(0xFF2563EB) : const Color(0xFFD1D5DB),
                              ),
                              onSelected: (val) {
                                if (val) {
                                  setState(() => _scenario = s);
                                  _loadBackendPreview();
                                }
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFBFDBFE)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline, size: 16, color: Color(0xFF2563EB)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_scenario.description} (后端参数: scenario=${_scenario.code})',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E40AF)),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 3. 多票据切换（若后端一次下发多张联，如结账联+客户联）
                        if (_backendResult != null && _backendResult!.tickets.length > 1) ...[
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Text(
                                '多联票据选择',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '共 ${_backendResult!.tickets.length} 联',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF92400E)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            children: List.generate(_backendResult!.tickets.length, (idx) {
                              final ticket = _backendResult!.tickets[idx];
                              final isSelected = _activeTicketIndex == idx;
                              return ChoiceChip(
                                label: Text(ticket.title.isNotEmpty ? ticket.title : '第 ${idx + 1} 联'),
                                selected: isSelected,
                                selectedColor: const Color(0xFF4B5563),
                                backgroundColor: Colors.white,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  color: isSelected ? Colors.white : const Color(0xFF374151),
                                ),
                                onSelected: (val) {
                                  if (val) setState(() => _activeTicketIndex = idx);
                                },
                              );
                            }),
                          ),
                        ],

                        // 4. 自定义内容编辑框（仅在自定义模式展开）
                        if (_scenario == ReceiptTemplateScenario.custom) ...[
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '自定义打印文本内容',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                              ),
                              TextButton(
                                onPressed: _loadBackendPreview,
                                child: const Text('由后端解析', style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: _customController,
                            maxLines: 4,
                            decoration: InputDecoration(
                              hintText: '请输入要由后端引擎解析的自定义测试小票内容...',
                              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.all(10),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                              ),
                            ),
                          ),
                        ],

                        // 5. 错误提示与重试
                        if (_previewError != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFFFECACA)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _previewError!,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
                                ),
                                const SizedBox(height: 6),
                                OutlinedButton.icon(
                                  onPressed: _loadBackendPreview,
                                  icon: const Icon(Icons.refresh_rounded, size: 14),
                                  label: const Text('重试请求接口'),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFFDC2626),
                                    side: const BorderSide(color: Color(0xFFDC2626)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 16),
                        const Divider(color: Color(0xFFE5E7EB)),
                        const SizedBox(height: 10),

                        // 6. 目标打印设备选择与下发测试
                        if (widget.devices.isNotEmpty && widget.onSendTest != null) ...[
                          const Text(
                            '下发真实设备出票测试',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF374151)),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFD1D5DB)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<CashierPrinterDevice>(
                                isExpanded: true,
                                value: _selectedDevice,
                                items: widget.devices.map((d) {
                                  return DropdownMenuItem(
                                    value: d,
                                    child: Text(
                                      '${d.name} (${d.vendor} · ${d.transportDisplayName})',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) => setState(() => _selectedDevice = val),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.icon(
                            onPressed: _sending || _selectedDevice == null
                                ? null
                                : () async {
                                    setState(() => _sending = true);
                                    try {
                                      await widget.onSendTest!(
                                        _selectedDevice!,
                                        _scenario.code,
                                        _scenario == ReceiptTemplateScenario.custom ? _customController.text : null,
                                      );
                                      if (mounted) {
                                        showSettingsSaved(
                                          context,
                                          '测试小票指令已下发至「${_selectedDevice!.name}」',
                                        );
                                      }
                                    } finally {
                                      if (mounted) setState(() => _sending = false);
                                    }
                                  },
                            icon: const Icon(Icons.send_rounded, size: 16),
                            label: Text(_sending ? '正在发送测试...' : '发送至「${_selectedDevice?.name ?? '打印机'}」真实出票'),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: const Color(0xFF059669),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 右侧：热敏纸小票画布容器
                  Expanded(
                    child: Container(
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFD1D5DB)),
                      ),
                      child: Column(
                        children: [
                          // 纸卷头部状态栏与模式切换
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: const BoxDecoration(
                              color: Color(0xFF1F2937),
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(11),
                                topRight: Radius.circular(11),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.receipt_outlined, color: Colors.white, size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  _is80mm ? '80mm 宽幅 (48列)' : '58mm 窄幅 (32列)',
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 8),
                                // 模式切换器
                                _buildViewModeToggle(),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: currentPlainText.isNotEmpty
                                      ? () {
                                          Clipboard.setData(ClipboardData(text: currentPlainText));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('已复制后端小票排版纯文本至剪贴板'),
                                              duration: Duration(seconds: 2),
                                            ),
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF93C5FD)),
                                  label: const Text('复制文本排版', style: TextStyle(color: Color(0xFF93C5FD), fontSize: 11)),
                                  style: TextButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // 滚动小票纸张主体
                          Expanded(
                            child: _buildMainPreviewContent(activeTicket, currentPlainText),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF374151),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton('仿真视图', ReceiptPreviewViewMode.simulator),
          _buildModeButton('纯文本', ReceiptPreviewViewMode.plainText),
          _buildModeButton('AST 节点', ReceiptPreviewViewMode.astInspector),
        ],
      ),
    );
  }

  Widget _buildModeButton(String title, ReceiptPreviewViewMode mode) {
    final active = _viewMode == mode;
    return InkWell(
      onTap: () => setState(() => _viewMode = mode),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2563EB) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.white : const Color(0xFFD1D5DB),
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildMainPreviewContent(PrintTicket? ticket, String plainText) {
    if (_loadingPreview && _backendResult == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF2563EB)),
            const SizedBox(height: 16),
            Text(
              '正在请求后端实时解析小票...',
              style: TextStyle(fontSize: 14, color: Colors.grey[700], fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    if (_previewError != null && _backendResult == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 10)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 40),
              const SizedBox(height: 12),
              const Text(
                '拉取后端小票预览数据失败',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
              ),
              const SizedBox(height: 8),
              Text(
                _previewError!,
                style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadBackendPreview,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重新请求接口'),
              ),
            ],
          ),
        ),
      );
    }

    if (ticket == null) {
      return Center(
        child: Text(
          '后端未返回有效小票数据',
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
      );
    }

    switch (_viewMode) {
      case ReceiptPreviewViewMode.plainText:
        return Container(
          color: const Color(0xFF1E293B),
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: SelectableText(
              plainText.isNotEmpty ? plainText : '(无纯文本内容)',
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 13,
                height: 1.4,
                color: Color(0xFFF1F5F9),
              ),
            ),
          ),
        );

      case ReceiptPreviewViewMode.astInspector:
        return Container(
          color: const Color(0xFF0F172A),
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AST 结构化节点总数: ${ticket.elements.length} 个',
                  style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 10),
                ...ticket.elements.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final el = entry.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '#$idx ${el.type.name.toUpperCase()}',
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            el.text != null
                                ? 'text: "${el.text}" (align: ${el.align.name}, bold: ${el.bold}, size: ${el.size.name})'
                                : (el.columns.isNotEmpty
                                    ? 'columns: ${el.columns.join(' | ')}'
                                    : (el.key != null ? 'key: "${el.key}", val: "${el.value}"' : 'meta: ${jsonEncode(el.meta)}')),
                            style: const TextStyle(color: Color(0xFFE2E8F0), fontFamily: 'Courier', fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        );

      case ReceiptPreviewViewMode.simulator:
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: ThermalPaperSimulator(
              ticket: ticket,
              is80mm: _is80mm,
            ),
          ),
        );
    }
  }

  Widget _buildPaperSizeChoice({
    required String label,
    required String sublabel,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFD1D5DB),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF9CA3AF),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? const Color(0xFF1E40AF) : const Color(0xFF1F2937),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              sublabel,
              style: TextStyle(fontSize: 11, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 仿真热敏纸纸卷外观组件 (完全基于后端 AST Elements 渲染，无 AST 时渲染后端 PlainText)
/// 仿真热敏纸纸卷外观组件 (完全基于真实热敏纸 32列/48列 字符网格与 ESC/POS 规格高保真渲染)
class ThermalPaperSimulator extends StatelessWidget {
  const ThermalPaperSimulator({
    super.key,
    required this.ticket,
    required this.is80mm,
  });

  final PrintTicket ticket;
  final bool is80mm;

  static const List<String> _receiptFontFallbacks = [
    'NSimSun',
    'SimSun',
    'SimHei',
    'Consolas',
    'Courier New',
    'Courier',
    'Microsoft YaHei',
    'PingFang SC',
    'Hiragino Sans GB',
    'monospace',
  ];

  @override
  Widget build(BuildContext context) {
    // 58mm 纸张宽度（32列字符，约270px） vs 80mm 纸张宽度（48列字符，约390px）
    final paperWidth = is80mm ? 390.0 : 270.0;

    return Center(
      child: Container(
        width: paperWidth,
        decoration: BoxDecoration(
          color: const Color(0xFFFAF9F6),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 14,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部撕纸齿纹仿真
            _buildTearEdge(),

            // 热敏小票主体：高保真字符网格渲染（32列/48列 100% 同宽对齐）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
              child: ticket.elements.isNotEmpty
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: ticket.elements.map(_buildElementWidget).toList(),
                    )
                  : SelectableText(
                      ticket.plainText.isNotEmpty ? ticket.plainText : ticket.rawContent,
                      style: const TextStyle(
                        fontFamily: 'NSimSun',
                        fontFamilyFallback: _receiptFontFallbacks,
                        fontSize: 14.0,
                        height: 1.35,
                        letterSpacing: 0.0,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
            ),

            // 底部切刀裁切线仿真
            _buildBottomCutEdge(),
          ],
        ),
      ),
    );
  }

  Widget _buildElementWidget(PrintElement el) {
    switch (el.type) {
      case PrintElementType.header:
        final isDouble = el.size == PrintElementSize.double;
        final isLarge = el.size == PrintElementSize.large;
        final fontSize = isDouble ? 22.0 : (isLarge ? 18.0 : 14.0);
        final align = el.align == PrintElementAlign.center
            ? TextAlign.center
            : el.align == PrintElementAlign.right
                ? TextAlign.right
                : TextAlign.left;

        return Padding(
          padding: EdgeInsets.symmetric(vertical: isDouble ? 4.0 : 2.0),
          child: Text(
            el.text ?? '',
            textAlign: align,
            style: TextStyle(
              fontFamily: 'NSimSun',
              fontFamilyFallback: _receiptFontFallbacks,
              fontSize: fontSize,
              height: 1.3,
              fontWeight: isDouble ? FontWeight.w900 : (el.bold ? FontWeight.w800 : FontWeight.w700),
              letterSpacing: isDouble ? 0.5 : 0.0,
              color: const Color(0xFF111827),
            ),
          ),
        );

      case PrintElementType.divider:
        final defaultDivider = is80mm
            ? '------------------------------------------------'
            : '--------------------------------';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(
            el.text?.isNotEmpty == true ? el.text! : defaultDivider,
            style: const TextStyle(
              fontFamily: 'NSimSun',
              fontFamilyFallback: _receiptFontFallbacks,
              fontSize: 14.0,
              height: 1.2,
              letterSpacing: 0.0,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
            overflow: TextOverflow.clip,
            maxLines: 1,
          ),
        );

      case PrintElementType.tableHeader:
      case PrintElementType.tableRow:
        if (el.columns.isEmpty) return const SizedBox.shrink();
        final isHeader = el.type == PrintElementType.tableHeader;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            children: el.columns.asMap().entries.map((entry) {
              final idx = entry.key;
              final col = entry.value;
              final isLast = idx == el.columns.length - 1;
              final isFirst = idx == 0;
              return Expanded(
                flex: isFirst ? 4 : (isLast ? 3 : 2),
                child: Text(
                  col,
                  textAlign: isFirst
                      ? TextAlign.left
                      : (isLast ? TextAlign.right : TextAlign.center),
                  style: TextStyle(
                    fontFamily: 'NSimSun',
                    fontFamilyFallback: _receiptFontFallbacks,
                    fontSize: 14.0,
                    height: 1.35,
                    letterSpacing: 0.0,
                    fontWeight: isHeader || el.bold
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: const Color(0xFF111827),
                  ),
                ),
              );
            }).toList(),
          ),
        );

      case PrintElementType.keyValue:
        final k = el.key ?? '';
        final v = el.value ?? '';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(
            mainAxisAlignment: el.align == PrintElementAlign.right
                ? MainAxisAlignment.end
                : (el.align == PrintElementAlign.center
                    ? MainAxisAlignment.center
                    : MainAxisAlignment.start),
            children: [
              Text(
                k.endsWith('：') || k.endsWith(':') ? k : '$k：',
                style: const TextStyle(
                  fontFamily: 'NSimSun',
                  fontFamilyFallback: _receiptFontFallbacks,
                  fontSize: 14.0,
                  height: 1.35,
                  letterSpacing: 0.0,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF374151),
                ),
              ),
              Text(
                v,
                style: TextStyle(
                  fontFamily: 'NSimSun',
                  fontFamilyFallback: _receiptFontFallbacks,
                  fontSize: 14.0,
                  height: 1.35,
                  letterSpacing: 0.0,
                  fontWeight: el.bold ? FontWeight.w800 : FontWeight.w600,
                  color: const Color(0xFF111827),
                ),
              ),
            ],
          ),
        );

      case PrintElementType.qrcode:
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Icon(Icons.qr_code_2_rounded, size: is80mm ? 84 : 68, color: Colors.black87),
                if (el.text != null && el.text!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    el.text!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF4B5563),
                      fontFamily: 'NSimSun',
                      fontFamilyFallback: _receiptFontFallbacks,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      case PrintElementType.barcode:
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              children: [
                Icon(Icons.view_week_outlined, size: is80mm ? 44 : 32, color: Colors.black87),
                if (el.text != null && el.text!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    el.text!,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF4B5563),
                      fontFamily: 'NSimSun',
                      fontFamilyFallback: _receiptFontFallbacks,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );

      case PrintElementType.cut:
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.content_cut_rounded, size: 12, color: Color(0xFF6B7280)),
              SizedBox(width: 4),
              Flexible(
                child: Text(
                  '- - - - - 切刀裁切线 - - - - -',
                style: TextStyle(
                  fontSize: 10,
                  color: Color(0xFF6B7280),
                    fontFamily: 'NSimSun',
                    fontFamilyFallback: _receiptFontFallbacks,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        );

      case PrintElementType.text:
      default:
        // 空行处理
        if (el.text == null || el.text!.isEmpty) {
          return const SizedBox(height: 14.0);
        }

        final align = el.align == PrintElementAlign.center
            ? TextAlign.center
            : el.align == PrintElementAlign.right
                ? TextAlign.right
                : TextAlign.left;
        final isDouble = el.size == PrintElementSize.double;
        final isLarge = el.size == PrintElementSize.large;
        final fontSize = isDouble ? 22.0 : (isLarge ? 18.0 : 14.0);

        return Padding(
          padding: EdgeInsets.symmetric(vertical: isDouble ? 3.0 : 1.0),
          child: Text(
            el.text!,
            textAlign: align,
            style: TextStyle(
              fontFamily: 'NSimSun',
              fontFamilyFallback: _receiptFontFallbacks,
              fontSize: fontSize,
              height: 1.35,
              letterSpacing: isDouble ? 0.5 : 0.0,
              fontWeight: isDouble ? FontWeight.w900 : (el.bold ? FontWeight.w800 : FontWeight.w500),
              color: const Color(0xFF111827),
            ),
          ),
        );
    }
  }

  Widget _buildTearEdge() {
    return Container(
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
        ),
      ),
      child: Row(
        children: List.generate(
          30,
          (i) => Expanded(
            child: Container(
              color: i.isEven ? const Color(0xFFE5E7EB) : const Color(0xFFFAF9F6),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomCutEdge() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F4F6),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.content_cut_rounded, size: 14, color: Color(0xFF9CA3AF)),
          SizedBox(width: 6),
          Flexible(
            child: Text(
              '-- 自动裁刀切纸线 (Cut Line) --',
              style: TextStyle(
                fontSize: 10,
                color: Color(0xFF4B5563),
                fontFamily: 'NSimSun',
                fontFamilyFallback: _receiptFontFallbacks,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
