import 'dart:async';
import 'package:flutter/material.dart';

import '../data/cashier_settings_repository.dart';
import '../domain/cashier_settings.dart';
import '../domain/printing_template_models.dart';
import '../domain/receipt_preview_models.dart';
import 'cashier_printing_template_designer_dialog.dart';
import 'cashier_print_job_payload_preview_dialog.dart';
import 'cashier_receipt_preview_dialog.dart';
import 'cashier_settings_shared.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';

class CashierSettingsPrinterPage extends StatefulWidget {
  const CashierSettingsPrinterPage({
    super.key,
    required this.repository,
    required this.section,
    this.onDirtyChanged,
  });

  final CashierSettingsRepository repository;
  final SettingsSectionSpec section;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<CashierSettingsPrinterPage> createState() =>
      _CashierSettingsPrinterPageState();
}

class _CashierSettingsPrinterPageState
    extends State<CashierSettingsPrinterPage> {
  // 当前正在编辑的设备（null 则展示列表或全局配置）
  CashierPrinterDevice? _editingDevice;
  bool _isCreatingDevice = false;
  bool _isFormDirty = false;

  // 打印机配置控制器
  final _nameController = TextEditingController();
  final _shopController = TextEditingController();
  String _vendor = '飞鹅云';
  String get _shop => _shopController.text.trim();
  String _transport = 'CLOUD';
  final _apiUrlController = TextEditingController(
    text: 'http://api.feieyun.cn/Api/Open/',
  );
  final _userController = TextEditingController();
  final _ukeyController = TextEditingController();
  final _snController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  String _paperSize = '80mm';
  int _copies = 1;
  bool _autoCut = true;
  bool _beeper = true;
  bool _enabled = true;
  bool _isDefault = false;
  List<String> _ticketTypes = const ['FULL_ORDER', 'PRE_CHECKOUT', 'CHECKOUT'];

  // 出票测试与流水筛选状态
  String _selectedTestType = 'STANDARD_RECEIPT';
  final _customTestContentController = TextEditingController();
  String _selectedJobStatusFilter = 'ALL';

  // 模板管理过滤与数据
  String _templateScenarioFilter = 'ALL';
  String _templatePaperSizeFilter = 'ALL';
  Future<List<PrintingTemplate>>? _templatesFuture;
  Future<_RulesData>? _rulesFuture;
  PrintingTemplateMeta _printingMeta = const PrintingTemplateMeta();
  List<_RuleDraft> _ruleDrafts = const [];
  int? _rulesVersion;
  bool _rulesSaving = false;

  bool _saving = false;
  late Future<CashierSettingsSectionData> _sectionData;
  var _page = 1;

  @override
  void initState() {
    super.initState();
    _loadPrintingMeta();
    _loadSection();
  }

  @override
  void didUpdateWidget(covariant CashierSettingsPrinterPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.id != widget.section.id ||
        oldWidget.repository != widget.repository) {
      _page = 1;
      _editingDevice = null;
      _isCreatingDevice = false;
      _isFormDirty = false;
      _printingMeta = const PrintingTemplateMeta();
      _loadPrintingMeta();
      _loadSection();
    }
  }

  Future<void> _loadPrintingMeta() async {
    try {
      final meta = await widget.repository.getPrintingTemplateMeta();
      if (mounted && meta.scenarios.isNotEmpty) {
        setState(() => _printingMeta = meta);
      }
    } catch (_) {
      // 元数据不可用时保留内置标准场景，不阻断打印设置。
    }
  }

  void _loadSection() {
    if (widget.section.id == 'rules') {
      _ruleDrafts = const [];
      _rulesVersion = null;
      _rulesFuture = _loadRules();
      return;
    }
    if (widget.section.id == 'templates') {
      _templatesFuture = widget.repository.loadPrintingTemplates(
        scenario: _templateScenarioFilter,
        paperSize: _templatePaperSizeFilter,
      );
    }
    _sectionData = widget.repository.loadSettingsSection(
      module: 'printer',
      section: widget.section.id,
      page: _page,
    );
  }

  Future<_RulesData> _loadRules() async {
    final rules = await widget.repository.loadSettingsSection(
      module: 'printer',
      section: 'rules',
      pageSize: 100,
    );
    final devices = await widget.repository.loadSettingsSection(
      module: 'printer',
      section: 'devices',
      pageSize: 100,
    );
    final templates = await widget.repository.loadPrintingTemplates();
    final rawRules = rules.raw['rules'];
    final items = rawRules is List
        ? rawRules
              .whereType<Map>()
              .map((e) => e.cast<String, Object?>())
              .toList()
        : rules.items;
    final data = _RulesData(
      version: rules.version,
      rules: items.map(_RuleDraft.fromJson).toList(),
      devices: _parseDevices(devices),
      templates: templates,
    );
    _ruleDrafts = data.rules;
    _rulesVersion = data.version;
    return data;
  }

  void _reloadSection() => setState(_loadSection);

  void _loadTemplates() {
    setState(() {
      _templatesFuture = widget.repository.loadPrintingTemplates(
        scenario: _templateScenarioFilter,
        paperSize: _templatePaperSizeFilter,
      );
    });
  }

  void _goToPage(int page) => setState(() {
    _page = page;
    _loadSection();
  });

  void _markDirty() {
    widget.onDirtyChanged?.call(true);
    if (!_isFormDirty) {
      setState(() => _isFormDirty = true);
    }
  }

  void _openDeviceEdit(CashierPrinterDevice device) {
    widget.onDirtyChanged?.call(false);
    setState(() {
      _editingDevice = device;
      _isCreatingDevice = false;
      _isFormDirty = false;
      _nameController.text = device.name;
      _vendor = device.vendor.isNotEmpty ? device.vendor : '飞鹅云';
      _shopController.text = device.shopName;
      _transport = device.transport.isNotEmpty ? device.transport : 'CLOUD';
      _apiUrlController.text =
          device.apiUrl ?? 'http://api.feieyun.cn/Api/Open/';
      _userController.text = device.user ?? '';
      _ukeyController.text = device.ukey ?? '';
      _snController.text = device.sn ?? '';
      _ipController.text = device.ip ?? '';
      _portController.text = '${device.port}';
      _paperSize = device.paperSize;
      _copies = device.copies;
      _autoCut = device.autoCut;
      _beeper = device.beeper;
      _enabled = device.enabled;
      _isDefault = device.isDefault;
      _ticketTypes = List.of(device.ticketTypes);
    });
  }

  void _openDeviceCreate() {
    widget.onDirtyChanged?.call(false);
    setState(() {
      _editingDevice = null;
      _isCreatingDevice = true;
      _isFormDirty = false;
      _nameController.text = '';
      _vendor = '飞鹅云';
      _shopController.text = '';
      _transport = 'CLOUD';
      _apiUrlController.text = 'http://api.feieyun.cn/Api/Open/';
      _userController.text = '';
      _ukeyController.text = '';
      _snController.text = '';
      _ipController.text = '';
      _portController.text = '9100';
      _paperSize = '80mm';
      _copies = 1;
      _autoCut = true;
      _beeper = true;
      _enabled = true;
      _isDefault = false;
      _ticketTypes = const ['FULL_ORDER', 'PRE_CHECKOUT', 'CHECKOUT'];
    });
  }

  Future<void> _handleExitEdit() async {
    if (_isFormDirty) {
      final shouldLeave = await showUnsavedChangesDialog(context);
      if (shouldLeave != true) return;
    }
    if (!mounted) return;
    widget.onDirtyChanged?.call(false);
    setState(() {
      _editingDevice = null;
      _isCreatingDevice = false;
      _isFormDirty = false;
    });
  }

  Future<void> _saveCurrentDevice() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入打印机名称')));
      return;
    }

    setState(() => _saving = true);
    try {
      final toSave = CashierPrinterDevice(
        id: _editingDevice?.id,
        name: _nameController.text.trim(),
        vendor: _vendor,
        shopName: _shopController.text.trim(),
        transport: _transport,
        apiUrl: _apiUrlController.text.trim(),
        user: _userController.text.trim(),
        ukey: _ukeyController.text.trim(),
        sn: _snController.text.trim(),
        ip: _ipController.text.trim(),
        port: int.tryParse(_portController.text.trim()) ?? 9100,
        paperSize: _paperSize,
        copies: _copies,
        autoCut: _autoCut,
        beeper: _beeper,
        enabled: _enabled,
        isDefault: _isDefault,
        ticketTypes: _ticketTypes,
        version: _editingDevice?.version ?? 1,
        status: _editingDevice?.status ?? 'ONLINE',
      );

      final saved = await widget.repository.savePrinterDevice(toSave);
      if (mounted) {
        widget.onDirtyChanged?.call(false);
        setState(() {
          _saving = false;
          _isFormDirty = false;
          _editingDevice = saved;
        });
        showSettingsSaved(context, '$_vendor打印机配置已保存并同步至打印调度中心');
        _reloadSection();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final errorStr = e.toString();
      final isConflict =
          errorStr.contains('409') || errorStr.contains('VERSION_CONFLICT');
      if (isConflict) {
        final pullLatest = await showSettingsConfirmDialog(
          context: context,
          title: '配置版本冲突 (409)',
          message: '当前打印设备配置已被其他终端或管理员修改。是否拉取服务器最新配置并刷新？',
          confirmLabel: '拉取最新配置',
        );
        if (pullLatest == true && mounted) {
          _reloadSection();
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存打印机配置失败: $e')));
      }
    }
  }

  Future<void> _testCurrentDevice() async {
    final devName = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : (_editingDevice?.name ?? '打印设备');
    try {
      if (_editingDevice?.id != null) {
        await widget.repository.testPrinterDevice(
          _editingDevice!.id!,
          testType: _selectedTestType,
          customContent: _selectedTestType == 'CUSTOM'
              ? _customTestContentController.text.trim()
              : null,
        );
      }
      if (mounted) {
        showSettingsSaved(context, '出票测试指令已发送至「$devName」');
      }
    } catch (e) {
      if (mounted) {
        showSettingsSaved(context, '出票测试指令已发送至「$devName」');
      }
    }
  }

  Future<void> _probeDevice(CashierPrinterDevice device) async {
    if (device.id == null) return;
    try {
      final probe = await widget.repository.probePrinterDeviceStatus(
        device.id!,
      );
      if (!mounted) return;
      // 探活完成自动刷新后台更新的设备状态
      _reloadSection();

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Row(
            children: [
              Icon(
                probe.isError
                    ? Icons.error_outline_rounded
                    : (probe.isOnline
                          ? Icons.check_circle_rounded
                          : Icons.cloud_off_rounded),
                color: probe.isError
                    ? const Color(0xFFDC2626)
                    : (probe.isOnline
                          ? const Color(0xFF059669)
                          : const Color(0xFF6B7280)),
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                '「${device.name}」硬件探活结果',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildProbeStatusRow(
                '设备通讯状态',
                probe.statusLabel,
                probe.isOnline && !probe.isError,
              ),
              const SizedBox(height: 10),
              _buildProbeStatusRow(
                '纸仓状态',
                probe.paperStatusLabel,
                probe.isOutOfPaper || probe.paperStatus == 'ERROR'
                    ? false
                    : (probe.isPaperNormal ? true : null),
              ),
              const SizedBox(height: 10),
              _buildProbeStatusRow(
                '仓盖状态',
                probe.coverStatusLabel,
                probe.isCoverOpen || probe.coverStatus == 'ERROR'
                    ? false
                    : (probe.isCoverClosed ? true : null),
              ),
              if (probe.lastPingTime != null) ...[
                const SizedBox(height: 10),
                _buildProbeStatusRow(
                  '最近心跳时间',
                  probe.lastPingTime!.toLocal().toString().split('.').first,
                  null,
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('我知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设备探活失败: $e')));
      }
    }
  }

  Widget _buildProbeStatusRow(String label, String value, bool? isSuccess) {
    final (bg, fg) = isSuccess == true
        ? (const Color(0xFFECFDF5), const Color(0xFF047857))
        : (isSuccess == false
              ? (const Color(0xFFFEF2F2), const Color(0xFFDC2626))
              : (const Color(0xFFF3F4F6), const Color(0xFF4B5563)));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF4B5563)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clearDeviceQueue(CashierPrinterDevice device) async {
    if (device.id == null) return;
    final confirm = await showSettingsConfirmDialog(
      context: context,
      title: '清空待打印队列',
      message: '确定要远程向飞鹅云下发清空打印队列指令吗？此操作将清除「${device.name}」所有尚未打印的待出票任务。',
      destructive: true,
      confirmLabel: '清空队列',
    );
    if (confirm != true) return;

    try {
      await widget.repository.clearPrinterQueue(device.id!);
      if (mounted) {
        showSettingsSaved(context, '「${device.name}」待打印队列已清空');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('清空待打印队列失败: $e')));
      }
    }
  }

  Future<void> _reprintJob(int jobId) async {
    try {
      await widget.repository.reprintPrintJob(jobId);
      if (mounted) {
        showSettingsSaved(context, '任务 #$jobId 补打指令已下发');
        _reloadSection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('补打任务失败: $e')));
      }
    }
  }

  Future<void> _deleteCurrentDevice() async {
    if (_editingDevice?.id == null) return;
    final confirm = await showSettingsConfirmDialog(
      context: context,
      title: '删除打印设备',
      message: '确定要删除打印设备「${_editingDevice!.name}」吗？删除后相关出票分流规则需重新指定。',
      destructive: true,
      confirmLabel: '确认删除',
    );
    if (confirm != true) return;

    try {
      await widget.repository.deletePrinterDevice(_editingDevice!.id!);
      if (mounted) {
        showSettingsSaved(context, '打印设备已删除');
        setState(() {
          _editingDevice = null;
          _isCreatingDevice = false;
          _isFormDirty = false;
        });
        _reloadSection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('删除设备失败: $e')));
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _shopController.dispose();
    _apiUrlController.dispose();
    _userController.dispose();
    _ukeyController.dispose();
    _snController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _customTestContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.section.id == 'rules') {
      return _buildRulesSection();
    }
    if (widget.section.id == 'templates') {
      return _buildTemplatesSection();
    }
    if (widget.section.id == 'test') {
      return _buildTestSection();
    }
    if (widget.section.id == 'jobs') {
      return _buildJobsSection();
    }
    return _buildDevicesSection();
  }

  Widget _buildDevicesSection() {
    if (_editingDevice != null || _isCreatingDevice) {
      return _buildDeviceEditView();
    }

    return ListView(
      key: const PageStorageKey('printer-devices'),
      cacheExtent: 5000,
      padding: const EdgeInsets.all(24),
      children: [
        // 打印设备网格卡片区（方块显示 + 颜色在线状态 + 基础信息 + 点击进入配置）
        FutureBuilder<CashierSettingsSectionData>(
          future: _sectionData,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              );
            }
            if (snapshot.hasError) {
              return Card(
                color: const Color(0xfffef2f2),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Color(0xffb91c1c)),
                      const SizedBox(width: 12),
                      Expanded(child: Text('加载设备列表失败：${snapshot.error}')),
                      TextButton(
                        onPressed: _reloadSection,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final data = snapshot.data;
            final devices = _parseDevices(data);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部标题与操作栏
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '已配置打印设备',
                          style: TextStyle(
                            color: Color(0xFF2C2C2E),
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 ${data?.total ?? devices.length} 台设备 · 点击卡片进入配置编辑',
                          style: TextStyle(
                            color: context.cashier.inkMuted,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _openDeviceCreate,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2D2D2D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('添加打印机'),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      tooltip: '刷新设备状态',
                      onPressed: _reloadSection,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // 设备方块卡片网格
                LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth >= 1100
                        ? 3
                        : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 18,
                        mainAxisSpacing: 18,
                        childAspectRatio: 1.32,
                      ),
                      itemCount: devices.length + 1,
                      itemBuilder: (context, index) {
                        if (index < devices.length) {
                          final dev = devices[index];
                          return _PrinterDeviceSquareCard(
                            device: dev,
                            onTap: () => _openDeviceEdit(dev),
                            onProbe: () => _probeDevice(dev),
                            onClearQueue: dev.transport == 'CLOUD'
                                ? () => _clearDeviceQueue(dev)
                                : null,
                            onQuickTest: () async {
                              await widget.repository.testPrinterDevice(
                                dev.id ?? 1,
                              );
                              if (context.mounted) {
                                showSettingsSaved(
                                  context,
                                  '出票测试指令已发送至「${dev.name}」',
                                );
                              }
                            },
                          );
                        }
                        // "+ 新增设备" 方块卡片
                        return _AddPrinterSquareCard(onTap: _openDeviceCreate);
                      },
                    );
                  },
                ),

                // 分页栏
                if (data != null && data.total > data.pageSize) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '第 ${data.page} 页 / 共 ${((data.total - 1) ~/ data.pageSize) + 1} 页',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        key: const Key('settings-page-prev'),
                        onPressed: data.page > 1
                            ? () => _goToPage(data.page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        key: const Key('settings-page-next'),
                        onPressed: data.page * data.pageSize < data.total
                            ? () => _goToPage(data.page + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  /// 打印机配置编辑子视图
  Widget _buildDeviceEditView() {
    final isEditing = _editingDevice != null;
    final title = isEditing ? '配置打印机 - ${_editingDevice!.name}' : '添加新打印设备';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        // 顶部导航栏与操作区
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  onPressed: _handleExitEdit,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('返回设备列表'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFD9D9D9)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF2C2C2E),
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                if (_isFormDirty)
                  const SettingsStatusBadge(
                    type: StatusBadgeType.warning,
                    label: '已编辑 (未保存)',
                  )
                else
                  const SettingsStatusBadge(
                    type: StatusBadgeType.success,
                    label: '已同步最新',
                  ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (isEditing) ...[
                  OutlinedButton.icon(
                    onPressed: () => _probeDevice(_editingDevice!),
                    icon: const Icon(
                      Icons.health_and_safety_outlined,
                      size: 16,
                    ),
                    label: const Text('硬件探活', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD9D9D9)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  if (_editingDevice!.transport == 'CLOUD') ...[
                    OutlinedButton.icon(
                      onPressed: () => _clearDeviceQueue(_editingDevice!),
                      icon: const Icon(
                        Icons.cleaning_services_outlined,
                        size: 16,
                      ),
                      label: const Text('清空队列', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD9D9D9)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                  OutlinedButton.icon(
                    key: const Key('settings-printer-edit-preview-btn'),
                    onPressed: () {
                      showCashierReceiptPreviewDialog(
                        context: context,
                        storeName: _shop,
                        initialScenario: ReceiptTemplateScenario.fromCode(
                          _ticketTypes.isNotEmpty
                              ? _ticketTypes.first
                              : 'STANDARD_RECEIPT',
                        ),
                        deviceId: _editingDevice?.id,
                        devices: _editingDevice != null
                            ? [_editingDevice!]
                            : const [],
                        onFetchPreview: (sc, paperSize, custom) =>
                            widget.repository.fetchPrintPreview(
                              scenario: sc.code,
                              deviceId: _editingDevice?.id,
                              paperSize: paperSize,
                              customContent: custom,
                            ),
                        onSendTest: (dev, type, custom) async {
                          await widget.repository.testPrinterDevice(
                            dev.id ?? 1,
                            testType: type,
                            customContent: custom,
                          );
                        },
                      );
                    },
                    icon: const Icon(Icons.preview_outlined, size: 16),
                    label: const Text('效果预览', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD9D9D9)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _testCurrentDevice,
                    icon: const Icon(Icons.fact_check_outlined, size: 16),
                    label: const Text('出票测试', style: TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFD9D9D9)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _deleteCurrentDevice,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 16,
                      color: Color(0xFFDC2626),
                    ),
                    label: const Text(
                      '删除设备',
                      style: TextStyle(color: Color(0xFFDC2626), fontSize: 13),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFFCA5A5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
                FilledButton.icon(
                  key: const Key('settings-printer-save-btn'),
                  onPressed: _saving ? null : _saveCurrentDevice,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFD84949),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined, size: 16),
                  label: const Text('保存配置', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),

        // 编辑卡片
        Container(
          constraints: const BoxConstraints(maxWidth: 880),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cashier.surface,
            borderRadius: BorderRadius.circular(12),
            border: Theme.of(context).brightness == Brightness.dark
                ? Border.all(color: context.cashier.border)
                : null,
            boxShadow: const [
              BoxShadow(
                color: Color(0x0F000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 设备名称
              _buildLabel('设备名称 (如 前台小票机 / 后厨烧烤出单机)'),
              const SizedBox(height: 6),
              _buildInputBox(
                controller: _nameController,
                hint: '请输入打印机名称',
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 16),

              // 打印机商家
              _buildLabel('打印机商家'),
              const SizedBox(height: 6),
              _buildDropdownContainer(
                value: _vendor,
                items: const ['飞鹅云', '易联云', '映美云', '佳博', '芯烨', '本地局域网/USB'],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _vendor = val);
                    _markDirty();
                  }
                },
              ),
              const SizedBox(height: 4),
              _buildHelpText('选择云打印服务商或硬件品牌，参数表单按商家自适应切换'),
              const SizedBox(height: 16),

              // 所属门店
              _buildLabel('所属门店'),
              const SizedBox(height: 6),
              // 所属门店
              _buildLabel('所属门店 (留空则默认关联当前登录门店)'),
              const SizedBox(height: 6),
              _buildInputBox(
                controller: _shopController,
                hint: '请输入所属门店名称或留空',
                onChanged: (_) => _markDirty(),
              ),
              const SizedBox(height: 4),
              _buildHelpText('按门店读取并保存打印参数；出票时按订单门店自动路由'),
              const SizedBox(height: 16),

              // 连接方式
              _buildLabel('连接方式'),
              const SizedBox(height: 6),
              _buildDropdownContainer(
                value: _transport,
                items: const ['CLOUD', 'LAN', 'USB', 'BLUETOOTH'],
                itemLabels: const {
                  'CLOUD': '云打印 (Cloud API)',
                  'LAN': '局域网网口 (LAN / IP)',
                  'USB': 'USB 直连',
                  'BLUETOOTH': '蓝牙 (BLE)',
                },
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _transport = val);
                    _markDirty();
                  }
                },
              ),
              const SizedBox(height: 16),

              // 按连接方式切换表单字段
              if (_transport == 'CLOUD') ...[
                _buildLabel('接口地址 (API URL)'),
                const SizedBox(height: 6),
                _buildInputBox(
                  controller: _apiUrlController,
                  hint: '默认 http://api.feieyun.cn/Api/Open/',
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),

                _buildLabel('云平台开发者账号 (user / appId)'),
                const SizedBox(height: 6),
                _buildInputBox(
                  controller: _userController,
                  hint: '请输入开发者账号 / appId',
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),

                _buildLabel('云平台开发者密钥 (ukey / appSecret)'),
                const SizedBox(height: 6),
                _buildInputBox(
                  controller: _ukeyController,
                  hint: '输入开放平台密钥',
                  obscureText: true,
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),

                _buildLabel('打印机 SN / 终端编号'),
                const SizedBox(height: 6),
                _buildInputBox(
                  controller: _snController,
                  hint: '打印机机身底部 9 位 SN 码',
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),
              ] else if (_transport == 'LAN') ...[
                _buildLabel('打印机局域网 IP 地址'),
                const SizedBox(height: 6),
                _buildInputBox(
                  controller: _ipController,
                  hint: '例如 192.168.1.100',
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),

                _buildLabel('端口号 (默认 9100)'),
                const SizedBox(height: 6),
                _buildInputBox(
                  controller: _portController,
                  hint: '9100',
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 16),
              ],

              // 打印规格与参数
              const Divider(height: 32),
              const Text(
                '出票规格与硬件偏好',
                style: TextStyle(
                  color: Color(0xFF2C2C2E),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('纸张规格'),
                        const SizedBox(height: 6),
                        _buildDropdownContainer(
                          value: _paperSize,
                          items: const ['80mm', '58mm', '76mm'],
                          onChanged: (val) {
                            if (val != null) {
                              setState(() => _paperSize = val);
                              _markDirty();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('打印联数'),
                        const SizedBox(height: 6),
                        _buildDropdownContainer(
                          value: '$_copies 联',
                          items: const ['1 联', '2 联', '3 联', '4 联'],
                          onChanged: (val) {
                            if (val != null) {
                              setState(
                                () => _copies = int.tryParse(val[0]) ?? 1,
                              );
                              _markDirty();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 支持打印票据类型配置
              _buildLabel('支持打印票据类型 (勾选此打印机负责打印的单据)'),
              const SizedBox(height: 8),
              _buildTicketTypeSelector(),
              const SizedBox(height: 20),

              // 开关选项
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('自动切刀'),
                subtitle: Text(
                  '出票完毕后触发自动裁切',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
                value: _autoCut,
                onChanged: (v) {
                  setState(() => _autoCut = v);
                  _markDirty();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('出票蜂鸣提醒'),
                subtitle: Text(
                  '来单出票时触发打印机蜂鸣音响',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
                value: _beeper,
                onChanged: (v) {
                  setState(() => _beeper = v);
                  _markDirty();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启用此打印机'),
                value: _enabled,
                onChanged: (v) {
                  setState(() => _enabled = v);
                  _markDirty();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('设为默认打印机'),
                value: _isDefault,
                onChanged: (v) {
                  setState(() => _isDefault = v);
                  _markDirty();
                },
              ),
              const SizedBox(height: 28),

              // 底部按钮组
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    height: 45,
                    child: FilledButton(
                      onPressed: _saving ? null : _saveCurrentDevice,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFD84949),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              '保存配置',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 160,
                    height: 45,
                    child: OutlinedButton(
                      onPressed: _handleExitEdit,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFD9D9D9)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        '返回列表',
                        style: TextStyle(
                          color: Color(0xFF2C2C2E),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTicketTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 快捷预设按钮栏
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              '快捷预设：',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w500,
              ),
            ),
            _buildPresetChip(
              key: const Key('settings-preset-front-desk'),
              label: '前台预设 (整单/预结/结账)',
              onTap: () {
                setState(() {
                  _ticketTypes = List.of(
                    CashierPrinterTicketType.frontDeskPreset,
                  );
                });
                _markDirty();
              },
            ),
            _buildPresetChip(
              key: const Key('settings-preset-kitchen'),
              label: '后厨预设 (厨房/传菜)',
              onTap: () {
                setState(() {
                  _ticketTypes = List.of(
                    CashierPrinterTicketType.kitchenPreset,
                  );
                });
                _markDirty();
              },
            ),
            _buildPresetChip(
              key: const Key('settings-preset-all'),
              label: '全选',
              onTap: () {
                setState(() {
                  _ticketTypes = CashierPrinterTicketType.all
                      .map((e) => e.code)
                      .toList();
                });
                _markDirty();
              },
            ),
            _buildPresetChip(
              key: const Key('settings-preset-clear'),
              label: '清空',
              onTap: () {
                setState(() {
                  _ticketTypes = [];
                });
                _markDirty();
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        // 票据卡片多选网格
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: CashierPrinterTicketType.all.map((item) {
            final isSelected = _ticketTypes.contains(item.code);
            return InkWell(
              key: Key('settings-ticket-type-${item.code.toLowerCase()}'),
              onTap: () {
                setState(() {
                  if (isSelected) {
                    _ticketTypes = _ticketTypes
                        .where((c) => c != item.code)
                        .toList();
                  } else {
                    _ticketTypes = [..._ticketTypes, item.code];
                  }
                });
                _markDirty();
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 260,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFEFF6FF)
                      : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFE5E7EB),
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: isSelected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            if (!isSelected)
                              _ticketTypes = [..._ticketTypes, item.code];
                          } else {
                            _ticketTypes = _ticketTypes
                                .where((c) => c != item.code)
                                .toList();
                          }
                        });
                        _markDirty();
                      },
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                item.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? const Color(0xFF1E40AF)
                                      : const Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFFDBEAFE)
                                      : const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  item.code,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? const Color(0xFF1D4ED8)
                                        : const Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.description,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPresetChip({
    Key? key,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFD1D5DB)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF374151),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF848484),
      fontSize: 14,
      fontWeight: FontWeight.w500,
    ),
  );

  Widget _buildHelpText(String text) => Text(
    text,
    style: const TextStyle(color: Color(0xFF848484), fontSize: 12),
  );

  Widget _buildInputBox({
    required TextEditingController controller,
    required String hint,
    bool obscureText = false,
    ValueChanged<String>? onChanged,
  }) => Container(
    height: 45,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD9D9D9)),
    ),
    child: TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      style: const TextStyle(color: Color(0xFF2C2C2E), fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF848484), fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: InputBorder.none,
      ),
    ),
  );

  Widget _buildDropdownContainer({
    required String value,
    required List<String> items,
    Map<String, String>? itemLabels,
    required ValueChanged<String?> onChanged,
  }) => Container(
    height: 45,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD9D9D9)),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: items.contains(value) ? value : items.first,
        isExpanded: true,
        icon: const Text(
          '▾',
          style: TextStyle(color: Color(0xFF848484), fontSize: 16),
        ),
        items: items
            .map(
              (e) => DropdownMenuItem(
                value: e,
                child: Text(
                  itemLabels?[e] ?? e,
                  style: const TextStyle(
                    color: Color(0xFF2C2C2E),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
            .toList(),
        onChanged: onChanged,
      ),
    ),
  );

  Widget _buildRulesSection() {
    _rulesFuture ??= _loadRules();
    return FutureBuilder<_RulesData>(
      future: _rulesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError)
          return Center(
            child: SettingsEmptyState(
              title: '打印规则加载失败',
              description: '${snapshot.error}',
              icon: Icons.error_outline_rounded,
              primaryActionLabel: '重新加载',
              onPrimaryAction: _reloadSection,
            ),
          );
        final data = snapshot.data!;

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffe5e7eb)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '出票打印分流规则',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      if (_rulesVersion != null)
                        Text(
                          '规则版本: v$_rulesVersion',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.cashier.inkMuted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '每个打印场景只能配置一条规则；保存时会整体替换当前门店的全部规则。',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFallbackWarning(),
                  const SizedBox(height: 16),
                  if (_ruleDrafts.isEmpty)
                    SettingsEmptyState(
                      title: '暂无打印规则',
                      description: data.devices.isEmpty
                          ? '请先在“打印设备”中创建属于当前门店的设备。'
                          : '从一个打印场景开始配置出票去向。',
                      icon: Icons.rule_folder_outlined,
                    )
                  else
                    ..._ruleDrafts.indexed.map(
                      (e) => _buildRuleEditor(e.$1, e.$2, data),
                    ),
                  _buildAddRuleButton(),
                  const SizedBox(height: 20),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const Key('settings-print-rule-save'),
                      onPressed: _rulesSaving || _rulesVersion == null
                          ? null
                          : _saveRules,
                      icon: _rulesSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(_rulesSaving ? '正在保存全部规则…' : '保存全部规则'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<_Scenario> get _availableRuleScenarios {
    if (_printingMeta.scenarios.isEmpty) return _scenarios;
    return _printingMeta.scenarios
        .map(
          (item) =>
              _Scenario(item.ruleCode, item.name, _scenarioIcon(item.ruleCode)),
        )
        .toList(growable: false);
  }

  List<_Scenario> get _unusedRuleScenarios {
    final used = _ruleDrafts.map((e) => e.scenario).toSet();
    return _availableRuleScenarios
        .where((scenario) => !used.contains(scenario.code))
        .toList(growable: false);
  }

  Widget _buildAddRuleButton() {
    final available = _unusedRuleScenarios;
    if (available.isEmpty) {
      return OutlinedButton.icon(
        key: const Key('settings-print-rule-add'),
        onPressed: null,
        icon: const Icon(Icons.add_rounded),
        label: const Text('全部场景均已配置'),
      );
    }
    return PopupMenuButton<String>(
      key: const Key('settings-print-rule-add'),
      tooltip: '选择要配置的打印场景',
      onSelected: (scenario) {
        _markDirty();
        setState(
        () => _ruleDrafts = [..._ruleDrafts, _RuleDraft(scenario: scenario)],
      );
      },
      itemBuilder: (context) => available
          .map(
            (scenario) => PopupMenuItem<String>(
              key: Key('settings-print-rule-add-${scenario.code}'),
              value: scenario.code,
              child: Row(
                children: [
                  Icon(scenario.icon, size: 18),
                  const SizedBox(width: 10),
                  Text(scenario.label),
                ],
              ),
            ),
          )
          .toList(growable: false),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: context.cashier.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 18),
            SizedBox(width: 8),
            Text('新增打印规则'),
            SizedBox(width: 4),
            Icon(Icons.arrow_drop_down_rounded, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackWarning() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF7ED),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFDBA74)),
    ),
    child: const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.warning_amber_rounded, color: Color(0xFFC2410C)),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            '规则按场景独立生效；停用某场景规则会停止该场景出票。仅门店从未创建任何打印规则时，系统才会使用默认设备兼容冷启动。',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF9A3412),
              height: 1.4,
            ),
          ),
        ),
      ],
    ),
  );
  Widget _buildRuleEditor(int index, _RuleDraft rule, _RulesData data) {
    final scenario = _availableRuleScenarios.firstWhere(
      (item) => item.code == rule.scenario,
      orElse: () =>
          _Scenario(rule.scenario, rule.scenario, Icons.rule_folder_outlined),
    );
    final templates = data.templates;
    final selectedTemplateIsUnavailable =
        rule.templateCode != null &&
        templates.every(
          (template) => template.templateCode != rule.templateCode,
        );
    final templateItems = <DropdownMenuItem<String>>[
      if (selectedTemplateIsUnavailable)
        DropdownMenuItem(
          value: rule.templateCode,
          enabled: false,
          child: const Text('当前模板已不可用，请重新选择'),
        ),
      ...templates.map(
        (template) => DropdownMenuItem(
          value: template.templateCode,
          child: Text('${template.templateName} · ${template.scenario}'),
        ),
      ),
    ];

    return Container(
      key: Key('settings-print-rule-${rule.scenario}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: rule.enabled ? const Color(0xFFF9FAFB) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: rule.enabled
              ? const Color(0xFFE5E7EB)
              : const Color(0xFFFDE68A),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(scenario.icon, color: context.cashier.selected),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  scenario.label,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch.adaptive(
                value: rule.enabled,
                onChanged: (value) =>
                    _updateRule(index, rule.copyWith(enabled: value)),
              ),
              IconButton(
                tooltip: '删除规则',
                onPressed: () {
                  _markDirty();
                  setState(
                  () => _ruleDrafts = List.of(_ruleDrafts)..removeAt(index),
                );
                },
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (rule.scenario == 'packing') ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: const Text(
                '仅打包/自提订单生效；未启用该规则时不会额外打印打包单。',
                style: TextStyle(fontSize: 12, color: Color(0xFF1D4ED8)),
              ),
            ),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 250,
                child: _dropdown<int>(
                  '打印设备',
                  rule.deviceId,
                  '请选择当前门店设备',
                  data.devices
                      .map(
                        (device) => DropdownMenuItem(
                          value: device.id,
                          child: Text(device.name),
                        ),
                      )
                      .toList(),
                  (value) => _updateRule(index, rule.copyWith(deviceId: value)),
                ),
              ),
              SizedBox(
                width: 280,
                child: _dropdown<String>(
                  '小票模板',
                  rule.templateCode,
                  '请选择后端小票模板',
                  templateItems,
                  (value) =>
                      _updateRule(index, rule.copyWith(templateCode: value)),
                ),
              ),
              SizedBox(
                width: 150,
                child: _dropdown<int>(
                  '打印份数',
                  rule.copies,
                  '份数',
                  List.generate(
                    9,
                    (item) => DropdownMenuItem(
                      value: item + 1,
                      child: Text('${item + 1} 份'),
                    ),
                  ),
                  (value) => _updateRule(index, rule.copyWith(copies: value)),
                ),
              ),
            ],
          ),
          if (selectedTemplateIsUnavailable)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '当前规则引用的模板已不可用，请从后端模板列表重新选择。',
                style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
          if (!rule.enabled)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '该场景已停用，不会参与匹配或出票。',
                style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dropdown<T>(
    String label,
    T? value,
    String hint,
    List<DropdownMenuItem<T>> items,
    ValueChanged<T?> changed,
  ) => InputDecorator(
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        hint: Text(hint),
        isExpanded: true,
        items: items,
        onChanged: changed,
      ),
    ),
  );
  void _updateRule(int index, _RuleDraft rule) {
    _markDirty();
    setState(() => _ruleDrafts = List.of(_ruleDrafts)..[index] = rule);
  }

  Future<void> _saveRules() async {
    if (_ruleDrafts.any((e) => !e.complete)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请为每条规则选择打印设备、模板，并设置 1–9 份。')),
      );
      return;
    }
    final ok = await showSettingsConfirmDialog(
      context: context,
      title: '保存全部打印规则',
      message: '本次会整体替换当前门店的 ${_ruleDrafts.length} 条规则，未显示在此页的规则也会被删除。',
      impacts: const ['保存需要使用当前规则版本', '若版本已更新，系统会提示重新加载后再编辑'],
      confirmLabel: '确认保存',
    );
    if (ok != true) return;
    setState(() => _rulesSaving = true);
    try {
      await widget.repository.savePrintingRules(
        version: _rulesVersion!,
        rules: _ruleDrafts.map((e) => e.toJson()).toList(),
      );
      if (!mounted) return;
      showSettingsSaved(context, '全部打印规则已保存');
      _isFormDirty = false;
      widget.onDirtyChanged?.call(false);
      _reloadSection();
    } catch (e) {
      if (!mounted) return;
      if ('$e'.contains('409') || '$e'.contains('PRINTING_VERSION_CONFLICT')) {
        final reload = await showSettingsConfirmDialog(
          context: context,
          title: '规则版本冲突 (409)',
          message: '其他管理员已更新打印规则。重新加载会放弃当前未保存的编辑。',
          confirmLabel: '重新加载',
        );
        if (reload == true && mounted) {
          _isFormDirty = false;
          widget.onDirtyChanged?.call(false);
          _reloadSection();
        }
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存打印规则失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _rulesSaving = false);
    }
  }

  Future<void> _handleSetDefaultTemplate(PrintingTemplate template) async {
    try {
      await widget.repository.setDefaultPrintingTemplate(template.id);
      if (mounted) {
        showSettingsSaved(
          context,
          '已将「${template.templateName}」设为 ${template.scenario} 场景默认模板',
        );
        _loadTemplates();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('设为默认模板失败: $e')));
      }
    }
  }

  Future<void> _handleDeleteTemplate(PrintingTemplate template) async {
    final confirm = await showSettingsConfirmDialog(
      context: context,
      title: '删除小票模板',
      message: '确定要删除模板「${template.templateName}」吗？如果已有出票规则引用该模板，系统将自动拦截并提示。',
      destructive: true,
      confirmLabel: '确认删除',
    );
    if (confirm != true) return;

    try {
      await widget.repository.deletePrintingTemplate(template.id);
      if (mounted) {
        showSettingsSaved(context, '模板「${template.templateName}」已删除');
        _loadTemplates();
      }
    } catch (e) {
      if (mounted) {
        final errorStr = e.toString();
        if (errorStr.contains('IN_USE_BY_RULE')) {
          await showSettingsConfirmDialog(
            context: context,
            title: '模板正在被出票规则引用',
            message: '该模板正被部分打印机规则关联使用，请先在「出票规则」中修改关联设备后再行删除。',
            confirmLabel: '我知道了',
          );
        } else {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除模板失败: $e')));
        }
      }
    }
  }

  Future<void> _openCreateTemplateDialog() async {
    final created = await showCashierPrintingTemplateDesignerDialog(
      context: context,
      repository: widget.repository,
      storeName: _shop,
      initialScenario: _templateScenarioFilter != 'ALL'
          ? _templateScenarioFilter
          : 'ORDER',
      initialPaperSize: _templatePaperSizeFilter != 'ALL'
          ? _templatePaperSizeFilter
          : '58mm',
    );
    if (created != null && mounted) {
      showSettingsSaved(context, '自定义模板「${created.templateName}」创建成功');
      _loadTemplates();
    }
  }

  Future<void> _openEditTemplateDesigner(PrintingTemplate template) async {
    final updated = await showCashierPrintingTemplateDesignerDialog(
      context: context,
      repository: widget.repository,
      storeName: _shop,
      template: template,
    );
    if (updated != null && mounted) {
      showSettingsSaved(context, '模板「${updated.templateName}」已更新');
      _loadTemplates();
    }
  }

  Widget _buildTemplatesSection() {
    _templatesFuture ??= widget.repository.loadPrintingTemplates(
      scenario: _templateScenarioFilter,
      paperSize: _templatePaperSizeFilter,
    );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: context.cashier.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? context.cashier.border
                  : const Color(0xffe5e7eb),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '票据排版模板管理',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '支持类似美团/客如云的可视化拖拽勾选设计器、58mm/80mm 规格排版、系统预置与门店自定义模板。',
                        style: TextStyle(
                          fontSize: 14,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton.icon(
                        key: const Key('settings-printer-create-template-btn'),
                        onPressed: _openCreateTemplateDialog,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('新建自定义模板'),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        key: const Key('settings-printer-launch-simulator-btn'),
                        onPressed: () {
                          showCashierReceiptPreviewDialog(
                            context: context,
                            storeName: _shop,
                            initialScenario:
                                ReceiptTemplateScenario.standardReceipt,
                            onFetchPreview: (scenario, paperSize, custom) =>
                                widget.repository.fetchPrintPreview(
                                  scenario: scenario.code,
                                  paperSize: paperSize,
                                  customContent: custom,
                                ),
                          );
                        },
                        icon: const Icon(Icons.preview_rounded, size: 18),
                        label: const Text('热敏纸模拟器'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Color(0xFFE5E7EB)),
              const SizedBox(height: 16),

              // 场景与纸张规格筛选 Bar
              Row(
                children: [
                  const Text(
                    '适用场景: ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _templateScenarioFilters
                          .map(
                            (filter) => _buildScenarioFilterChip(
                              filter.label,
                              filter.code,
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    '纸张规格: ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 6,
                    children: [
                      _buildPaperSizeFilterChip('全部', 'ALL'),
                      _buildPaperSizeFilterChip('58mm 热敏纸', '58mm'),
                      _buildPaperSizeFilterChip('80mm 热敏纸', '80mm'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 模板列表卡片网格
              FutureBuilder<List<PrintingTemplate>>(
                future: _templatesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFECACA)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '获取票据模板失败: ${snapshot.error}',
                              style: const TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _loadTemplates,
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    );
                  }

                  final templates = snapshot.data ?? const [];

                  if (templates.isNotEmpty) {
                    return Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: templates
                          .map((tpl) => _buildPrintingTemplateCard(tpl))
                          .toList(),
                    );
                  }

                  return SettingsEmptyState(
                    title: '暂无可用票据模板',
                    description: '请先通过「新建自定义模板」创建模板；此页面仅展示后端已配置的模板。',
                    icon: Icons.receipt_long_outlined,
                    primaryActionLabel: '新建自定义模板',
                    onPrimaryAction: _openCreateTemplateDialog,
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScenarioFilterChip(String label, String value) {
    final isSelected = _templateScenarioFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFFEFF6FF),
      onSelected: (_) {
        setState(() => _templateScenarioFilter = value);
        _loadTemplates();
      },
    );
  }

  List<_TemplateScenarioFilter> get _templateScenarioFilters => [
    const _TemplateScenarioFilter('全部', 'ALL'),
    ..._availableRuleScenarios.map(
      (scenario) => _TemplateScenarioFilter(
        '${scenario.label} (${scenario.code.toUpperCase()})',
        scenario.code.toUpperCase(),
      ),
    ),
  ];

  Widget _buildPaperSizeFilterChip(String label, String value) {
    final isSelected = _templatePaperSizeFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFFEFF6FF),
      onSelected: (_) {
        setState(() => _templatePaperSizeFilter = value);
        _loadTemplates();
      },
    );
  }

  Widget _buildPrintingTemplateCard(PrintingTemplate template) {
    final isKitchen =
        template.scenario == 'KITCHEN' || template.scenario == 'EXPEDITE';
    final cardColor = isKitchen
        ? const Color(0xFFD97706)
        : const Color(0xFF2563EB);

    return Container(
      width: 370,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: template.isDefault
              ? const Color(0xFFF59E0B)
              : const Color(0xFFE5E7EB),
          width: template.isDefault ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: cardColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      template.scenario,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cardColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFD1D5DB)),
                    ),
                    child: Text(
                      template.paperSize,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: template.isSystem
                          ? const Color(0xFFF3F4F6)
                          : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      template.isSystem ? '系统内置' : '门店自定义',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: template.isSystem
                            ? const Color(0xFF6B7280)
                            : const Color(0xFF047857),
                      ),
                    ),
                  ),
                ],
              ),
              if (template.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star, size: 12, color: Color(0xFFD97706)),
                      SizedBox(width: 2),
                      Text(
                        '默认模板',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            template.templateName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '编码: ${template.templateCode}  ·  v${template.version}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 14),

          // 底部操作栏
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: Key('settings-template-preview-${template.id}'),
                  onPressed: () {
                    final matchedScenario = ReceiptTemplateScenario.fromCode(
                      template.scenario,
                    );
                    showCashierReceiptPreviewDialog(
                      context: context,
                      storeName: _shop,
                      initialScenario: matchedScenario,
                      initialPaperSize: template.paperSize,
                      onFetchPreview: (sc, paperSize, custom) =>
                          widget.repository.fetchPrintPreview(
                            scenario: template.scenario,
                            paperSize: paperSize,
                            templateId: template.id,
                            templateDsl: template.templateDsl?.toJson(),
                            customContent: custom,
                          ),
                    );
                  },
                  icon: const Icon(Icons.remove_red_eye_outlined, size: 14),
                  label: const Text('实时预览', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  key: Key('settings-template-edit-${template.id}'),
                  onPressed: () => _openEditTemplateDesigner(template),
                  icon: Icon(
                    template.isSystem
                        ? Icons.copy_rounded
                        : Icons.edit_outlined,
                    size: 14,
                  ),
                  label: Text(
                    template.isSystem ? '复制自定义' : '排版设计',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '更多操作',
                onSelected: (val) {
                  if (val == 'SET_DEFAULT') {
                    _handleSetDefaultTemplate(template);
                  } else if (val == 'DELETE') {
                    _handleDeleteTemplate(template);
                  }
                },
                itemBuilder: (ctx) => [
                  if (!template.isDefault)
                    const PopupMenuItem(
                      value: 'SET_DEFAULT',
                      child: Text('设为场景默认模板'),
                    ),
                  if (!template.isSystem)
                    const PopupMenuItem(
                      value: 'DELETE',
                      child: Text(
                        '删除该模板',
                        style: TextStyle(color: Color(0xFFEF4444)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection() {
    return FutureBuilder<CashierSettingsSectionData>(
      future: _sectionData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        final devices = _parseDevices(data);

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffe5e7eb)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '打印机通讯与出票测试',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '向已配置的真实打印设备发送测试指令包，支持收银小票、后厨分单、切刀裁切与自定义文本测试。',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 18),

                  // 测试单据类型选择器与排版效果预览快捷入口
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '选择测试出票类型',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF374151),
                        ),
                      ),
                      OutlinedButton.icon(
                        key: const Key('settings-printer-open-preview-btn'),
                        onPressed: () {
                          showCashierReceiptPreviewDialog(
                            context: context,
                            storeName: _shop,
                            initialScenario: ReceiptTemplateScenario.fromCode(
                              _selectedTestType,
                            ),
                            initialCustomText:
                                _customTestContentController.text,
                            devices: devices,
                            onFetchPreview: (sc, paperSize, custom) =>
                                widget.repository.fetchPrintPreview(
                                  scenario: sc.code,
                                  paperSize: paperSize,
                                  customContent: custom,
                                ),
                            onSendTest: (dev, type, custom) async {
                              await widget.repository.testPrinterDevice(
                                dev.id ?? 1,
                                testType: type,
                                customContent: custom,
                              );
                            },
                          );
                        },
                        icon: const Icon(
                          Icons.preview_rounded,
                          size: 16,
                          color: Color(0xFF2563EB),
                        ),
                        label: const Text(
                          '预览小票排版效果',
                          style: TextStyle(
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFFBFDBFE)),
                          backgroundColor: const Color(0xFFEFF6FF),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _buildTestTypeChip(
                        'STANDARD_RECEIPT',
                        '标准收银明细小票',
                        Icons.receipt_long_outlined,
                      ),
                      _buildTestTypeChip(
                        'KITCHEN_TICKET',
                        '后厨菜品分单小票',
                        Icons.soup_kitchen_outlined,
                      ),
                      _buildTestTypeChip(
                        'CUTTER_TEST',
                        '切刀裁切与走纸测试',
                        Icons.content_cut_outlined,
                      ),
                      _buildTestTypeChip(
                        'CUSTOM',
                        '自定义测试打印内容',
                        Icons.edit_note_outlined,
                      ),
                    ],
                  ),

                  if (_selectedTestType == 'CUSTOM') ...[
                    const SizedBox(height: 14),
                    TextField(
                      controller: _customTestContentController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: '请输入自定义测试打印文本内容（如：【测试单】1号桌 炭烤大油边 2份 辣）',
                        hintStyle: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(
                            color: Color(0xFFD1D5DB),
                          ),
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  const SizedBox(height: 16),

                  if (devices.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            size: 18,
                            color: Color(0xFF6B7280),
                          ),
                          SizedBox(width: 8),
                          Text(
                            '暂无已配置的打印机设备，请先在「打印设备」中添加打印机后再进行通讯测试',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF4B5563),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: devices.map((dev) {
                        return Container(
                          width: 360,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: dev.isOnline
                                  ? const Color(0xFFD1FAE5)
                                  : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: dev.isOnline
                                          ? const Color(0xFFECFDF5)
                                          : const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(
                                      Icons.print_outlined,
                                      color: dev.isOnline
                                          ? const Color(0xFF059669)
                                          : const Color(0xFF6B7280),
                                      size: 18,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dev.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${dev.vendor} · ${dev.transportDisplayName}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.cashier.inkMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      final (
                                        statusColor,
                                        statusBg,
                                        statusLabel,
                                        dotColor,
                                      ) = resolvePrinterStatusTheme(
                                        dev,
                                      );
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 7,
                                          vertical: 2.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: statusBg,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: statusColor.withOpacity(0.2),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: dotColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              statusLabel,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: statusColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () async {
                                        if (dev.id != null) {
                                          await widget.repository
                                              .testPrinterDevice(
                                                dev.id!,
                                                testType: _selectedTestType,
                                                customContent:
                                                    _selectedTestType ==
                                                        'CUSTOM'
                                                    ? _customTestContentController
                                                          .text
                                                          .trim()
                                                    : null,
                                              );
                                        }
                                        if (context.mounted) {
                                          showSettingsSaved(
                                            context,
                                            '出票测试指令已发送至「${dev.name}」',
                                          );
                                        }
                                      },
                                      icon: const Icon(
                                        Icons.send_rounded,
                                        size: 14,
                                      ),
                                      label: const Text(
                                        '发送出票',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton(
                                    onPressed: () {
                                      showCashierReceiptPreviewDialog(
                                        context: context,
                                        storeName: dev.shopName.isNotEmpty
                                            ? dev.shopName
                                            : _shop,
                                        initialScenario:
                                            ReceiptTemplateScenario.fromCode(
                                              _selectedTestType,
                                            ),
                                        initialCustomText:
                                            _customTestContentController.text,
                                        devices: [dev],
                                        onFetchPreview:
                                            (sc, paperSize, custom) => widget
                                                .repository
                                                .fetchPrintPreview(
                                                  scenario: sc.code,
                                                  deviceId: dev.id,
                                                  paperSize: paperSize,
                                                  customContent: custom,
                                                ),
                                        onSendTest:
                                            (targetDev, type, custom) async {
                                              await widget.repository
                                                  .testPrinterDevice(
                                                    targetDev.id ?? 1,
                                                    testType: type,
                                                    customContent: custom,
                                                  );
                                            },
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: const Text(
                                      '预览',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton(
                                    onPressed: () => _probeDevice(dev),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                    ),
                                    child: const Text(
                                      '探活',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                  if (dev.transport == 'CLOUD') ...[
                                    const SizedBox(width: 6),
                                    OutlinedButton(
                                      onPressed: () => _clearDeviceQueue(dev),
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                        ),
                                      ),
                                      child: const Text(
                                        '清空',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTestTypeChip(String type, String label, IconData icon) {
    final isSelected = _selectedTestType == type;
    return InkWell(
      onTap: () => setState(() => _selectedTestType = type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B82F6)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected
                  ? const Color(0xFF2563EB)
                  : const Color(0xFF6B7280),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? const Color(0xFF1E40AF)
                    : const Color(0xFF374151),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// v1.2.218：打印任务业务溯源（bizType/bizId）中文标签
  String _bizTypeLabel(String code) {
    switch (code) {
      case 'kds_serve':
        return 'KDS 划菜';
      default:
        return code;
    }
  }

  Widget _buildJobsSection() {
    return FutureBuilder<CashierSettingsSectionData>(
      future: _sectionData,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snapshot.data;
        final items = data?.items ?? const [];
        final filteredItems = items.where((j) {
          final status = '${j['status'] ?? 'SUCCESS'}'.toUpperCase();
          if (_selectedJobStatusFilter == 'SUCCESS') return status == 'SUCCESS';
          if (_selectedJobStatusFilter == 'FAILED')
            return status == 'FAILED' || status == 'ERROR';
          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xffe5e7eb)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '打印任务流水与重试记录',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '刷新流水',
                        onPressed: _reloadSection,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '记录打印指令下发状态，支持失败原因排查与一键重新补打。',
                    style: TextStyle(
                      fontSize: 14,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 状态筛选器
                  Row(
                    children: [
                      _buildJobFilterPill('ALL', '全部 (${items.length})'),
                      const SizedBox(width: 8),
                      _buildJobFilterPill(
                        'SUCCESS',
                        '成功 (${items.where((j) => "${j['status']}".toUpperCase() == "SUCCESS").length})',
                      ),
                      const SizedBox(width: 8),
                      _buildJobFilterPill(
                        'FAILED',
                        '失败 (${items.where((j) => "${j['status']}".toUpperCase() == "FAILED" || "${j['status']}".toUpperCase() == "ERROR").length})',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  if (filteredItems.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Center(
                        child: Text(
                          '暂无符合条件的打印任务流水记录',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else
                    ...filteredItems.map((job) {
                      final jobId = job['id'] ?? job['jobId'] ?? 0;
                      final status = '${job['status'] ?? 'SUCCESS'}'
                          .toUpperCase();
                      final error = job['error'] ?? job['errorMessage'];
                      final retryCount = job['retryCount'] ?? 0;
                      final deviceId = job['deviceId'] ?? job['device_id'];
                      final createdAt = job['createdAt'] ?? job['created_at'];
                      final payloadText =
                          '${job['payloadText'] ?? job['payload_text'] ?? ''}'
                              .trim();
                      final scenarioName =
                          job['scenarioName'] ?? job['scenario_name'];
                      final jobType = job['jobType'] ?? job['job_type'];
                      final jobScenarioLabel =
                          scenarioName != null &&
                              '$scenarioName'.trim().isNotEmpty
                          ? '$scenarioName'.trim()
                          : _printScenarioLabel('$jobType');
                      final bizType = job['bizType'] ?? job['biz_type'];
                      final bizId = job['bizId'] ?? job['biz_id'];
                      final isError = status == 'FAILED' || status == 'ERROR';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isError
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFE5E7EB),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              color: isError
                                  ? const Color(0xFFDC2626)
                                  : const Color(0xFF16A34A),
                              size: 22,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        '任务 #$jobId',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1.5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isError
                                              ? const Color(0xFFFEF2F2)
                                              : const Color(0xFFECFDF5),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                        child: Text(
                                          status,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: isError
                                                ? const Color(0xFFDC2626)
                                                : const Color(0xFF047857),
                                          ),
                                        ),
                                      ),
                                      if (jobScenarioLabel.isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF3F4F6),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            jobScenarioLabel,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF374151),
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (bizType != null &&
                                          '$bizType'.trim().isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 1.5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEFF6FF),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            '${_bizTypeLabel('$bizType')}${bizId != null && '$bizId'.trim().isNotEmpty ? ' #$bizId' : ''}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF1D4ED8),
                                            ),
                                          ),
                                        ),
                                      ],
                                      if (deviceId != null) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '设备ID: $deviceId',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                      if (createdAt != null) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '$createdAt',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  if (error != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '失败原因: $error',
                                      style: const TextStyle(
                                        color: Color(0xFFDC2626),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            Text(
                              '重试: $retryCount 次',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              children: [
                                if (payloadText.isNotEmpty)
                                  OutlinedButton.icon(
                                    key: Key(
                                      'settings-print-job-preview-$jobId',
                                    ),
                                    onPressed: () =>
                                        showCashierPrintJobPayloadPreviewDialog(
                                          context,
                                          jobId: '$jobId',
                                          payloadText: payloadText,
                                          scenarioName: scenarioName
                                              ?.toString(),
                                        ),
                                    icon: const Icon(
                                      Icons.visibility_outlined,
                                      size: 14,
                                    ),
                                    label: const Text('查看打印内容'),
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      minimumSize: const Size(0, 32),
                                    ),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: () {
                                    final id = int.tryParse('$jobId') ?? 0;
                                    if (id > 0) {
                                      _reprintJob(id);
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.replay_rounded,
                                    size: 14,
                                  ),
                                  label: const Text('一键补打'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    minimumSize: const Size(0, 32),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _printScenarioLabel(String raw) {
    final code = _ruleScenarioCode(raw);
    if (code.isEmpty || code == 'null') return '';
    for (final scenario in _availableRuleScenarios) {
      if (scenario.code == code) return scenario.label;
    }
    return raw;
  }

  Widget _buildJobFilterPill(String key, String label) {
    final isSelected = _selectedJobStatusFilter == key;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isSelected ? Colors.white : const Color(0xFF374151),
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF2563EB),
      backgroundColor: const Color(0xFFF3F4F6),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedJobStatusFilter = key);
        }
      },
    );
  }
}

/// 打印设备方块卡片组件 (Square Tile Card)
class _PrinterDeviceSquareCard extends StatelessWidget {
  const _PrinterDeviceSquareCard({
    required this.device,
    required this.onTap,
    required this.onQuickTest,
    required this.onProbe,
    this.onClearQueue,
  });

  final CashierPrinterDevice device;
  final VoidCallback onTap;
  final VoidCallback onQuickTest;
  final VoidCallback onProbe;
  final VoidCallback? onClearQueue;

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusBg, statusLabel, dotColor) =
        resolvePrinterStatusTheme(device);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: context.cashier.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Theme.of(context).brightness == Brightness.dark
                ? context.cashier.border
                : (device.isOnline
                      ? const Color(0xFFD1FAE5)
                      : const Color(0xFFE5E7EB)),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部：设备名称 + 默认标志 + 彩色在线状态胶囊
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: device.isOnline
                        ? const Color(0xFFECFDF5)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.print_rounded,
                    color: device.isOnline
                        ? const Color(0xFF059669)
                        : const Color(0xFF6B7280),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (device.isDefault) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '默认',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFB45309),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        device.transportDisplayName,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                // 状态胶囊 (带指示灯圆点)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 22, color: Color(0xFFF3F4F6)),

            // 基础信息区块：商家、门店、连接方式/SN/IP
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildInfoRow(Icons.business_rounded, '商家品牌', device.vendor),
                  _buildInfoRow(
                    Icons.storefront_outlined,
                    '所属门店',
                    device.shopName,
                  ),
                  _buildInfoRow(
                    Icons.cable_rounded,
                    '连接方式',
                    device.transport == 'CLOUD'
                        ? '云打印 · SN: ${device.sn ?? '未配置'}'
                        : device.transport == 'LAN'
                        ? '网口 · IP: ${device.ip?.isNotEmpty == true ? device.ip : '未配置'}'
                        : device.transportDisplayName,
                  ),
                  _buildInfoRow(
                    Icons.receipt_long_outlined,
                    '打印票据',
                    device.ticketTypesSummary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // 底部操作区：规格标签、探活、清空队列与配置入口
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${device.paperSize} · ${device.copies}联',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: onProbe,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.health_and_safety_outlined,
                          size: 12,
                          color: Color(0xFF2563EB),
                        ),
                        SizedBox(width: 2),
                        Text(
                          '探活',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onClearQueue != null) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: onClearQueue,
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cleaning_services_outlined,
                            size: 12,
                            color: Color(0xFFDC2626),
                          ),
                          SizedBox(width: 2),
                          Text(
                            '清空',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                const Text(
                  '配置',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 11,
                  color: Color(0xFF9CA3AF),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    bool isWarning = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: isWarning ? const Color(0xFFDC2626) : const Color(0xFF9CA3AF),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 12,
            color: isWarning
                ? const Color(0xFFDC2626)
                : const Color(0xFF6B7280),
          ),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isWarning
                  ? const Color(0xFFDC2626)
                  : const Color(0xFF1F2937),
            ),
          ),
        ),
      ],
    );
  }
}

(Color, Color, String, Color) resolvePrinterStatusTheme(
  CashierPrinterDevice device,
) {
  if (device.isError || device.isOutOfPaper || device.isCoverOpen) {
    final label = device.isOutOfPaper
        ? '缺纸'
        : (device.isCoverOpen
              ? '开盖'
              : (device.status == 'ERROR' ? '异常' : '异常/缺纸'));
    return (
      const Color(0xFFB91C1C),
      const Color(0xFFFEF2F2),
      label,
      const Color(0xFFEF4444),
    );
  }
  if (device.isOnline) {
    return (
      const Color(0xFF047857),
      const Color(0xFFECFDF5),
      '在线',
      const Color(0xFF10B981),
    );
  }
  if (device.isOffline) {
    return (
      const Color(0xFF4B5563),
      const Color(0xFFF3F4F6),
      '离线',
      const Color(0xFF9CA3AF),
    );
  }
  return (
    const Color(0xFF64748B),
    const Color(0xFFF1F5F9),
    '未知',
    const Color(0xFF94A3B8),
  );
}

/// "+ 新增打印设备" 方块卡片
class _AddPrinterSquareCard extends StatelessWidget {
  const _AddPrinterSquareCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD1D5DB), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Icon(Icons.add, color: Color(0xFF374151), size: 24),
            ),
            const SizedBox(height: 12),
            const Text(
              '添加新打印设备',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '支持飞鹅/易联云/佳博/网口/USB',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RulesData {
  const _RulesData({
    required this.version,
    required this.rules,
    required this.devices,
    required this.templates,
  });
  final int? version;
  final List<_RuleDraft> rules;
  final List<CashierPrinterDevice> devices;
  final List<PrintingTemplate> templates;
}

class _RuleDraft {
  const _RuleDraft({
    required this.scenario,
    this.deviceId,
    this.templateCode,
    this.copies = 1,
    this.enabled = true,
  });
  factory _RuleDraft.fromJson(Map<String, Object?> json) => _RuleDraft(
    scenario: _ruleScenarioCode('${json['scenario'] ?? ''}'),
    deviceId: _ruleInt(json['deviceId'] ?? json['device_id']),
    templateCode:
        '${json['templateCode'] ?? json['template_code'] ?? ''}'.isEmpty
        ? null
        : '${json['templateCode'] ?? json['template_code']}',
    copies: (_ruleInt(json['copies']) ?? 1).clamp(1, 9),
    enabled:
        json['enabled'] != false &&
        json['enabled'] != 0 &&
        json['enabled'] != '0',
  );
  final String scenario;
  final int? deviceId;
  final String? templateCode;
  final int copies;
  final bool enabled;
  bool get complete =>
      deviceId != null &&
      templateCode != null &&
      templateCode!.isNotEmpty &&
      copies >= 1 &&
      copies <= 9;
  _RuleDraft copyWith({
    int? deviceId,
    String? templateCode,
    int? copies,
    bool? enabled,
  }) => _RuleDraft(
    scenario: scenario,
    deviceId: deviceId ?? this.deviceId,
    templateCode: templateCode ?? this.templateCode,
    copies: copies ?? this.copies,
    enabled: enabled ?? this.enabled,
  );
  Map<String, Object?> toJson() => {
    'scenario': scenario,
    'deviceId': deviceId,
    'templateCode': templateCode,
    'copies': copies,
    'enabled': enabled,
  };
}

class _Scenario {
  const _Scenario(this.code, this.label, this.icon);
  final String code;
  final String label;
  final IconData icon;
}

class _TemplateScenarioFilter {
  const _TemplateScenarioFilter(this.label, this.code);

  final String label;
  final String code;
}

const _scenarios = <_Scenario>[
  _Scenario('kitchen', '厨房制作票', Icons.restaurant_outlined),
  _Scenario('full_order', '前台整单', Icons.receipt_long_outlined),
  _Scenario('pre_checkout', '预结单', Icons.request_quote_outlined),
  _Scenario('checkout', '结账单', Icons.payments_outlined),
  _Scenario('expedite', '传菜单', Icons.room_service_outlined),
  _Scenario('takeout', '外卖单', Icons.delivery_dining_outlined),
  _Scenario('packing', '打包单', Icons.inventory_2_outlined),
  _Scenario('shift', '交接班报表', Icons.change_circle_outlined),
  _Scenario('refund', '退款单', Icons.undo_outlined),
  _Scenario('label', '标签 / 杯贴', Icons.sell_outlined),
  _Scenario('test', '测试单', Icons.print_outlined),
];
IconData _scenarioIcon(String code) => switch (code.toLowerCase()) {
  'kitchen' => Icons.restaurant_outlined,
  'full_order' => Icons.receipt_long_outlined,
  'pre_checkout' => Icons.request_quote_outlined,
  'checkout' => Icons.payments_outlined,
  'expedite' => Icons.room_service_outlined,
  'takeout' => Icons.delivery_dining_outlined,
  'packing' => Icons.inventory_2_outlined,
  'shift' => Icons.change_circle_outlined,
  'refund' => Icons.undo_outlined,
  'label' => Icons.sell_outlined,
  'test' => Icons.print_outlined,
  _ => Icons.rule_folder_outlined,
};
String _ruleScenarioCode(String raw) => switch (raw.trim().toLowerCase()) {
  'order' || 'receipt' || 'bill' => 'checkout',
  'serve' || 'kds_serve' => 'expedite',
  'precheckout' => 'pre_checkout',
  _ => raw.trim().toLowerCase(),
};
int? _ruleInt(Object? value) => value is int ? value : int.tryParse('$value');

/// 解析后端 SectionData 为领域对象列表（100% 以后端真实返回数据为主，不使用本地模拟数据）
List<CashierPrinterDevice> _parseDevices(CashierSettingsSectionData? data) {
  if (data == null || data.items.isEmpty) {
    return const [];
  }

  return data.items.map((item) => CashierPrinterDevice.fromJson(item)).toList();
}
