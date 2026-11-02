import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/crash_log.dart';
import '../data/cashier_settings_repository.dart';
import '../domain/printing_template_models.dart';
import '../domain/receipt_preview_models.dart';
import 'cashier_receipt_preview_dialog.dart';
import 'cashier_exact_print_preview_dialog.dart';
import 'cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

/// 弹出可视化小票模板设计器（支持纯文本参数绑定与区块可视化双模式）
Future<PrintingTemplate?> showCashierPrintingTemplateDesignerDialog({
  required BuildContext context,
  required CashierSettingsRepository repository,
  required String storeName,
  PrintingTemplate? template,
  String initialScenario = 'ORDER',
  String initialPaperSize = '58mm',
}) {
  return showDialog<PrintingTemplate>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => CashierPrintingTemplateDesignerDialog(
      repository: repository,
      storeName: storeName,
      template: template,
      initialScenario: initialScenario,
      initialPaperSize: initialPaperSize,
    ),
  );
}

class CashierPrintingTemplateDesignerDialog extends StatefulWidget {
  const CashierPrintingTemplateDesignerDialog({
    super.key,
    required this.repository,
    required this.storeName,
    this.template,
    this.initialScenario = 'ORDER',
    this.initialPaperSize = '58mm',
  });

  final CashierSettingsRepository repository;
  final String storeName;
  final PrintingTemplate? template;
  final String initialScenario;
  final String initialPaperSize;

  @override
  State<CashierPrintingTemplateDesignerDialog> createState() =>
      _CashierPrintingTemplateDesignerDialogState();
}

class _CashierPrintingTemplateDesignerDialogState
    extends State<CashierPrintingTemplateDesignerDialog> {
  static const _nativeCrashGuardChannel = MethodChannel(
    'laofei_cashier/native_crash_guard',
  );

  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _rawTextController;
  late String _scenario;
  late String _paperSize;
  late bool _isDefault;
  late PrintTemplateDsl _dsl;
  late String _editorMode; // 'TEXT' (纯文本参数绑定) 或 'BLOCK' (可视化区块)
  late int _selectedBlockIndex;

  bool _saving = false;
  bool _nativeTextEditorGuardEnabled = false;
  Timer? _debounceTimer;

  // 模板元数据（支持从后端 GET /admin/printing/templates/meta 动态拉取）
  PrintingTemplateMeta? _templateMeta;

  // 实时小票预览数据
  PrintPreviewResult? _previewResult;
  bool _previewLoading = false;
  String? _previewError;

  @override
  void initState() {
    super.initState();
    final tpl = widget.template;
    final rawScenario = tpl?.scenario ?? widget.initialScenario;
    _scenario = ReceiptTemplateScenario.fromCode(rawScenario).code;
    _paperSize = tpl?.paperSize ?? widget.initialPaperSize;
    _isDefault = tpl?.isDefault ?? false;
    _nameController = TextEditingController(
      text: tpl != null
          ? (tpl.isSystem ? '${tpl.templateName} (自定义)' : tpl.templateName)
          : _defaultNameForScenario(_scenario),
    );
    _codeController = TextEditingController(
      text: tpl != null && !tpl.isSystem
          ? tpl.templateCode
          : 'tpl_${_scenario.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 10000}',
    );

    if (tpl?.templateDsl != null) {
      _dsl = tpl!.templateDsl!.copyWith(
        scenario: _scenario,
        paperSize: _paperSize,
      );
    } else if (tpl?.templateJson != null && tpl!.templateJson!.isNotEmpty) {
      try {
        final decoded = jsonDecode(tpl.templateJson!);
        _dsl = PrintTemplateDsl.fromJson(
          (decoded as Map).cast<String, Object?>(),
        ).copyWith(scenario: _scenario, paperSize: _paperSize);
      } catch (_) {
        _dsl = PrintTemplateDsl.defaultForScenario(
          _scenario,
          paperSize: _paperSize,
        );
      }
    } else {
      _dsl = PrintTemplateDsl.defaultForScenario(
        _scenario,
        paperSize: _paperSize,
      );
    }

    _editorMode = _dsl.mode == 'TEXT' ? 'TEXT' : 'BLOCK';
    final initialText =
        _dsl.rawTemplate ??
        PrintTemplateDsl.defaultTextTemplateForScenario(_scenario);
    _rawTextController = TextEditingController(text: initialText);
    _dsl = _dsl.copyWith(
      mode: _editorMode,
      rawTemplate: initialText,
      scenario: _scenario,
      paperSize: _paperSize,
    );

    _selectedBlockIndex = _dsl.blocks.isNotEmpty ? 0 : -1;

    CrashLog.instance.recordBreadcrumb(
      category: 'printing_template',
      message: 'editor_opened mode=$_editorMode scenario=$_scenario',
    );
    if (_editorMode == 'TEXT') {
      unawaited(_setNativeTextEditorGuard(true));
    }
    _loadTemplateMeta();
    _scheduleLivePreview();
  }

  Future<void> _loadTemplateMeta() async {
    try {
      final meta = await widget.repository.getPrintingTemplateMeta();
      if (mounted && meta.scenarios.isNotEmpty) {
        setState(() {
          _templateMeta = meta;
        });
      }
    } catch (_) {
      // 忽略或使用本地预设 fallback
    }
  }

  List<PrintingTemplateScenarioMeta> get _scenarioOptions {
    final remote = _templateMeta?.scenarios ?? const [];
    final options = remote.isNotEmpty
        ? List<PrintingTemplateScenarioMeta>.of(remote)
        : ReceiptTemplateScenario.values
              .map(
                (scenario) => PrintingTemplateScenarioMeta(
                  code: scenario.code,
                  name: scenario.shortLabel,
                  description: scenario.description,
                ),
              )
              .toList(growable: true);
    if (options.every((item) => item.code != _scenario)) {
      options.add(
        PrintingTemplateScenarioMeta(
          code: _scenario,
          name: _defaultNameForScenario(_scenario),
        ),
      );
    }
    return options;
  }

  static String _defaultNameForScenario(String scenario) {
    switch (scenario.toUpperCase()) {
      case 'KITCHEN':
        return '后厨制作小票';
      case 'FULL_ORDER':
        return '前台整单小票';
      case 'PRE_CHECKOUT':
        return '预结单模板';
      case 'CHECKOUT':
        return '前台结账小票';
      case 'EXPEDITE':
        return '后厨传菜单';
      case 'TAKEOUT':
        return '外卖配送小票';
      case 'PACKING':
        return '打包单模板';
      case 'SHIFT':
        return '收银交接班报表';
      case 'REFUND':
        return '订单退款单据';
      case 'LABEL':
        return '商品标签杯贴';
      case 'TEST':
        return '自检测试小票';
      case 'ORDER':
        return '通用点餐小票';
      default:
        return '点餐小票模板';
    }
  }

  void _onScenarioChanged(String newScenario) {
    final canon = ReceiptTemplateScenario.fromCode(newScenario).code;
    if (canon == _scenario) return;
    setState(() {
      _scenario = canon;
      _dsl = _dsl.copyWith(scenario: _scenario);
      _nameController.text = _defaultNameForScenario(_scenario);
      _codeController.text =
          'tpl_${_scenario.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 10000}';
    });
    _resetToDefaultTextTemplate();
  }

  @override
  void dispose() {
    CrashLog.instance.recordBreadcrumb(
      category: 'printing_template',
      message: 'editor_closed mode=$_editorMode scenario=$_scenario',
    );
    if (_nativeTextEditorGuardEnabled) {
      unawaited(_setNativeTextEditorGuard(false));
    }
    _debounceTimer?.cancel();
    _nameController.dispose();
    _codeController.dispose();
    _rawTextController.dispose();
    super.dispose();
  }

  Future<void> _setNativeTextEditorGuard(bool enabled) async {
    if (_nativeTextEditorGuardEnabled == enabled) return;
    _nativeTextEditorGuardEnabled = enabled;
    CrashLog.instance.recordBreadcrumb(
      category: 'printing_template',
      message: 'native_accessibility_guard_${enabled ? 'enabled' : 'disabled'}',
    );
    try {
      await _nativeCrashGuardChannel.invokeMethod<void>(
        'setReceiptTemplateTextGuard',
        enabled,
      );
    } on MissingPluginException {
      // Non-Windows hosts and widget tests do not install the runner channel.
    } on PlatformException catch (error) {
      CrashLog.instance.recordBreadcrumb(
        category: 'printing_template',
        message: 'native_accessibility_guard_failed code=${error.code}',
        level: 'warning',
      );
    }
  }

  Future<void> _pasteRawTemplateFromClipboard() async {
    final selection = _rawTextController.selection;
    CrashLog.instance.recordBreadcrumb(
      category: 'printing_template',
      message:
          'paste_started mode=TEXT selection=${selection.start}:${selection.end}',
      data: {
        'editor_mode': 'TEXT',
        'selection_start': selection.start,
        'selection_end': selection.end,
      },
    );
    try {
      final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
      final pastedText = clipboard?.text;
      if (pastedText == null || pastedText.isEmpty) {
        CrashLog.instance.recordBreadcrumb(
          category: 'printing_template',
          message: 'paste_ignored reason=empty_clipboard',
        );
        return;
      }

      final current = _rawTextController.value;
      final textLength = current.text.length;
      final rawStart = current.selection.isValid
          ? current.selection.start
          : textLength;
      final rawEnd = current.selection.isValid
          ? current.selection.end
          : textLength;
      final start = rawStart.clamp(0, textLength);
      final end = rawEnd.clamp(start, textLength);
      final updatedText = current.text.replaceRange(start, end, pastedText);
      _rawTextController.value = TextEditingValue(
        text: updatedText,
        selection: TextSelection.collapsed(offset: start + pastedText.length),
      );
      _dsl = _dsl.copyWith(mode: 'TEXT', rawTemplate: updatedText);
      _markDirty();
      CrashLog.instance.recordBreadcrumb(
        category: 'printing_template',
        message:
            'paste_completed character_count=${pastedText.length} total_length=${updatedText.length}',
        data: {
          'character_count': pastedText.length,
          'total_length': updatedText.length,
        },
      );
    } on PlatformException catch (error) {
      CrashLog.instance.recordBreadcrumb(
        category: 'printing_template',
        message: 'paste_failed code=${error.code}',
        level: 'error',
      );
    }
  }

  void _markDirty() {
    _scheduleLivePreview();
  }

  void _scheduleLivePreview() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      const Duration(milliseconds: 250),
      _fetchLivePreview,
    );
  }

  Future<void> _fetchLivePreview() async {
    if (!mounted) return;
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });

    try {
      final res = await widget.repository.fetchPrintPreview(
        scenario: _scenario,
        paperSize: _paperSize,
        templateDsl: _dsl.toJson(),
      );
      if (mounted) {
        setState(() {
          _previewResult = res;
          _previewLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewError = e.toString();
          _previewLoading = false;
        });
      }
    }
  }

  void _insertParameterTag(String tag) {
    final text = _rawTextController.text;
    final selection = _rawTextController.selection;
    final start = selection.start;
    final end = selection.end;

    if (start >= 0 && end >= start) {
      final newText = text.replaceRange(start, end, tag);
      _rawTextController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + tag.length),
      );
    } else {
      final newText = '$text$tag';
      _rawTextController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }
    _dsl = _dsl.copyWith(mode: 'TEXT', rawTemplate: _rawTextController.text);
    _markDirty();
  }

  void _resetToDefaultTextTemplate() {
    final defaultText = PrintTemplateDsl.defaultTextTemplateForScenario(
      _scenario,
    );
    _rawTextController.text = defaultText;
    final defaultDsl = PrintTemplateDsl.defaultForScenario(
      _scenario,
      paperSize: _paperSize,
    );
    setState(() {
      _dsl = defaultDsl.copyWith(mode: _editorMode, rawTemplate: defaultText);
      _selectedBlockIndex = _dsl.blocks.isNotEmpty ? 0 : -1;
    });
    _markDirty();
  }

  void _updateCurrentBlockConfig(String key, Object? value) {
    if (_selectedBlockIndex < 0 || _selectedBlockIndex >= _dsl.blocks.length)
      return;
    final block = _dsl.blocks[_selectedBlockIndex];
    final updatedConfig = Map<String, Object?>.from(block.config);
    if (value == null) {
      updatedConfig.remove(key);
    } else {
      updatedConfig[key] = value;
    }
    final updatedBlock = block.copyWith(config: updatedConfig);
    final updatedBlocks = List<TemplateBlock>.from(_dsl.blocks);
    updatedBlocks[_selectedBlockIndex] = updatedBlock;

    setState(() {
      _dsl = _dsl.copyWith(blocks: updatedBlocks);
    });
    _markDirty();
  }

  void _toggleBlockEnabled(int index, bool enabled) {
    if (index < 0 || index >= _dsl.blocks.length) return;
    final block = _dsl.blocks[index];
    final updatedBlock = block.copyWith(enabled: enabled);
    final updatedBlocks = List<TemplateBlock>.from(_dsl.blocks);
    updatedBlocks[index] = updatedBlock;

    setState(() {
      _dsl = _dsl.copyWith(blocks: updatedBlocks);
    });
    _markDirty();
  }

  void _moveBlock(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _dsl.blocks.length ||
        newIndex < 0 ||
        newIndex >= _dsl.blocks.length)
      return;
    final updatedBlocks = List<TemplateBlock>.from(_dsl.blocks);
    final item = updatedBlocks.removeAt(oldIndex);
    updatedBlocks.insert(newIndex, item);

    setState(() {
      _dsl = _dsl.copyWith(blocks: updatedBlocks);
      _selectedBlockIndex = newIndex;
    });
    _markDirty();
  }

  void _addNewCustomBlock(String type) {
    final id =
        'block_${type.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 10000}';
    String name;
    Map<String, Object?> config;

    switch (type) {
      case 'HEADER':
        name = '单据抬头';
        config = {
          'titleType': 'SHOP_NAME',
          'align': 'CENTER',
          'size': 'DOUBLE',
          'bold': true,
        };
        break;
      case 'ORDER_INFO':
        name = '订单基础信息';
        config = {
          'showTableNo': true,
          'showDineInType': true,
          'showOrderNo': true,
          'showOrderTime': true,
        };
        break;
      case 'DISH_ITEMS':
        name = '菜品明细列表';
        config = {
          'showTableHead': true,
          'showUnitPrice': true,
          'showQuantity': true,
          'showTotalPrice': true,
        };
        break;
      case 'PAYMENT_SUMMARY':
        name = '结算与支付汇总';
        config = {
          'showOriginalAmount': true,
          'showDiscountAmount': true,
          'showActualAmount': true,
          'showPayChannel': true,
        };
        break;
      case 'DELIVERY_INFO':
        name = '外卖配送信息';
        config = {
          'showReceiverName': true,
          'showReceiverPhone': true,
          'showDeliveryAddress': true,
          'showExpectedTime': true,
        };
        break;
      case 'MEMBER_INFO':
        name = '会员营销信息';
        config = {'label': '会员卡号：VIP-', 'customNotice': '积分可抵扣现金'};
        break;
      case 'REMARK':
        name = '整单备注';
        config = {'label': '整单备注：', 'size': 'NORMAL', 'bold': true};
        break;
      case 'DIVIDER':
        name = '分割横线';
        config = {
          'char': '-',
          'length': _paperSize == '80mm' ? 48 : 32,
          'text': _paperSize == '80mm'
              ? '------------------------------------------------'
              : '--------------------------------',
          'linesBefore': 0,
          'linesAfter': 0,
        };
        break;
      case 'SPACING':
        name = '空白间距行';
        config = {'lines': 1};
        break;
      case 'QRCODE':
        name = '自定义二维码';
        config = {
          'qrCodeUrl': 'https://u.wechat.com/EF9MZwaAbHhL79QCtBgAVAA?s=2',
          'qrCodeNote': '扫码参与门店活动',
          'linesBefore': 1,
          'linesAfter': 1,
        };
        break;
      case 'FOOTER':
        name = '页脚结语';
        config = {'thankText': '感谢惠顾 欢迎再次光临', 'showQrCode': true};
        break;
      case 'CUSTOM_TEXT':
      default:
        name = '自定义文字';
        config = {
          'content': '欢迎再次光临',
          'align': 'CENTER',
          'size': 'NORMAL',
          'bold': false,
          'linesBefore': 0,
          'linesAfter': 0,
        };
        break;
    }

    final newBlock = TemplateBlock(
      id: id,
      type: type,
      name: name,
      enabled: true,
      config: config,
    );

    final updatedBlocks = List<TemplateBlock>.from(_dsl.blocks)..add(newBlock);
    setState(() {
      _dsl = _dsl.copyWith(blocks: updatedBlocks);
      _selectedBlockIndex = updatedBlocks.length - 1;
    });
    _markDirty();
  }

  void _deleteBlock(int index) {
    if (index < 0 || index >= _dsl.blocks.length) return;
    final updatedBlocks = List<TemplateBlock>.from(_dsl.blocks)
      ..removeAt(index);
    setState(() {
      _dsl = _dsl.copyWith(blocks: updatedBlocks);
      _selectedBlockIndex = updatedBlocks.isEmpty
          ? -1
          : (index >= updatedBlocks.length ? updatedBlocks.length - 1 : index);
    });
    _markDirty();
  }

  void _cloneBlock(int index) {
    if (index < 0 || index >= _dsl.blocks.length) return;
    final target = _dsl.blocks[index];
    final cloned = TemplateBlock(
      id: '${target.type.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 10000}',
      type: target.type,
      name: '${target.name} (副本)',
      enabled: target.enabled,
      config: Map<String, Object?>.from(target.config),
    );
    final updatedBlocks = List<TemplateBlock>.from(_dsl.blocks)
      ..insert(index + 1, cloned);
    setState(() {
      _dsl = _dsl.copyWith(blocks: updatedBlocks);
      _selectedBlockIndex = index + 1;
    });
    _markDirty();
  }

  Future<void> _handleSave() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入模板名称')));
      return;
    }

    setState(() => _saving = true);
    try {
      final isEdit =
          widget.template != null &&
          widget.template!.id > 0 &&
          !widget.template!.isSystem;
      final finalDsl = _dsl.copyWith(
        scenario: _scenario,
        paperSize: _paperSize,
        mode: _editorMode,
        rawTemplate: _editorMode == 'TEXT'
            ? _rawTextController.text
            : _dsl.rawTemplate,
      );
      final dslJson = jsonEncode(finalDsl.toJson());

      PrintingTemplate result;
      if (isEdit) {
        result = await widget.repository.updatePrintingTemplate(
          id: widget.template!.id,
          version: widget.template!.version,
          templateName: name,
          scenario: _scenario,
          paperSize: _paperSize,
          isDefault: _isDefault,
          templateJson: dslJson,
          templateDsl: finalDsl.toJson(),
        );
      } else {
        final code = _codeController.text.trim().isNotEmpty
            ? _codeController.text.trim()
            : 'tpl_${_scenario.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 10000}';
        result = await widget.repository.createPrintingTemplate(
          templateName: name,
          templateCode: code,
          scenario: _scenario,
          paperSize: _paperSize,
          isDefault: _isDefault,
          templateJson: dslJson,
          templateDsl: finalDsl.toJson(),
        );
      }

      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final errorStr = e.toString();
      if (errorStr.contains('409') || errorStr.contains('VERSION_CONFLICT')) {
        await showSettingsConfirmDialog(
          context: context,
          title: '模板版本冲突 (409)',
          message: '该模板已被其他终端或管理员修改，请刷新并重新编辑。',
          confirmLabel: '我知道了',
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存模板失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.template != null && widget.template!.id > 0;

    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 1320,
          height: 860,
          child: Column(
            children: [
              // 顶部头部导航栏
              _buildTopHeader(isEdit),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),

              // 主体编辑区：纯文本参数绑定 或 可视化区块 + 右侧真实热敏纸模拟器
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左侧与中间编辑区
                    Expanded(
                      child: _editorMode == 'TEXT'
                          ? _buildPureTextEditorPanel()
                          : _buildBlockModeEditorRow(),
                    ),
                    const VerticalDivider(width: 1, color: Color(0xFFE5E7EB)),

                    // 右侧：真实热敏纸模拟器纸卷
                    SizedBox(width: 380, child: _buildLivePaperPreviewPanel()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(bool isEdit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: const Color(0xFFF9FAFB),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              color: Color(0xFF2563EB),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isEdit ? '编辑小票模板' : '新建自定义小票模板',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 场景切换下拉框
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _scenario,
                          isDense: true,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1D4ED8),
                          ),
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            size: 18,
                            color: Color(0xFF1D4ED8),
                          ),
                          items: _scenarioOptions
                              .map(
                                (scenario) => DropdownMenuItem(
                                  value: scenario.code,
                                  child: Text(
                                    '${scenario.name} (${scenario.code})',
                                  ),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: (v) {
                            if (v != null) _onScenarioChanged(v);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // 编辑模式切换 SegmentedButton
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'TEXT',
                          icon: Icon(Icons.code_rounded, size: 14),
                          label: Text(
                            '纯文本参数绑定',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        ButtonSegment(
                          value: 'BLOCK',
                          icon: Icon(
                            Icons.dashboard_customize_outlined,
                            size: 14,
                          ),
                          label: Text('可视化区块', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                      selected: {_editorMode},
                      onSelectionChanged: (set) {
                        final nextMode = set.first;
                        unawaited(
                          _setNativeTextEditorGuard(nextMode == 'TEXT'),
                        );
                        setState(() {
                          _editorMode = nextMode;
                          _dsl = _dsl.copyWith(mode: _editorMode);
                        });
                        _markDirty();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _editorMode == 'TEXT'
                      ? '直接输入小票文本排版，使用 {菜品}、{单价}、{数量}、{金额}、{桌号} 绑定动态参数，右侧即时精准预览'
                      : '可视化拖拽区块与细化编辑，右侧实时渲染',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
              ],
            ),
          ),

          // 设为默认模板 Switch
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '设为默认模板',
                style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
              ),
              const SizedBox(width: 6),
              Switch.adaptive(
                value: _isDefault,
                activeColor: const Color(0xFF2563EB),
                onChanged: (val) {
                  setState(() => _isDefault = val);
                  _markDirty();
                },
              ),
            ],
          ),
          const SizedBox(width: 16),

          // 取消按钮
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: 10),

          // 保存模板按钮
          FilledButton.icon(
            key: const Key('settings-template-save-btn'),
            onPressed: _saving ? null : _handleSave,
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check, size: 16),
            label: Text(_saving ? '保存中...' : '保存模板'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// 纯文本排版 + 参数绑定编辑器面板
  Widget _buildPureTextEditorPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部参数快速插入工具栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: const Color(0xFFF8FAFC),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 16,
                        color: Color(0xFF2563EB),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '点击直接插入动态绑定参数：',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                        ),
                        onPressed: _resetToDefaultTextTemplate,
                        icon: const Icon(Icons.restart_alt_rounded, size: 13),
                        label: const Text(
                          '重置为标准预设',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: '58mm',
                            label: Text('58mm (32列)'),
                          ),
                          ButtonSegment(
                            value: '80mm',
                            label: Text('80mm (48列)'),
                          ),
                        ],
                        selected: {_paperSize},
                        onSelectionChanged: (set) {
                          setState(() {
                            _paperSize = set.first;
                            _dsl = _dsl.copyWith(paperSize: _paperSize);
                          });
                          _markDirty();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 根据场景动态展示的参数群
              _buildVariableButtonsForCurrentScenario(),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // 模板名称配置条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.white,
          child: Row(
            children: [
              const Text(
                '模板名称: ',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
              ),
              const Spacer(),
              // 硬件选项快速微调
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('自动切刀', style: TextStyle(fontSize: 12)),
                  Switch.adaptive(
                    value: _dsl.autoCut,
                    activeColor: const Color(0xFF2563EB),
                    onChanged: (val) {
                      setState(() => _dsl = _dsl.copyWith(autoCut: val));
                      _markDirty();
                    },
                  ),
                  const SizedBox(width: 8),
                  const Text('走纸:', style: TextStyle(fontSize: 12)),
                  DropdownButton<int>(
                    value: _dsl.feedLines,
                    underline: const SizedBox(),
                    items: [1, 2, 3, 4, 5]
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(
                              '$e 行',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _dsl = _dsl.copyWith(feedLines: val));
                        _markDirty();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE2E8F0)),

        // 纯文本大代码编辑器
        Expanded(
          child: Container(
            color: const Color(0xFF0F172A),
            padding: const EdgeInsets.all(16),
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  control: true,
                ): () =>
                    unawaited(_pasteRawTemplateFromClipboard()),
                const SingleActivator(
                  LogicalKeyboardKey.keyV,
                  meta: true,
                ): () =>
                    unawaited(_pasteRawTemplateFromClipboard()),
                const SingleActivator(
                  LogicalKeyboardKey.insert,
                  shift: true,
                ): () =>
                    unawaited(_pasteRawTemplateFromClipboard()),
              },
              child: TextField(
                key: const Key('settings-template-raw-text-editor'),
                controller: _rawTextController,
                maxLines: null,
                expands: true,
                keyboardType: TextInputType.multiline,
                // 展开式 TextField 失焦时内容会垂直居中、获焦后回到顶部，造成文字位置跳动；
                // 显式锁定左上对齐，保证焦点切换时文字位置稳定。
                textAlign: TextAlign.start,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontFamily: 'Courier New',
                  fontSize: 13.5,
                  height: 1.5,
                  color: Color(0xFFE2E8F0),
                  letterSpacing: 0.5,
                ),
                // 固定统一行高：中文回退字体与 Courier New 的基线度量不同，
                // 不设 strut 时各行高度随字符变化，导致编辑时文字/光标上下跳动
                strutStyle: const StrutStyle(
                  fontFamily: 'Courier New',
                  fontSize: 13.5,
                  height: 1.5,
                  forceStrutHeight: true,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  hintText: '在此输入小票排版内容与绑定参数...',
                  hintStyle: TextStyle(color: Color(0xFF64748B)),
                ),
                onChanged: (val) {
                  _dsl = _dsl.copyWith(mode: 'TEXT', rawTemplate: val);
                  _markDirty();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVariableButtonsForCurrentScenario() {
    final upper = _scenario.toUpperCase();

    if (upper == 'SHIFT') {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Text(
              '交接班报表参数:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
          _buildVariableChip('{shiftId}', '班次ID'),
          _buildVariableChip('{cashier}', '收银员'),
          _buildVariableChip('{startTime}', '开班时间'),
          _buildVariableChip('{endTime}', '交班时间'),
          _buildVariableChip('{startCash}', '开班备用金'),
          _buildVariableChip('{orderCount}', '总单数'),
          _buildVariableChip('{totalAmount}', '实收总额'),
          _buildVariableChip('{wechatAmount}', '微信收款'),
          _buildVariableChip('{alipayAmount}', '支付宝收款'),
          _buildVariableChip('{cashAmount}', '现金收款'),
          _buildVariableChip('{memberAmount}', '会员收款'),
          _buildVariableChip('{totalRefund}', '退款总额'),
          _buildVariableChip('{printTime}', '打印时间'),
          const SizedBox(width: 8),
          _buildVariableChip(
            _paperSize == '80mm'
                ? '------------------------------------------------'
                : '--------------------------------',
            '标准分割线',
            isSpecial: true,
          ),
        ],
      );
    }

    if (upper == 'REFUND') {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: const Text(
              '退款单参数:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB91C1C),
              ),
            ),
          ),
          _buildVariableChip('{orderNo}', '原订单号'),
          _buildVariableChip('{tableNo}', '桌台号'),
          _buildVariableChip('{originalAmount}', '原单金额'),
          _buildVariableChip('{refundAmount}', '退款金额'),
          _buildVariableChip('{refundReason}', '退款原因'),
          _buildVariableChip('{refundChannel}', '退款渠道'),
          _buildVariableChip('{operator}', '操作人员'),
          _buildVariableChip('{refundTime}', '退款时间'),
          const SizedBox(width: 8),
          _buildVariableChip(
            _paperSize == '80mm'
                ? '------------------------------------------------'
                : '--------------------------------',
            '标准分割线',
            isSpecial: true,
          ),
        ],
      );
    }

    if (upper == 'LABEL') {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Text(
              '标签杯贴参数:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF15803D),
              ),
            ),
          ),
          _buildVariableChip('{goodsName}', '品名'),
          _buildVariableChip('{spec}', '规格'),
          _buildVariableChip('{spicy}', '辣度'),
          _buildVariableChip('{quantity}', '数量'),
          _buildVariableChip('{price}', '单价'),
          _buildVariableChip('{tableNo}', '桌号'),
          _buildVariableChip('{orderNo}', '订单号'),
          _buildVariableChip('{time}', '出标时间'),
          const SizedBox(width: 8),
          _buildVariableChip('{二维码}', '条码/二维码', isSpecial: true),
        ],
      );
    }

    if (upper == 'TAKEOUT') {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Text(
              '外卖配送:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
          ),
          _buildVariableChip('{外卖平台}', '平台'),
          _buildVariableChip('{收件人}', '顾客名'),
          _buildVariableChip('{收件人电话}', '电话'),
          _buildVariableChip('{配送地址}', '地址'),
          _buildVariableChip('{配送时间}', '送达时间'),
          _buildVariableChip('{打包费}', '餐盒费'),
          _buildVariableChip('{配送费}', '配送费'),
          _buildVariableChip('{订单号}', '订单号'),
          _buildVariableChip('{实付}', '实付'),
          _buildVariableChip('{备注}', '备注'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Text(
              '菜品循环:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
          ),
          _buildVariableChip('{菜品}', '菜品名'),
          _buildVariableChip('{规格}', '口味规格'),
          _buildVariableChip('{单价}', '单价'),
          _buildVariableChip('{数量}', '数量'),
          _buildVariableChip('{金额}', '金额'),
          const SizedBox(width: 8),
          _buildVariableChip(
            _paperSize == '80mm'
                ? '------------------------------------------------'
                : '--------------------------------',
            '标准分割线',
            isSpecial: true,
          ),
        ],
      );
    }

    if (upper == 'KITCHEN' || upper == 'EXPEDITE') {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Text(
              '后厨菜品循环:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
          ),
          _buildVariableChip('{菜品}', '菜品名'),
          _buildVariableChip('{规格}', '口味规格'),
          _buildVariableChip('{数量}', '数量'),
          _buildVariableChip('{菜品}                {数量}', '整行商品格式'),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFBFDBFE)),
            ),
            child: const Text(
              '台号与时间:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1D4ED8),
              ),
            ),
          ),
          _buildVariableChip('{桌号}', '桌号'),
          _buildVariableChip('{加菜}', '加菜'),
          _buildVariableChip('{订单ID}', '订单ID'),
          _buildVariableChip('{订单号}', '单号'),
          _buildVariableChip('{下单时间}', '下单时间'),
          _buildVariableChip('{备注}', '整单制作备注'),
          const SizedBox(width: 8),
          _buildVariableChip(
            _paperSize == '80mm'
                ? '------------------------------------------------'
                : '--------------------------------',
            '标准分割线',
            isSpecial: true,
          ),
        ],
      );
    }

    if (upper == 'PACKING') {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _buildVariableChip('{取餐码}', '取餐码'),
          _buildVariableChip('{订单号}', '订单号'),
          _buildVariableChip('{用餐方式}', '用餐方式'),
          _buildVariableChip('{下单时间}', '下单时间'),
          _buildVariableChip('{备注}', '打包备注'),
          _buildVariableChip('{菜品}', '菜品名'),
          _buildVariableChip('{规格}', '口味规格'),
          _buildVariableChip('{数量}', '数量'),
        ],
      );
    }

    // 全量标准订单/整单/结账/预结单
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // 菜品循环字段
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF3C7),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFDE68A)),
          ),
          child: const Text(
            '菜品循环:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFFB45309),
            ),
          ),
        ),
        _buildVariableChip('{菜品}', '菜品名'),
        _buildVariableChip('{规格}', '口味规格'),
        _buildVariableChip('{单价}', '单价'),
        _buildVariableChip('{数量}', '数量'),
        _buildVariableChip('{金额}', '金额小计'),
        _buildVariableChip('{菜品}    {单价}     {数量}  {金额}', '整行商品格式'),

        const SizedBox(width: 8),
        // 桌台与订单
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Text(
            '订单信息:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1D4ED8),
            ),
          ),
        ),
        _buildVariableChip('{门店名称}', '店名'),
        _buildVariableChip('{桌号}', '桌号'),
        _buildVariableChip('{加菜}', '加菜'),
        _buildVariableChip('{订单ID}', '订单ID'),
        _buildVariableChip('{订单号}', '单号'),
        _buildVariableChip('{用餐方式}', '就餐类型'),
        _buildVariableChip('{下单时间}', '下单时间'),
        _buildVariableChip('{结账时间}', '结账时间'),
        _buildVariableChip('{会员卡号}', '会员卡号'),
        _buildVariableChip('{备注}', '整单备注'),

        const SizedBox(width: 8),
        // 结算金额
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFA7F3D0)),
          ),
          child: const Text(
            '金额汇总:',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Color(0xFF047857),
            ),
          ),
        ),
        _buildVariableChip('{原价}', '原价合计'),
        _buildVariableChip('{打包费}', '打包费'),
        _buildVariableChip('{优惠}', '优惠金额'),
        _buildVariableChip('{实付}', '实付应收'),
        _buildVariableChip('{支付方式}', '支付渠道'),

        const SizedBox(width: 8),
        // 排版元素
        _buildVariableChip('{二维码}', '动态二维码', isSpecial: true),
        _buildVariableChip(
          _paperSize == '80mm'
              ? '------------------------------------------------'
              : '--------------------------------',
          '标准分割线',
          isSpecial: true,
        ),
      ],
    );
  }

  Widget _buildVariableChip(
    String tag,
    String label, {
    bool isSpecial = false,
  }) {
    return InkWell(
      onTap: () => _insertParameterTag(tag),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: isSpecial ? const Color(0xFFF1F5F9) : Colors.white,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSpecial
                ? const Color(0xFFCBD5E1)
                : const Color(0xFF93C5FD),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, size: 11, color: Color(0xFF2563EB)),
            const SizedBox(width: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF1E293B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 原可视化区块编辑模式双栏（保持完整兼容）
  Widget _buildBlockModeEditorRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 290, child: _buildBlocksListPanel()),
        const VerticalDivider(width: 1, color: Color(0xFFE5E7EB)),
        Expanded(child: _buildBlockPropertiesPanel()),
      ],
    );
  }

  Widget _buildBlocksListPanel() {
    return Container(
      color: const Color(0xFFF9FAFB),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      '小票区块构成',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_dsl.blocks.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: '添加区块',
                  onSelected: _addNewCustomBlock,
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'HEADER',
                      child: Row(
                        children: [
                          Icon(
                            Icons.title_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('单据抬头 (HEADER)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'ORDER_INFO',
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('订单信息 (ORDER_INFO)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'DISH_ITEMS',
                      child: Row(
                        children: [
                          Icon(
                            Icons.table_rows_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('菜品明细 (DISH_ITEMS)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'PAYMENT_SUMMARY',
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('结算汇总 (PAYMENT)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'DELIVERY_INFO',
                      child: Row(
                        children: [
                          Icon(
                            Icons.delivery_dining_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('外卖配送信息 (DELIVERY)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'MEMBER_INFO',
                      child: Row(
                        children: [
                          Icon(
                            Icons.card_membership_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('会员营销信息 (MEMBER)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'REMARK',
                      child: Row(
                        children: [
                          Icon(
                            Icons.notes_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('整单备注 (REMARK)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'CUSTOM_TEXT',
                      child: Row(
                        children: [
                          Icon(
                            Icons.text_fields_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('自定义文字 (CUSTOM_TEXT)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'DIVIDER',
                      child: Row(
                        children: [
                          Icon(
                            Icons.horizontal_rule_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('下划线/分割线 (DIVIDER)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'SPACING',
                      child: Row(
                        children: [
                          Icon(
                            Icons.format_line_spacing_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('空白间距行 (SPACING)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'QRCODE',
                      child: Row(
                        children: [
                          Icon(
                            Icons.qr_code_2_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('独立二维码 (QRCODE)'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'FOOTER',
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_downward_rounded,
                            size: 16,
                            color: Color(0xFF2563EB),
                          ),
                          SizedBox(width: 8),
                          Text('页脚标语 (FOOTER)'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Color(0xFF2563EB)),
                        SizedBox(width: 2),
                        Text(
                          '加区块',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),

          // 区块列表
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _dsl.blocks.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final block = _dsl.blocks[index];
                final isSelected = _selectedBlockIndex == index;
                final isCustom =
                    block.type == 'CUSTOM_TEXT' ||
                    block.type == 'DIVIDER' ||
                    block.type == 'SPACING' ||
                    block.type == 'QRCODE';

                return InkWell(
                  onTap: () => setState(() => _selectedBlockIndex = index),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFEFF6FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFFE5E7EB),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // 显隐开关
                        SizedBox(
                          width: 30,
                          height: 22,
                          child: Switch.adaptive(
                            value: block.enabled,
                            activeColor: const Color(0xFF2563EB),
                            onChanged: (val) => _toggleBlockEnabled(index, val),
                          ),
                        ),
                        const SizedBox(width: 6),

                        // 类型图标与名称
                        Icon(
                          _iconForBlock(block.type),
                          size: 16,
                          color: block.enabled
                              ? const Color(0xFF374151)
                              : const Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            block.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: block.enabled
                                  ? const Color(0xFF111827)
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ),

                        // 上下移动排序
                        if (index > 0)
                          InkWell(
                            onTap: () => _moveBlock(index, index - 1),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.arrow_upward_rounded,
                                size: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        if (index < _dsl.blocks.length - 1)
                          InkWell(
                            onTap: () => _moveBlock(index, index + 1),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.arrow_downward_rounded,
                                size: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ),

                        // 克隆按钮
                        InkWell(
                          onTap: () => _cloneBlock(index),
                          child: const Padding(
                            padding: EdgeInsets.all(2),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 13,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),

                        // 自定义区块删除按钮
                        if (isCustom)
                          InkWell(
                            onTap: () => _deleteBlock(index),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(
                                Icons.close_rounded,
                                size: 14,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockPropertiesPanel() {
    if (_selectedBlockIndex < 0 || _selectedBlockIndex >= _dsl.blocks.length) {
      return const Center(
        child: Text(
          '请在左侧选择需要配置的区块',
          style: TextStyle(color: Color(0xFF9CA3AF)),
        ),
      );
    }

    final block = _dsl.blocks[_selectedBlockIndex];
    final cfg = block.config;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 模板全局基础设置
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '模板全局属性',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '模板名称',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _markDirty(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 纸张规格切换
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '热敏纸规格',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                      const SizedBox(height: 4),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: '58mm',
                            label: Text('58mm (32列)'),
                          ),
                          ButtonSegment(
                            value: '80mm',
                            label: Text('80mm (48列)'),
                          ),
                        ],
                        selected: {_paperSize},
                        onSelectionChanged: (set) {
                          setState(() {
                            _paperSize = set.first;
                            _dsl = _dsl.copyWith(paperSize: _paperSize);
                          });
                          _markDirty();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 当前选中区块头部
        Row(
          children: [
            Icon(
              _iconForBlock(block.type),
              size: 20,
              color: const Color(0xFF2563EB),
            ),
            const SizedBox(width: 8),
            Text(
              '「${block.name}」细化编辑',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF111827),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 区块专门内容与样式编辑器
        _buildSpecificBlockEditor(block, cfg),

        const SizedBox(height: 16),
        // 区块通用空行间距调节组件
        _buildBlockSpacingControls(cfg),

        const SizedBox(height: 20),
        const Divider(color: Color(0xFFE5E7EB)),
        const SizedBox(height: 12),

        // 全局打印机硬件动作参数
        const Text(
          '打印机硬件出票动作',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('出票自动切刀', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Switch.adaptive(
                  value: _dsl.autoCut,
                  activeColor: const Color(0xFF2563EB),
                  onChanged: (val) {
                    setState(() => _dsl = _dsl.copyWith(autoCut: val));
                    _markDirty();
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('出票蜂鸣提示', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 6),
                Switch.adaptive(
                  value: _dsl.beeper,
                  activeColor: const Color(0xFF2563EB),
                  onChanged: (val) {
                    setState(() => _dsl = _dsl.copyWith(beeper: val));
                    _markDirty();
                  },
                ),
              ],
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '底部走纸留白: ${_dsl.feedLines} 行',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 130,
                  child: Slider(
                    value: _dsl.feedLines.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '${_dsl.feedLines} 行',
                    onChanged: (val) {
                      setState(
                        () => _dsl = _dsl.copyWith(feedLines: val.toInt()),
                      );
                      _markDirty();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// 区块通用空行间距调节
  Widget _buildBlockSpacingControls(Map<String, Object?> cfg) {
    final before =
        int.tryParse('${cfg['linesBefore'] ?? cfg['blankLinesBefore'] ?? 0}') ??
        0;
    final after =
        int.tryParse('${cfg['linesAfter'] ?? cfg['blankLinesAfter'] ?? 0}') ??
        0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '区块上下空行间距 (行高)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '前置空行: $before 行',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Slider(
                        value: before.toDouble().clamp(0.0, 5.0),
                        min: 0,
                        max: 5,
                        divisions: 5,
                        label: '$before 行',
                        onChanged: (val) => _updateCurrentBlockConfig(
                          'linesBefore',
                          val.toInt(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '后置空行: $after 行',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Slider(
                        value: after.toDouble().clamp(0.0, 5.0),
                        min: 0,
                        max: 5,
                        divisions: 5,
                        label: '$after 行',
                        onChanged: (val) => _updateCurrentBlockConfig(
                          'linesAfter',
                          val.toInt(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpecificBlockEditor(
    TemplateBlock block,
    Map<String, Object?> cfg,
  ) {
    switch (block.type) {
      case 'HEADER':
        final titleType = cfg['titleType']?.toString() ?? 'SHOP_NAME';
        final customTitle = cfg['customTitle']?.toString() ?? '';
        final align = cfg['align']?.toString() ?? 'CENTER';
        final size = cfg['size']?.toString() ?? 'DOUBLE';
        final bold = cfg['bold'] != false;
        final subTitle = cfg['subTitle']?.toString() ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '抬头来源与主标题',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Radio<String>(
                  value: 'SHOP_NAME',
                  groupValue: titleType,
                  onChanged: (v) => _updateCurrentBlockConfig('titleType', v),
                ),
                const Text('门店名称 (自动读取当前门店)'),
                const SizedBox(width: 20),
                Radio<String>(
                  value: 'CUSTOM',
                  groupValue: titleType,
                  onChanged: (v) => _updateCurrentBlockConfig('titleType', v),
                ),
                const Text('自定义主标题文字'),
              ],
            ),
            if (titleType == 'CUSTOM') ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '自定义主标题文案 (如: 欢迎光临老肥烧烤 / 总单结账)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      controller: TextEditingController(text: customTitle)
                        ..selection = TextSelection.collapsed(
                          offset: customTitle.length,
                        ),
                      onChanged: (v) =>
                          _updateCurrentBlockConfig('customTitle', v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: [
                  _buildInsertVariableChip(
                    '{门店名称}',
                    '店名',
                    customTitle,
                    'customTitle',
                  ),
                  _buildInsertVariableChip(
                    '{桌号}',
                    '桌号',
                    customTitle,
                    'customTitle',
                  ),
                  _buildInsertVariableChip(
                    '{加菜}',
                    '加菜',
                    customTitle,
                    'customTitle',
                  ),
                  _buildInsertVariableChip(
                    '{订单ID}',
                    '订单ID',
                    customTitle,
                    'customTitle',
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                labelText: '副标题 / 欢迎标语 (如: 堂食结账单 / 祝您就餐愉快)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: subTitle)
                ..selection = TextSelection.collapsed(offset: subTitle.length),
              onChanged: (v) => _updateCurrentBlockConfig('subTitle', v),
            ),
            const SizedBox(height: 14),
            _buildTextStyleControls(
              align: align,
              size: size,
              bold: bold,
              onAlignChanged: (v) => _updateCurrentBlockConfig('align', v),
              onSizeChanged: (v) => _updateCurrentBlockConfig('size', v),
              onBoldChanged: (v) => _updateCurrentBlockConfig('bold', v),
            ),
          ],
        );

      case 'ORDER_INFO':
        final showTable = cfg['showTableNo'] != false;
        final tableLabel = cfg['tableNoLabel']?.toString() ?? '桌台号: ';
        final tableSize = cfg['tableNoSize']?.toString() ?? 'DOUBLE';
        final showDineIn = cfg['showDineInType'] != false;
        final dineInLabel = cfg['dineInTypeLabel']?.toString() ?? '用餐方式：';
        final showOrderNo = cfg['showOrderNo'] != false;
        final orderNoLabel = cfg['orderNoLabel']?.toString() ?? '订单编号：';
        final showOrderTime = cfg['showOrderTime'] != false;
        final timeLabel = cfg['timeLabel']?.toString() ?? '下单时间：';
        final showPayTime = cfg['showPayTime'] == true;
        final payTimeLabel = cfg['payTimeLabel']?.toString() ?? '结账时间：';
        final customInfo = cfg['customInfoText']?.toString() ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '订单字段显隐与前缀标签自定义',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // 桌台号行
            Row(
              children: [
                Checkbox(
                  value: showTable,
                  onChanged: (v) => _updateCurrentBlockConfig('showTableNo', v),
                ),
                const Text('桌台号/牌号: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '前缀文本 (如: 桌号 / 台号 / 牌号)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: tableLabel)
                      ..selection = TextSelection.collapsed(
                        offset: tableLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('tableNoLabel', v),
                  ),
                ),
                const SizedBox(width: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'NORMAL', label: Text('标准')),
                    ButtonSegment(value: 'DOUBLE', label: Text('双倍')),
                  ],
                  selected: {tableSize},
                  onSelectionChanged: (s) =>
                      _updateCurrentBlockConfig('tableNoSize', s.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 用餐方式行
            Row(
              children: [
                Checkbox(
                  value: showDineIn,
                  onChanged: (v) =>
                      _updateCurrentBlockConfig('showDineInType', v),
                ),
                const Text('就餐方式: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '前缀文本 (如: 用餐方式 / 就餐类型)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: dineInLabel)
                      ..selection = TextSelection.collapsed(
                        offset: dineInLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('dineInTypeLabel', v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 订单编号行
            Row(
              children: [
                Checkbox(
                  value: showOrderNo,
                  onChanged: (v) => _updateCurrentBlockConfig('showOrderNo', v),
                ),
                const Text('订单编号: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '前缀文本 (如: 订单号 / 流水号)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: orderNoLabel)
                      ..selection = TextSelection.collapsed(
                        offset: orderNoLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('orderNoLabel', v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 下单时间行
            Row(
              children: [
                Checkbox(
                  value: showOrderTime,
                  onChanged: (v) =>
                      _updateCurrentBlockConfig('showOrderTime', v),
                ),
                const Text('下单时间: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '前缀文本 (如: 下单时间 / 开单时间)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: timeLabel)
                      ..selection = TextSelection.collapsed(
                        offset: timeLabel.length,
                      ),
                    onChanged: (v) => _updateCurrentBlockConfig('timeLabel', v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 结账时间行
            Row(
              children: [
                Checkbox(
                  value: showPayTime,
                  onChanged: (v) => _updateCurrentBlockConfig('showPayTime', v),
                ),
                const Text('结账时间: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '前缀文本 (如: 结账时间 / 支付时间)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: payTimeLabel)
                      ..selection = TextSelection.collapsed(
                        offset: payTimeLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('payTimeLabel', v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                labelText: '附加订单补充信息 (选填，支持变量如 {加菜} {订单ID} {会员卡号})',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(
                text: customInfo,
              )..selection = TextSelection.collapsed(offset: customInfo.length),
              onChanged: (v) => _updateCurrentBlockConfig('customInfoText', v),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                _buildInsertVariableChip(
                  '{加菜}',
                  '加菜',
                  customInfo,
                  'customInfoText',
                ),
                _buildInsertVariableChip(
                  '{订单ID}',
                  '订单ID',
                  customInfo,
                  'customInfoText',
                ),
                _buildInsertVariableChip(
                  '{会员卡号}',
                  '会员卡号',
                  customInfo,
                  'customInfoText',
                ),
                _buildInsertVariableChip(
                  '{备注}',
                  '整单备注',
                  customInfo,
                  'customInfoText',
                ),
              ],
            ),
          ],
        );

      case 'DISH_ITEMS':
        final showTableHead = cfg['showTableHead'] != false;
        final headerText =
            cfg['headerText']?.toString() ??
            (cfg['showUnitPrice'] != false && cfg['showTotalPrice'] != false
                ? '名称　　　　　 单价  数量  金额'
                : '名称　　　　　          数量');
        final dividerText =
            cfg['dividerText']?.toString() ??
            (_paperSize == '80mm'
                ? '------------------------------------------------'
                : '--------------------------------');
        final spicyPrioritySort = cfg['spicyPrioritySort'] == true;
        final specPosition = cfg['specPosition']?.toString() ?? 'INLINE';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('展示商品表头栏'),
              value: showTableHead,
              onChanged: (v) => _updateCurrentBlockConfig('showTableHead', v),
            ),
            if (showTableHead) ...[
              const SizedBox(height: 4),
              TextField(
                decoration: const InputDecoration(
                  labelText: '表头文字 (如: 名称　　　　　 单价  数量  金额)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: headerText)
                  ..selection = TextSelection.collapsed(
                    offset: headerText.length,
                  ),
                onChanged: (v) => _updateCurrentBlockConfig('headerText', v),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Checkbox(
                    value: cfg['showHeadDivider'] == true,
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('showHeadDivider', v),
                  ),
                  const Text('表头下方附带横向分隔线', style: TextStyle(fontSize: 12)),
                ],
              ),
              if (cfg['showHeadDivider'] == true) ...[
                const SizedBox(height: 4),
                TextField(
                  decoration: const InputDecoration(
                    labelText: '表头下分隔横线',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  controller: TextEditingController(text: dividerText)
                    ..selection = TextSelection.collapsed(
                      offset: dividerText.length,
                    ),
                  onChanged: (v) => _updateCurrentBlockConfig('dividerText', v),
                ),
              ],
              const SizedBox(height: 10),
            ],
            Wrap(
              spacing: 16,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: cfg['showUnitPrice'] != false,
                      onChanged: (v) =>
                          _updateCurrentBlockConfig('showUnitPrice', v),
                    ),
                    const Text('单价列', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: cfg['showQuantity'] != false,
                      onChanged: (v) =>
                          _updateCurrentBlockConfig('showQuantity', v),
                    ),
                    const Text('数量列', style: TextStyle(fontSize: 12)),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: cfg['showTotalPrice'] != false,
                      onChanged: (v) =>
                          _updateCurrentBlockConfig('showTotalPrice', v),
                    ),
                    const Text('金额小计列', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('按辣度等级自动排产优先排序 (适用于后厨档口)'),
              value: spicyPrioritySort,
              onChanged: (v) =>
                  _updateCurrentBlockConfig('spicyPrioritySort', v),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('规格展示位置: ', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'INLINE',
                      label: Text('行内跟随 (菜名(微辣))'),
                    ),
                    ButtonSegment(value: 'NEW_LINE', label: Text('换行独立展示')),
                  ],
                  selected: {specPosition},
                  onSelectionChanged: (s) =>
                      _updateCurrentBlockConfig('specPosition', s.first),
                ),
              ],
            ),
          ],
        );

      case 'PAYMENT_SUMMARY':
        final showOriginal = cfg['showOriginalAmount'] != false;
        final originalLabel = cfg['originalLabel']?.toString() ?? '原价合计：';
        final showDiscount = cfg['showDiscountAmount'] != false;
        final discountLabel = cfg['discountLabel']?.toString() ?? '优惠减免：-';
        final showActual = cfg['showActualAmount'] != false;
        final actualLabel = cfg['actualLabel']?.toString() ?? '实付合计：';
        final actualSize = cfg['actualAmountSize']?.toString() ?? 'DOUBLE';
        final actualBold = cfg['actualAmountBold'] != false;
        final showPayChannel = cfg['showPayChannel'] != false;
        final payChannelLabel = cfg['payChannelLabel']?.toString() ?? '支付方式：';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '结算汇总字段与自定义标签',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            // 原价行
            Row(
              children: [
                Checkbox(
                  value: showOriginal,
                  onChanged: (v) =>
                      _updateCurrentBlockConfig('showOriginalAmount', v),
                ),
                const Text('原价合计: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '原价标签 (如: 原价合计: / 商品总计: )',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: originalLabel)
                      ..selection = TextSelection.collapsed(
                        offset: originalLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('originalLabel', v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 优惠减免行
            Row(
              children: [
                Checkbox(
                  value: showDiscount,
                  onChanged: (v) =>
                      _updateCurrentBlockConfig('showDiscountAmount', v),
                ),
                const Text('优惠减免: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '优惠标签 (如: 优惠减免: - / 折扣: -)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: discountLabel)
                      ..selection = TextSelection.collapsed(
                        offset: discountLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('discountLabel', v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 实付总额行
            Row(
              children: [
                Checkbox(
                  value: showActual,
                  onChanged: (v) =>
                      _updateCurrentBlockConfig('showActualAmount', v),
                ),
                const Text('实付总额: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '实付标签 (如: 实付合计: / 应收总额: )',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: actualLabel)
                      ..selection = TextSelection.collapsed(
                        offset: actualLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('actualLabel', v),
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'NORMAL', label: Text('标准')),
                    ButtonSegment(value: 'DOUBLE', label: Text('双倍')),
                  ],
                  selected: {actualSize},
                  onSelectionChanged: (s) =>
                      _updateCurrentBlockConfig('actualAmountSize', s.first),
                ),
                const SizedBox(width: 6),
                Row(
                  children: [
                    const Text('加粗', style: TextStyle(fontSize: 12)),
                    Checkbox(
                      value: actualBold,
                      onChanged: (v) =>
                          _updateCurrentBlockConfig('actualAmountBold', v),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 支付方式行
            Row(
              children: [
                Checkbox(
                  value: showPayChannel,
                  onChanged: (v) =>
                      _updateCurrentBlockConfig('showPayChannel', v),
                ),
                const Text('支付方式: ', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: '支付方式标签 (如: 支付方式: / 结账渠道: )',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: payChannelLabel)
                      ..selection = TextSelection.collapsed(
                        offset: payChannelLabel.length,
                      ),
                    onChanged: (v) =>
                        _updateCurrentBlockConfig('payChannelLabel', v),
                  ),
                ),
              ],
            ),
          ],
        );

      case 'MEMBER_INFO':
        final label = cfg['label']?.toString() ?? '会员卡号：VIP-';
        final customNotice = cfg['customNotice']?.toString() ?? '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '会员信息展示与营销提示',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextField(
              decoration: const InputDecoration(
                labelText: '会员卡号前缀 (如: 会员卡号: / 尊贵会员: )',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: label)
                ..selection = TextSelection.collapsed(offset: label.length),
              onChanged: (v) => _updateCurrentBlockConfig('label', v),
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                labelText: '会员积分/储值自定义提示 (如: 积分可抵扣现金，欢迎充值)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: customNotice)
                ..selection = TextSelection.collapsed(
                  offset: customNotice.length,
                ),
              onChanged: (v) => _updateCurrentBlockConfig('customNotice', v),
            ),
          ],
        );

      case 'DELIVERY_INFO':
        final showName = cfg['showReceiverName'] != false;
        final showPhone = cfg['showReceiverPhone'] != false;
        final showAddress = cfg['showDeliveryAddress'] != false;
        final showExpectedTime = cfg['showExpectedTime'] != false;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '外卖配送信息展示项',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('展示收货人姓名'),
              value: showName,
              onChanged: (v) =>
                  _updateCurrentBlockConfig('showReceiverName', v),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('展示收货人联系电话'),
              value: showPhone,
              onChanged: (v) =>
                  _updateCurrentBlockConfig('showReceiverPhone', v),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('展示完整配送地址 (大字醒目)'),
              value: showAddress,
              onChanged: (v) =>
                  _updateCurrentBlockConfig('showDeliveryAddress', v),
            ),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('展示期望送达时间'),
              value: showExpectedTime,
              onChanged: (v) =>
                  _updateCurrentBlockConfig('showExpectedTime', v),
            ),
          ],
        );

      case 'REMARK':
        final label = cfg['label']?.toString() ?? '整单备注：';
        final size = cfg['size']?.toString() ?? 'NORMAL';
        final bold = cfg['bold'] != false;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: '备注前缀标签 (如: 顾客备注: / 制作要求: / 【特别交代】)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: label)
                ..selection = TextSelection.collapsed(offset: label.length),
              onChanged: (v) => _updateCurrentBlockConfig('label', v),
            ),
            const SizedBox(height: 12),
            _buildTextStyleControls(
              align: 'LEFT',
              size: size,
              bold: bold,
              showAlign: false,
              onSizeChanged: (v) => _updateCurrentBlockConfig('size', v),
              onBoldChanged: (v) => _updateCurrentBlockConfig('bold', v),
            ),
          ],
        );

      case 'CUSTOM_TEXT':
        final content = cfg['content']?.toString() ?? '';
        final align = cfg['align']?.toString() ?? 'CENTER';
        final size = cfg['size']?.toString() ?? 'NORMAL';
        final bold = cfg['bold'] == true;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '文本内容 (支持变量与换行)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    _buildInsertVariableChip(
                      '{门店名称}',
                      '店名',
                      content,
                      'content',
                    ),
                    _buildInsertVariableChip('{桌号}', '桌号', content, 'content'),
                    _buildInsertVariableChip('{加菜}', '加菜', content, 'content'),
                    _buildInsertVariableChip(
                      '{订单ID}',
                      '订单ID',
                      content,
                      'content',
                    ),
                    _buildInsertVariableChip('{订单号}', '单号', content, 'content'),
                    _buildInsertVariableChip(
                      '{下单时间}',
                      '时间',
                      content,
                      'content',
                    ),
                    _buildInsertVariableChip('{实付}', '实付', content, 'content'),
                    _buildInsertVariableChip(
                      '{会员卡号}',
                      '会员',
                      content,
                      'content',
                    ),
                    _buildInsertVariableChip('{备注}', '备注', content, 'content'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    '输入自定义文本，支持多行与变量插值，如：\nWiFi名称: LaoFei / 密码: 88888888\n如有任何就餐问题请联系大堂经理',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: content)
                ..selection = TextSelection.collapsed(offset: content.length),
              onChanged: (v) => _updateCurrentBlockConfig('content', v),
            ),
            const SizedBox(height: 12),
            _buildTextStyleControls(
              align: align,
              size: size,
              bold: bold,
              onAlignChanged: (v) => _updateCurrentBlockConfig('align', v),
              onSizeChanged: (v) => _updateCurrentBlockConfig('size', v),
              onBoldChanged: (v) => _updateCurrentBlockConfig('bold', v),
            ),
          ],
        );

      case 'DIVIDER':
        final ch = cfg['char']?.toString() ?? '-';
        final rawLen = cfg['length'];
        final length = rawLen is num
            ? rawLen.toInt()
            : (int.tryParse('$rawLen') ?? (_paperSize == '80mm' ? 48 : 32));
        final text = cfg['text']?.toString() ?? '';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '下划线/分割线样式与长度调节',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('线型样式: ', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 8),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: '-', label: Text('虚线 -')),
                    ButtonSegment(value: '=', label: Text('双线 =')),
                    ButtonSegment(value: '*', label: Text('星号 *')),
                    ButtonSegment(value: '.', label: Text('点线 .')),
                    ButtonSegment(value: '─', label: Text('实线 ─')),
                    ButtonSegment(value: '~', label: Text('波浪 ~')),
                  ],
                  selected: {ch},
                  onSelectionChanged: (s) {
                    final newCh = s.first;
                    final generatedText = List.filled(length, newCh).join();
                    _updateCurrentBlockConfig('char', newCh);
                    _updateCurrentBlockConfig('text', generatedText);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '分割线长度 (字符数): $length 列',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Slider(
                    value: length.toDouble().clamp(8.0, 64.0),
                    min: 8,
                    max: 64,
                    divisions: 56,
                    label: '$length 列',
                    onChanged: (val) {
                      final newLen = val.toInt();
                      final generatedText = List.filled(newLen, ch).join();
                      _updateCurrentBlockConfig('length', newLen);
                      _updateCurrentBlockConfig('text', generatedText);
                    },
                  ),
                ),
                // 快捷填充按钮
                Wrap(
                  spacing: 4,
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        final generatedText = List.filled(32, ch).join();
                        _updateCurrentBlockConfig('length', 32);
                        _updateCurrentBlockConfig('text', generatedText);
                      },
                      child: const Text(
                        '58mm(32)',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        final generatedText = List.filled(48, ch).join();
                        _updateCurrentBlockConfig('length', 48);
                        _updateCurrentBlockConfig('text', generatedText);
                      },
                      child: const Text(
                        '80mm(48)',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                      ),
                      onPressed: () {
                        final generatedText = List.filled(16, ch).join();
                        _updateCurrentBlockConfig('length', 16);
                        _updateCurrentBlockConfig('text', generatedText);
                      },
                      child: const Text(
                        '短分隔(16)',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(
                labelText: '完全自定义分割横线内容 (可输入居中文本，如: -------- 菜品明细 --------)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: text)
                ..selection = TextSelection.collapsed(offset: text.length),
              onChanged: (v) => _updateCurrentBlockConfig('text', v),
            ),
          ],
        );

      case 'SPACING':
        final lines = int.tryParse('${cfg['lines'] ?? 1}') ?? 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '空白间距行设置',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('空白行数: $lines 行', style: const TextStyle(fontSize: 13)),
                const SizedBox(width: 12),
                Expanded(
                  child: Slider(
                    value: lines.toDouble().clamp(1.0, 10.0),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '$lines 行',
                    onChanged: (val) =>
                        _updateCurrentBlockConfig('lines', val.toInt()),
                  ),
                ),
              ],
            ),
          ],
        );

      case 'QRCODE':
      case 'FOOTER':
        final thankText = cfg['thankText']?.toString() ?? '感谢惠顾 欢迎再次光临';
        final noticeText = cfg['noticeText']?.toString() ?? '';
        final showQr = cfg['showQrCode'] != false;
        final qrUrl =
            cfg['qrCodeUrl']?.toString() ??
            'https://u.wechat.com/EF9MZwaAbHhL79QCtBgAVAA?s=2';
        final qrNote = cfg['qrCodeNote']?.toString() ?? '扫码开票 / 意见反馈';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              decoration: const InputDecoration(
                labelText: '页脚致谢标语 (如: 感谢惠顾 欢迎再次光临)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: thankText)
                ..selection = TextSelection.collapsed(offset: thankText.length),
              onChanged: (v) => _updateCurrentBlockConfig('thankText', v),
            ),
            const SizedBox(height: 10),
            TextField(
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: '店招公告 / WiFi密码 / 客服热线 (选填)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(
                text: noticeText,
              )..selection = TextSelection.collapsed(offset: noticeText.length),
              onChanged: (v) => _updateCurrentBlockConfig('noticeText', v),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('打印二维码（公众号 / 客服微信 / 开票 / 评价）'),
              value: showQr,
              onChanged: (v) => _updateCurrentBlockConfig('showQrCode', v),
            ),
            if (showQr) ...[
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                  labelText: '二维码解析内容 / 跳转 URL',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: qrUrl)
                  ..selection = TextSelection.collapsed(offset: qrUrl.length),
                onChanged: (v) => _updateCurrentBlockConfig('qrCodeUrl', v),
              ),
              const SizedBox(height: 10),
              TextField(
                decoration: const InputDecoration(
                  labelText: '二维码下方引导文字',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                controller: TextEditingController(text: qrNote)
                  ..selection = TextSelection.collapsed(offset: qrNote.length),
                onChanged: (v) => _updateCurrentBlockConfig('qrCodeNote', v),
              ),
            ],
          ],
        );

      default:
        return const Text('系统内置区块，支持调整上下空行间距与显隐控制。');
    }
  }

  Widget _buildInsertVariableChip(
    String tag,
    String label,
    String currentContent, [
    String configKey = 'content',
  ]) {
    return InkWell(
      onTap: () {
        final newContent = currentContent.isEmpty
            ? tag
            : '$currentContent $tag';
        _updateCurrentBlockConfig(configKey, newContent);
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Text(
          '+$label',
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF1D4ED8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildTextStyleControls({
    String align = 'LEFT',
    String size = 'NORMAL',
    bool bold = false,
    bool showAlign = true,
    ValueChanged<String>? onAlignChanged,
    ValueChanged<String>? onSizeChanged,
    ValueChanged<bool>? onBoldChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showAlign && onAlignChanged != null) ...[
          const Text(
            '文字对齐',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'LEFT', label: Text('居左')),
              ButtonSegment(value: 'CENTER', label: Text('居中')),
              ButtonSegment(value: 'RIGHT', label: Text('居右')),
            ],
            selected: {align},
            onSelectionChanged: (s) => onAlignChanged(s.first),
          ),
          const SizedBox(height: 12),
        ],
        if (onSizeChanged != null) ...[
          const Text(
            '字号大小',
            style: TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 4),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'NORMAL', label: Text('标准')),
              ButtonSegment(value: 'LARGE', label: Text('放大')),
              ButtonSegment(value: 'DOUBLE', label: Text('双倍宽高')),
            ],
            selected: {size},
            onSelectionChanged: (s) => onSizeChanged(s.first),
          ),
          const SizedBox(height: 12),
        ],
        if (onBoldChanged != null) ...[
          Row(
            children: [
              const Text('文本加粗: ', style: TextStyle(fontSize: 13)),
              Checkbox(
                value: bold,
                onChanged: (v) => onBoldChanged(v ?? false),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLivePaperPreviewPanel() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.print_rounded,
                    color: Color(0xFF38BDF8),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '真实热敏小票预览 ($_paperSize)',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: _scenario == 'TEST'
                        ? '测试场景不支持精确预览'
                        : '精确预览（真实订单/班次）',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 24,
                      height: 24,
                    ),
                    onPressed: _scenario == 'TEST'
                        ? null
                        : () => showCashierExactPrintPreviewDialog(
                            context: context,
                            repository: widget.repository,
                            scenario: _scenario,
                          ),
                    icon: const Icon(
                      Icons.fact_check_outlined,
                      size: 16,
                      color: Color(0xFF7DD3FC),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (_previewLoading)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF38BDF8),
                      ),
                    )
                  else
                    InkWell(
                      onTap: _fetchLivePreview,
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 13,
                            color: Color(0xFF94A3B8),
                          ),
                          SizedBox(width: 2),
                          Text(
                            '刷新',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 真实热敏纸模拟器纸卷
          Expanded(
            child: Container(
              alignment: Alignment.topCenter,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: _previewError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '预览生成异常: $_previewError',
                          style: const TextStyle(
                            color: Color(0xFFF87171),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 8,
                      ),
                      child:
                          _previewResult != null &&
                              _previewResult!.tickets.isNotEmpty
                          ? ThermalPaperSimulator(
                              ticket: _previewResult!.tickets.first,
                              is80mm: _paperSize == '80mm',
                            )
                          : const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Text(
                                  '正在生成真实小票排版预览...',
                                  style: TextStyle(color: Color(0xFF94A3B8)),
                                ),
                              ),
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconForBlock(String type) {
    switch (type) {
      case 'HEADER':
        return Icons.title_rounded;
      case 'ORDER_INFO':
        return Icons.receipt_outlined;
      case 'DISH_ITEMS':
        return Icons.restaurant_menu_rounded;
      case 'PAYMENT_SUMMARY':
        return Icons.payments_outlined;
      case 'MEMBER_INFO':
        return Icons.card_membership_rounded;
      case 'DELIVERY_INFO':
        return Icons.delivery_dining_outlined;
      case 'REMARK':
        return Icons.speaker_notes_outlined;
      case 'CUSTOM_TEXT':
        return Icons.text_fields_rounded;
      case 'DIVIDER':
        return Icons.horizontal_rule_rounded;
      case 'SPACING':
        return Icons.format_line_spacing_rounded;
      case 'QRCODE':
        return Icons.qr_code_2_rounded;
      case 'FOOTER':
        return Icons.web_stories_outlined;
      default:
        return Icons.widgets_outlined;
    }
  }
}
