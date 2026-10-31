import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import 'cashier_runtime_diagnostics_page.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import 'cashier_settings_shared.dart';

/// 设置页 · 日志（重构版：全表格水平/垂直滚动支持、多级子页与详情弹窗）。
///
/// 数据口径一律来自 openapi.yaml（禁止 mock）：
/// - 操作日志 / 设备日志：`GET /admin/logs`（近 30 天硬边界、敏感信息脱敏、
///   allShops 仅总部可用；设备日志为该接口的设备模块筛选视图，openapi 未定义
///   独立级别字段，级别列不展示）
/// - 归档检索：`POST /admin/logs/archive-search`（30 天~1 年异步任务，与报表
///   导出共享全局 128 / 单门店 4 未完成任务配额）+ `GET /admin/logs/archive-search/{jobId}`
///   （DONE 返回命中摘要，明细数据至归档存储查看）
/// - 日志导出：`POST /admin/logs/exports`（purpose 必填、log:export 仅超管、
///   返回 jobId + auditNo 并记审计；openapi 未提供导出记录列表接口，记录仅在
///   当前会话内展示）
class CashierSettingsLogPage extends StatefulWidget {
  const CashierSettingsLogPage({
    super.key,
    required this.client,
    required this.section,
    required this.storeName,
    this.currentShopId,
    this.permissions = const {},
  });

  final AdminApiClient? client;
  final SettingsSectionSpec section;
  final String storeName;
  final int? currentShopId;
  final Set<String> permissions;

  @override
  State<CashierSettingsLogPage> createState() => _CashierSettingsLogPageState();
}

class _CashierSettingsLogPageState extends State<CashierSettingsLogPage> {
  @override
  Widget build(BuildContext context) {
    if (widget.section.id == 'runtime') {
      return const CashierRuntimeDiagnosticsPage();
    }
    final client = widget.client;
    if (client == null) {
      return const SettingsPagePadding(
        child: SettingsErrorState(message: '日志查询需要登录后使用', onRetry: null),
      );
    }
    final scope = _LogApiScope(
      client: client.copyWith(shopId: widget.currentShopId),
      permissions: widget.permissions,
      storeName: widget.storeName,
    );
    return switch (widget.section.id) {
      'operations' => _OperationsView(scope: scope),
      'devices' => _DevicesView(scope: scope),
      'archive' => _ArchiveView(scope: scope),
      'exports' => _ExportsView(scope: scope),
      _ => SettingsPagePadding(
          child: SettingsErrorState(
            message: '不支持的日志页面：${widget.section.id}',
            onRetry: null,
          ),
        ),
    };
  }
}

class _LogApiScope {
  const _LogApiScope({
    required this.client,
    required this.permissions,
    required this.storeName,
  });

  final AdminApiClient client;
  final Set<String> permissions;
  final String storeName;
}

// =====================================================================
// 1. 在线日志（操作日志视图）
// =====================================================================

class _OperationsView extends StatefulWidget {
  const _OperationsView({required this.scope});

  final _LogApiScope scope;

  @override
  State<_OperationsView> createState() => _OperationsViewState();
}

class _OperationsViewState extends State<_OperationsView> {
  static const _pageSize = 20;
  final ScrollController _vScrollController = ScrollController();
  bool _loading = true;
  Object? _error;
  List<Map<String, Object?>> _rows = const [];
  int _total = 0;
  int _page = 1;
  String _module = '';
  String _action = '';
  String _category = '';
  final _operatorController = TextEditingController();
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = now.subtract(const Duration(days: 6));
    _load();
  }

  @override
  void dispose() {
    _vScrollController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _dateOnly(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.scope.client.get(
        settingsLogsEndpoint,
        query: {
          if (_module.isNotEmpty) 'module': _module,
          if (_action.isNotEmpty) 'action': _action,
          if (_category.isNotEmpty) 'category': _category,
          if (_operatorController.text.trim().isNotEmpty)
            'operator': _operatorController.text.trim(),
          if (_start != null) 'startTime': _fmt(_start!),
          if (_end != null) 'endTime': _fmt(_end!),
          'page': _page,
          'pageSize': _pageSize,
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = objectList(data);
        _total = _intOf(_asMap(data)['total']);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _goPage(int page) {
    if (page < 1 || page > _maxPage() || page == _page) return;
    setState(() => _page = page);
    _load();
  }

  int _maxPage() => (_total / _pageSize).ceil().clamp(1, 1 << 31);

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_start ?? now) : (_end ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  void _reset() {
    final now = DateTime.now();
    setState(() {
      _module = '';
      _action = '';
      _category = '';
      _operatorController.clear();
      _end = now;
      _start = now.subtract(const Duration(days: 6));
      _page = 1;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vScrollController,
      thumbVisibility: false,
      notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
      child: SingleChildScrollView(
        controller: _vScrollController,
        child: SettingsPagePadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionIntro(
                title: '在线日志（近 30 天）',
                subtitle: '查询当前门店关键操作记录；手机号、身份证号按正则脱敏，全部门店范围仅总部可用。',
              ),
              const SizedBox(height: 16),
              _LogCard(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _FilterField(
                      label: '模块',
                      child: _drop(_module, _moduleOptions, (v) {
                        setState(() => _module = v);
                      }, width: 140),
                    ),
                    _FilterField(
                      label: '动作',
                      child: _drop(_action, _actionOptions, (v) {
                        setState(() => _action = v);
                      }, width: 150),
                    ),
                    _FilterField(
                      label: '类型',
                      child: _drop(_category, _categoryOptions, (v) {
                        setState(() => _category = v);
                      }, width: 120),
                    ),
                    _FilterField(
                      label: '操作人',
                      child: SizedBox(
                        width: 200,
                        child: TextField(
                          key: const Key('log-operator-input'),
                          controller: _operatorController,
                          decoration: const InputDecoration(hintText: '姓名 / 手机号',
                          ),
                        ),
                      ),
                    ),
                    _FilterField(
                      label: '时间范围',
                      child: _dateRangeRow()),
                    const SizedBox(width: 4, height: 44, child: _InlineDivider(),
                    ),
                    OutlinedButton(
                      key: const Key('log-filter-reset'),
                      onPressed: _reset,
                      child: const Text('重置'),
                    ),
                    FilledButton(
                      key: const Key('log-filter-search'),
                      onPressed: _load,
                      child: const Text('查询'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _StatsStrip(
                pageCount: _rows.length,
                total: _total,
                page: _page,
                pageSize: _pageSize,
              ),
              const SizedBox(height: 12),
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SettingsSkeletonLoader(rows: 6);
    if (_error != null) {
      return SettingsErrorState(message: '日志加载失败：$_error', onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const SettingsEmptyState(
        title: '暂无符合条件的日志',
        description: '调整筛选条件后重试，在线日志仅保留最近 30 天。',
      );
    }
    return _LogTable(
      rows: _rows,
      storeName: widget.scope.storeName,
      onDetail: (row) => _openDetail(row),
      footer: _pager(),
    );
  }

  Widget _pager() {
    final maxPage = _maxPage();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Text(
            '共 $_total 条 · 第 $_page / $maxPage 页',
            style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
          ),
          const Spacer(),
          OutlinedButton(
            key: const Key('log-prev'),
            onPressed: _page <= 1 ? null : () => _goPage(_page - 1),
            child: const Text('上一页'),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            key: const Key('log-next'),
            onPressed: _page >= maxPage ? null : () => _goPage(_page + 1),
            child: const Text('下一页'),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetail(Map<String, Object?> row) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _LogDetailDialog(row: row, storeName: widget.scope.storeName),
    );
  }

  Widget _dateRangeRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dateButton(_start, isStart: true),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text('至', style: TextStyle(fontSize: 13)),
        ),
        _dateButton(_end, isStart: false),
      ],
    );
  }

  Widget _dateButton(DateTime? value, {required bool isStart}) {
    return OutlinedButton(
      key: Key(isStart ? 'log-start' : 'log-end'),
      onPressed: () => _pickDate(isStart: isStart),
      child: Text(value == null ? '选择日期' : _dateOnly(value)),
    );
  }
}

// =====================================================================
// 2. 设备运行日志视图
// =====================================================================

class _DevicesView extends StatefulWidget {
  const _DevicesView({required this.scope});

  final _LogApiScope scope;

  @override
  State<_DevicesView> createState() => _DevicesViewState();
}

class _DevicesViewState extends State<_DevicesView> {
  static const _pageSize = 20;
  final ScrollController _vScrollController = ScrollController();
  bool _loading = true;
  Object? _error;
  List<Map<String, Object?>> _rows = const [];
  int _total = 0;
  int _page = 1;
  String _module = '';
  DateTime? _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = now.subtract(const Duration(days: 1));
    _load();
  }

  @override
  void dispose() {
    _vScrollController.dispose();
    super.dispose();
  }

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _dateOnly(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.scope.client.get(
        settingsLogsEndpoint,
        query: {
          if (_module.isNotEmpty) 'module': _module,
          if (_start != null) 'startTime': _fmt(_start!),
          if (_end != null) 'endTime': _fmt(_end!),
          'page': _page,
          'pageSize': _pageSize,
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = objectList(data);
        _total = _intOf(_asMap(data)['total']);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _goPage(int page) {
    if (page < 1 || page > _maxPage() || page == _page) return;
    setState(() => _page = page);
    _load();
  }

  int _maxPage() => (_total / _pageSize).ceil().clamp(1, 1 << 31);

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_start ?? now) : (_end ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  void _reset() {
    final now = DateTime.now();
    setState(() {
      _module = '';
      _end = now;
      _start = now.subtract(const Duration(days: 1));
      _page = 1;
    });
    _load();
  }

  Future<void> _openDetail(Map<String, Object?> row) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _LogDetailDialog(row: row, storeName: widget.scope.storeName),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vScrollController,
      thumbVisibility: false,
      notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
      child: SingleChildScrollView(
        controller: _vScrollController,
        child: SettingsPagePadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionIntro(
                title: '设备运行日志',
                subtitle: '按设备模块与时间查询收银 / 厨显 / 打印设备运行记录（在线保留 30 天）；'
                    'openapi 未定义独立设备日志接口与级别字段，本页为在线日志的设备模块筛选视图。',
              ),
              const SizedBox(height: 16),
              _LogCard(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _FilterField(
                      label: '设备模块',
                      child: SizedBox(
                        width: 180,
                        child: DropdownButton<String>(
                          value: _module.isEmpty ? null : _module,
                          isExpanded: true,
                          hint: const Text('全部设备'),
                          items: const [
                            DropdownMenuItem<String>(value: null, child: Text('全部设备'),
                            ),
                            DropdownMenuItem<String>(value: 'kds', child: Text('KDS 厨显'),
                            ),
                            DropdownMenuItem<String>(value: 'printing', child: Text('打印'),
                            ),
                            DropdownMenuItem<String>(value: 'pos', child: Text('收银 POS'),
                            ),
                          ],
                          onChanged: (v) => setState(() => _module = v ?? ''),
                        ),
                      ),
                    ),
                    _FilterField(
                      label: '时间范围',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            key: const Key('dev-start'),
                            onPressed: () => _pickDate(isStart: true),
                            child: Text(_dateOnly(_start ?? DateTime.now())),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('至', style: TextStyle(fontSize: 13)),
                          ),
                          OutlinedButton(
                            key: const Key('dev-end'),
                            onPressed: () => _pickDate(isStart: false),
                            child: Text(_dateOnly(_end ?? DateTime.now())),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton(onPressed: _reset, child: const Text('重置')),
                    FilledButton(key: const Key('dev-search'), onPressed: _load, child: const Text('查询'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _StatsStrip(
                pageCount: _rows.length,
                total: _total,
                page: _page,
                pageSize: _pageSize,
              ),
              const SizedBox(height: 12),
              _buildBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SettingsSkeletonLoader(rows: 6);
    if (_error != null) {
      return SettingsErrorState(message: '设备日志加载失败：$_error', onRetry: _load);
    }
    if (_rows.isEmpty) {
      return const SettingsEmptyState(
        title: '暂无设备日志',
        description: '调整筛选条件后重试，在线日志仅保留最近 30 天。',
      );
    }
    return _DeviceLogTable(
      rows: _rows,
      storeName: widget.scope.storeName,
      onDetail: (row) => _openDetail(row),
      footer: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Text(
              '共 $_total 条 · 第 $_page / ${_maxPage()} 页',
              style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
            ),
            const Spacer(),
            OutlinedButton(
              onPressed: _page <= 1 ? null : () => _goPage(_page - 1),
              child: const Text('上一页'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _page >= _maxPage() ? null : () => _goPage(_page + 1),
              child: const Text('下一页'),
            ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// 3. 归档检索视图与任务表格
// =====================================================================

class _ArchiveView extends StatefulWidget {
  const _ArchiveView({required this.scope});

  final _LogApiScope scope;

  @override
  State<_ArchiveView> createState() => _ArchiveViewState();
}

class _ArchiveViewState extends State<_ArchiveView> {
  final ScrollController _vScrollController = ScrollController();
  String _module = '';
  String _action = '';
  final _operatorController = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  bool _creating = false;
  List<_ArchiveJob> _jobs = const [];
  final Set<int> _polling = {};
  final Map<int, int> _pollTries = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now.subtract(const Duration(days: 31));
    _start = now.subtract(const Duration(days: 365));
  }

  @override
  void dispose() {
    _vScrollController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _dateOnly(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  Future<void> _create() async {
    if (_creating) return;
    setState(() => _creating = true);
    try {
      final data = await widget.scope.client.post(
        settingsLogArchiveSearchEndpoint,
        body: {
          if (_module.isNotEmpty) 'module': _module,
          if (_action.isNotEmpty) 'action': _action,
          if (_operatorController.text.trim().isNotEmpty)
            'operator': _operatorController.text.trim(),
          if (_start != null) 'startTime': _fmt(_start!),
          if (_end != null) 'endTime': _fmt(_end!),
        },
      );
      if (!mounted) return;
      final jobId = _intOf(_asMap(data)['jobId']);
      setState(() {
        _creating = false;
        _jobs = [
          _ArchiveJob(
            jobId: jobId,
            module: _module.isEmpty ? '全部模块' : _module,
            action: _action.isEmpty ? '全部动作' : _action,
            operator: _operatorController.text.trim().isEmpty
                ? '全部'
                : _operatorController.text.trim(),
            status: 'PENDING',
            createdAt: DateTime.now(),
            start: _start,
            end: _end,
          ),
          ..._jobs,
        ];
      });
      showSettingsSaved(context, '归档检索任务已提交（任务 #$jobId）');
      _poll(jobId);
    } catch (error) {
      if (!mounted) return;
      setState(() => _creating = false);
      showSettingsSaved(context, '提交失败：$error');
    }
  }

  Future<void> _poll(int jobId) async {
    if (_polling.contains(jobId)) return;
    _polling.add(jobId);
    final tries = (_pollTries[jobId] ?? 0) + 1;
    _pollTries[jobId] = tries;
    try {
      final data = await widget.scope.client.get(
        settingsLogArchiveSearchDetailEndpoint('$jobId'),
      );
      if (!mounted) return;
      final status = _s(_asMap(data)['status']);
      setState(() {
        _jobs = [
          for (final j in _jobs)
            if (j.jobId == jobId)
              _ArchiveJob(
                jobId: j.jobId,
                module: j.module,
                action: j.action,
                operator: j.operator,
                status: status.isEmpty ? j.status : status,
                createdAt: j.createdAt,
                start: j.start,
                end: j.end,
                summary: status.isEmpty
                    ? j.summary
                    : _s(_asMap(data)['resultSummary'] ?? j.summary),
              )
            else
              j,
        ];
      });
      if (status.isEmpty || status == 'DONE' || status == 'FAILED') {
        _polling.remove(jobId);
        return;
      }
      if (tries < 10) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (mounted) _poll(jobId);
      } else {
        _polling.remove(jobId);
      }
    } catch (_) {
      _polling.remove(jobId);
    }
  }

  Future<void> _refresh(int jobId) async {
    try {
      final data = await widget.scope.client.get(
        settingsLogArchiveSearchDetailEndpoint('$jobId'),
      );
      if (!mounted) return;
      final status = _s(_asMap(data)['status']);
      setState(() {
        _jobs = [
          for (final j in _jobs)
            if (j.jobId == jobId)
              _ArchiveJob(
                jobId: j.jobId,
                module: j.module,
                action: j.action,
                operator: j.operator,
                status: status.isEmpty ? j.status : status,
                createdAt: j.createdAt,
                start: j.start,
                end: j.end,
                summary: status.isEmpty
                    ? j.summary
                    : _s(_asMap(data)['resultSummary'] ?? j.summary),
              )
            else
              j,
        ];
      });
      showSettingsSaved(context, '已更新任务 #$jobId 状态');
    } catch (error) {
      if (!mounted) return;
      showSettingsSaved(context, '刷新失败：$error');
    }
  }

  Future<void> _openJobDetail(_ArchiveJob job) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ArchiveJobDetailDialog(
        job: job,
        onRefresh: () => _refresh(job.jobId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vScrollController,
      thumbVisibility: false,
      notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
      child: SingleChildScrollView(
        controller: _vScrollController,
        child: SettingsPagePadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionIntro(
                title: '归档日志检索',
                subtitle: '在线 30 天以上的日志进入归档存储（最终保留 1 年）。检索为异步任务：'
                    '提交后进入后台检索队列，完成后可查看命中摘要；详细日志文件保存在云端审计存储中。',
              ),
              const SizedBox(height: 16),
              const _ArchiveQuotaNote(),
              const SizedBox(height: 16),
              _LogCard(
                padding: const EdgeInsets.all(20),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    _FilterField(
                      label: '模块',
                      child: _archiveDrop(_module, _moduleOptions, (v) {
                        setState(() => _module = v);
                      }),
                    ),
                    _FilterField(
                      label: '动作',
                      child: _archiveDrop(_action, _actionOptions, (v) {
                        setState(() => _action = v);
                      }),
                    ),
                    _FilterField(
                      label: '操作人',
                      child: SizedBox(
                        width: 200,
                        child: TextField(
                          key: const Key('archive-operator-input'),
                          controller: _operatorController,
                          decoration: const InputDecoration(hintText: '姓名 / 手机号',
                          ),
                        ),
                      ),
                    ),
                    _FilterField(
                      label: '归档时间范围（31~365天前）',
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            key: const Key('archive-start'),
                            onPressed: () => _pickDate(isStart: true),
                            child: Text(_dateOnly(_start ?? DateTime.now())),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Text('至', style: TextStyle(fontSize: 13)),
                          ),
                          OutlinedButton(
                            key: const Key('archive-end'),
                            onPressed: () => _pickDate(isStart: false),
                            child: Text(_dateOnly(_end ?? DateTime.now())),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4, height: 44, child: _InlineDivider(),
                    ),
                    FilledButton(
                      key: const Key('archive-submit'),
                      onPressed: _creating ? null : _create,
                      child: Text(_creating ? '提交中…' : '提交检索任务'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildJobsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobsSection() {
    if (_jobs.isEmpty) {
      return const _LogCard(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Text(
            '暂无检索任务，填写上方条件后提交',
            style: TextStyle(color: Color(0xff737373)),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              const Text(
                '检索任务列表',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              SettingsStatusBadge(
                label: '未完成任务 ${_jobs.where((j) => !_isDone(j.status)).length} / 4',
                type: StatusBadgeType.neutral,
              ),
            ],
          ),
        ),
        _ArchiveJobTable(
          jobs: _jobs,
          onRefresh: _refresh,
          onDetail: _openJobDetail,
        ),
      ],
    );
  }

  bool _isDone(String status) => status == 'DONE' || status == 'FAILED';

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_start ?? now) : (_end ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  Widget _archiveDrop(String value, List<(String, String)> options, ValueChanged<String> onChanged,
  ) {
    return _drop(value, options, onChanged, width: 150);
  }
}

class _ArchiveJob {
  const _ArchiveJob({
    required this.jobId,
    required this.module,
    required this.action,
    required this.operator,
    required this.status,
    required this.createdAt,
    this.start,
    this.end,
    this.summary = '',
  });

  final int jobId;
  final String module;
  final String action;
  final String operator;
  final String status;
  final DateTime createdAt;
  final DateTime? start;
  final DateTime? end;
  final String summary;
}

class _ArchiveJobTable extends StatelessWidget {
  const _ArchiveJobTable({
    required this.jobs,
    required this.onRefresh,
    required this.onDetail,
  });

  final List<_ArchiveJob> jobs;
  final ValueChanged<int> onRefresh;
  final ValueChanged<_ArchiveJob> onDetail;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTableCard(
      minWidth: 1100,
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(85),  // 任务ID
          1: FixedColumnWidth(135), // 提交时间
          2: FixedColumnWidth(95),  // 模块
          3: FixedColumnWidth(130), // 动作
          4: FixedColumnWidth(105), // 操作人
          5: FixedColumnWidth(170), // 时间范围
          6: FixedColumnWidth(110), // 状态
          7: FixedColumnWidth(140), // 结果摘要
          8: FixedColumnWidth(130), // 操作
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: context.cashier.row,
              border: const Border(
                bottom: BorderSide(color: Color(0xffd8d8d8), width: 1),
              ),
            ),
            children: [
              _header(context, '任务ID'),
              _header(context, '提交时间'),
              _header(context, '模块'),
              _header(context, '动作'),
              _header(context, '操作人'),
              _header(context, '时间跨度'),
              _header(context, '状态'),
              _header(context, '结果摘要'),
              _header(context, '操作'),
            ],
          ),
          ...jobs.map((job) {
            final (badgeType, badgeLabel) = switch (job.status) {
              'DONE' => (StatusBadgeType.success, '已完成'),
              'FAILED' => (StatusBadgeType.danger, '失败'),
              'RUNNING' => (StatusBadgeType.warning, '检索中'),
              'PENDING' => (StatusBadgeType.info, '排队中'),
              _ => (StatusBadgeType.neutral, job.status),
            };
            final timeRangeStr = job.start == null || job.end == null
                ? '全部历史时间'
                : '${_dateOnlyDirect(job.start!)} ~ ${_dateOnlyDirect(job.end!)}';
            return TableRow(
              decoration: BoxDecoration(
                color: context.cashier.surface,
                border: Border(
                  bottom: BorderSide(color: context.cashier.row, width: 1),
                ),
              ),
              children: [
                _cell(
                  context,
                  Text(
                    '#${job.jobId}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: context.cashier.ink,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    _timeDirect(job.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(context, Text(job.module, style: const TextStyle(fontSize: 13)),
                ),
                _cell(
                  context,
                  Text(
                    job.action,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    job.operator,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    timeRangeStr,
                    style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsStatusBadge(label: badgeLabel, type: badgeType,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    job.summary.isEmpty ? '-' : job.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton(
                        onPressed: () => onDetail(job),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 30),
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('详情', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 2),
                      IconButton(
                        tooltip: '刷新状态',
                        iconSize: 15,
                        constraints: const BoxConstraints(minWidth: 26, minHeight: 26,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: () => onRefresh(job.jobId),
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// =====================================================================
// 4. 日志导出视图与导出记录表格
// =====================================================================

class _ExportsView extends StatefulWidget {
  const _ExportsView({required this.scope});

  final _LogApiScope scope;

  @override
  State<_ExportsView> createState() => _ExportsViewState();
}

class _ExportsViewState extends State<_ExportsView> {
  final ScrollController _vScrollController = ScrollController();
  String _module = '';
  final _purposeController = TextEditingController();
  DateTime? _start;
  DateTime? _end;
  bool _submitting = false;
  List<_ExportRecord> _records = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _end = now;
    _start = now.subtract(const Duration(days: 6));
  }

  @override
  void dispose() {
    _vScrollController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  bool get _hasExportPermission =>
      widget.scope.permissions.contains('log:export') ||
      widget.scope.permissions.contains('admin:manage');

  String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  }

  String _dateOnly(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  Future<void> _export() async {
    final purpose = _purposeController.text.trim();
    if (purpose.isEmpty) {
      showSettingsSaved(context, '请填写导出用途（用于合规审计）');
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final data = await widget.scope.client.post(
        settingsLogExportEndpoint,
        body: {
          'purpose': purpose,
          'query': {
            if (_module.isNotEmpty) 'module': _module,
          if (_start != null) 'startTime': _fmt(_start!),
          if (_end != null) 'endTime': _fmt(_end!),
          },
        },
      );
      if (!mounted) return;
      final map = _asMap(data);
      final jobId = _intOf(map['jobId']);
      final auditNo = _s(map['auditNo']);
      setState(() {
        _submitting = false;
        _records = [
          _ExportRecord(
            auditNo: auditNo.isEmpty ? 'AUDIT-$jobId' : auditNo,
            jobId: jobId,
            purpose: purpose,
            module: _module.isEmpty ? '全部模块' : _module,
            start: _start,
            end: _end,
            createdAt: DateTime.now(),
          ),
          ..._records,
        ];
        _purposeController.clear();
      });
      showSettingsSaved(context, '导出任务已提交，审计编号 $auditNo');
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showSettingsSaved(context, '提交失败：$error');
    }
  }

  Future<void> _openExportDetail(_ExportRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ExportRecordDetailDialog(record: record),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _vScrollController,
      thumbVisibility: false,
      notificationPredicate: (notif) => notif.metrics.axis == Axis.vertical,
      child: SingleChildScrollView(
        controller: _vScrollController,
        child: SettingsPagePadding(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SectionIntro(
                title: '日志导出（仅超级管理员）',
                subtitle: '导出脱敏日志用于审计归档；导出行为本身也会写入审计记录（生成审计编号）。'
                    '需要系统管理员（log:export）权限。',
              ),
              const SizedBox(height: 16),
              if (!_hasExportPermission)
                const SettingsForbiddenPlaceholder(moduleName: '日志导出')
              else ...[
                _LogCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          _FilterField(
                            label: '导出模块',
                            child: _exportDrop(_module, _moduleOptions, (v) {
                              setState(() => _module = v);
                            }),
                          ),
                          _FilterField(
                            label: '时间范围',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _pickDate(isStart: true),
                                  child: Text(_dateOnly(_start ?? DateTime.now()),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Text('至', style: TextStyle(fontSize: 13),
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: () => _pickDate(isStart: false),
                                  child: Text(_dateOnly(_end ?? DateTime.now()),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _FilterField(
                        label: '导出用途（必填，计入合规审计）',
                        child: TextField(
                          key: const Key('export-purpose-input'),
                          controller: _purposeController,
                          maxLength: 100,
                          decoration: const InputDecoration(
                            hintText: '例：2026 年中业务审计 / 异常排查凭据',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          key: const Key('export-submit'),
                          onPressed: _submitting ? null : _export,
                          child: Text(_submitting ? '提交中…' : '提交导出'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildRecordsSection(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecordsSection() {
    if (_records.isEmpty) {
      return const _LogCard(
        padding: EdgeInsets.all(40),
        child: Center(
          child: Text(
            '暂无导出记录（后端未提供导出记录列表接口，仅展示当前会话提交）',
            style: TextStyle(color: Color(0xff737373)),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            '本次会话导出记录',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        _ExportRecordTable(
          records: _records,
          onDetail: _openExportDetail),
      ],
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_start ?? now) : (_end ?? now),
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _start = picked;
        if (_end != null && _end!.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
        if (_start != null && _start!.isAfter(picked)) _start = picked;
      }
    });
  }

  Widget _exportDrop(String value, List<(String, String)> options, ValueChanged<String> onChanged,
  ) {
    return _drop(value, options, onChanged, width: 150);
  }
}

class _ExportRecord {
  const _ExportRecord({
    required this.auditNo,
    required this.jobId,
    required this.purpose,
    required this.module,
    required this.start,
    required this.end,
    required this.createdAt,
  });

  final String auditNo;
  final int jobId;
  final String purpose;
  final String module;
  final DateTime? start;
  final DateTime? end;
  final DateTime createdAt;
}

class _ExportRecordTable extends StatelessWidget {
  const _ExportRecordTable({
    required this.records,
    required this.onDetail});

  final List<_ExportRecord> records;
  final ValueChanged<_ExportRecord> onDetail;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTableCard(
      minWidth: 1080,
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(210), // 审计编号
          1: FixedColumnWidth(85),  // 任务ID
          2: FixedColumnWidth(100), // 模块
          3: FixedColumnWidth(200), // 导出用途
          4: FixedColumnWidth(170), // 时间范围
          5: FixedColumnWidth(130), // 提交时间
          6: FixedColumnWidth(105), // 状态
          7: FixedColumnWidth(80),  // 操作
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: context.cashier.row,
              border: const Border(
                bottom: BorderSide(color: Color(0xffd8d8d8), width: 1),
              ),
            ),
            children: [
              _header(context, '审计编号'),
              _header(context, '任务ID'),
              _header(context, '模块'),
              _header(context, '导出用途'),
              _header(context, '时间范围'),
              _header(context, '提交时间'),
              _header(context, '状态'),
              _header(context, '操作'),
            ],
          ),
          ...records.map((r) {
            final timeRangeStr = r.start == null || r.end == null
                ? '全部时间'
                : '${_dateOnlyDirect(r.start!)} ~ ${_dateOnlyDirect(r.end!)}';
            return TableRow(
              decoration: BoxDecoration(
                color: context.cashier.surface,
                border: Border(
                  bottom: BorderSide(color: context.cashier.row, width: 1),
                ),
              ),
              children: [
                _cell(
                  context,
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.auditNo,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: context.cashier.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip: '复制审计编号',
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 20, minHeight: 20,
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: r.auditNo),
                          );
                          if (context.mounted) {
                            showSettingsSaved(context, '已复制审计编号：${r.auditNo}');
                          }
                        },
                      ),
                    ],
                  ),
                ),
                _cell(
                  context,
                  Text(
                    '#${r.jobId}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(context, Text(r.module, style: const TextStyle(fontSize: 13)),
                ),
                _cell(
                  context,
                  Text(
                    r.purpose,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    timeRangeStr,
                    style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    _timeDirect(r.createdAt),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(
                  context,
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsStatusBadge(
                      label: '已提交',
                      type: StatusBadgeType.success,
                    ),
                  ),
                ),
                _cell(
                  context,
                  OutlinedButton(
                    onPressed: () => onDetail(r),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(54, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('详情', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

// =====================================================================
// 5. 共享小部件与滑动容器
// =====================================================================

/// 统一的带横向滚动条的数据表格卡片容器。
///
/// 特性：
/// - 内部包含带控制器的横向 `Scrollbar(thumbVisibility: true)`；
/// - 通过 `notificationPredicate` 隔离纵向滚动通知，保证桌面端与触摸端顺畅滑动；
/// - 保持底部统一分页插槽。
class _ScrollableTableCard extends StatefulWidget {
  const _ScrollableTableCard({
    required this.minWidth,
    required this.child,
    this.footer,
  });

  final double minWidth;
  final Widget child;
  final Widget? footer;

  @override
  State<_ScrollableTableCard> createState() => _ScrollableTableCardState();
}

class _ScrollableTableCardState extends State<_ScrollableTableCard> {
  late final ScrollController _hScrollController;

  @override
  void initState() {
    super.initState();
    _hScrollController = ScrollController();
  }

  @override
  void dispose() {
    _hScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Scrollbar(
            controller: _hScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (notif) => notif.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _hScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: widget.minWidth,
                child: widget.child),
            ),
          ),
          if (widget.footer != null) ...[
            Divider(height: 1, color: context.cashier.border),
            widget.footer!,
          ],
        ],
      ),
    );
  }
}

/// 无标题卡片（对齐 SettingsPanel 视觉，但允许自由 padding / 无标题）。
class _LogCard extends StatelessWidget {
  const _LogCard({
    this.padding = const EdgeInsets.all(24),
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.cashier.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cashier.border),
      ),
      child: child,
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.cashier.inkMuted,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _SectionIntro extends StatelessWidget {
  const _SectionIntro({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
      ],
    );
  }
}

class _ArchiveQuotaNote extends StatelessWidget {
  const _ArchiveQuotaNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xffeff6ff),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xffbfdbfe)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: Color(0xff1d4ed8)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '异步任务配额：单门店最多 4 个进行中任务；若排队过多，请等待当前任务完成或联系超管。',
              style: TextStyle(fontSize: 12, color: Color(0xff1e40af)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineDivider extends StatelessWidget {
  const _InlineDivider();

  @override
  Widget build(BuildContext context) {
    return const Center(child: VerticalDivider(width: 1, indent: 4, endIndent: 4),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip({
    required this.pageCount,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final int pageCount;
  final int total;
  final int page;
  final int pageSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '本页 $pageCount 条 · 共 $total 条记录',
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
        const Spacer(),
        Text(
          '每页 $pageSize 条 · 第 $page 页',
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: context.cashier.inkMuted,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// 6. 操作日志表格与设备日志表格
// =====================================================================

class _LogTable extends StatelessWidget {
  const _LogTable({
    required this.rows,
    required this.storeName,
    required this.onDetail,
    required this.footer,
  });

  final List<Map<String, Object?>> rows;
  final String storeName;
  final ValueChanged<Map<String, Object?>> onDetail;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTableCard(
      minWidth: 1110,
      footer: footer,
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(130), // 时间
          1: FixedColumnWidth(95),  // 模块
          2: FixedColumnWidth(80),  // 类型
          3: FixedColumnWidth(200), // 操作
          4: FixedColumnWidth(140), // 对象
          5: FixedColumnWidth(150), // 操作人
          6: FixedColumnWidth(130), // 门店
          7: FixedColumnWidth(105), // 结果
          8: FixedColumnWidth(80),  // 详情
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: context.cashier.row,
              border: const Border(
                bottom: BorderSide(color: Color(0xffd8d8d8), width: 1),
              ),
            ),
            children: [
              _header(context, '时间'),
              _header(context, '模块'),
              _header(context, '类型'),
              _header(context, '操作'),
              _header(context, '对象'),
              _header(context, '操作人'),
              _header(context, '门店'),
              _header(context, '结果'),
              _header(context, '操作'),
            ],
          ),
          ...rows.map(
            (row) => TableRow(
              decoration: BoxDecoration(
                color: context.cashier.surface,
                border: Border(
                  bottom: BorderSide(color: context.cashier.row, width: 1),
                ),
              ),
              children: [
                _cell(
                  context,
                  Text(
                    _timeText(row),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: context.cashier.ink,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Text(_moduleLabel(row), style: const TextStyle(fontSize: 13)),
                ),
                _cell(context, _categoryBadge(context, row)),
                _cell(
                  context,
                  Text(
                    _actionLabel(row),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    _f(row, 'targetId', 'target_id').isEmpty
                        ? '-'
                        : _f(row, 'targetId', 'target_id'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(context, _operatorCell(row)),
                _cell(context, _shopCell(row)),
                _cell(
                  context,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsStatusBadge(
                      label: _resultBadge(row).$2,
                      type: _resultBadge(row).$1,
                    ),
                  ),
                ),
                _cell(
                  context,
                  OutlinedButton(
                    key: Key('log-detail-${_f(row, "id", "id")}'),
                    onPressed: () => onDetail(row),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(54, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('详情', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceLogTable extends StatelessWidget {
  const _DeviceLogTable({
    required this.rows,
    required this.storeName,
    required this.onDetail,
    required this.footer,
  });

  final List<Map<String, Object?>> rows;
  final String storeName;
  final ValueChanged<Map<String, Object?>> onDetail;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return _ScrollableTableCard(
      minWidth: 1100,
      footer: footer,
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(130), // 时间
          1: FixedColumnWidth(140), // 设备模块
          2: FixedColumnWidth(180), // 操作
          3: FixedColumnWidth(330), // 对象 / 说明
          4: FixedColumnWidth(130), // 门店
          5: FixedColumnWidth(105), // 结果
          6: FixedColumnWidth(85),  // 操作
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              color: context.cashier.row,
              border: const Border(
                bottom: BorderSide(color: Color(0xffd8d8d8), width: 1),
              ),
            ),
            children: [
              _header(context, '时间'),
              _header(context, '设备模块'),
              _header(context, '操作'),
              _header(context, '对象 / 说明'),
              _header(context, '门店'),
              _header(context, '结果'),
              _header(context, '操作'),
            ],
          ),
          ...rows.map(
            (row) => TableRow(
              decoration: BoxDecoration(
                color: context.cashier.surface,
                border: Border(
                  bottom: BorderSide(color: context.cashier.row, width: 1),
                ),
              ),
              children: [
                _cell(
                  context,
                  Text(
                    _timeText(row),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: context.cashier.ink,
                    ),
                  ),
                ),
                _cell(context, Text(_moduleLabel(row), style: const TextStyle(fontSize: 13)),
                ),
                _cell(context, Text(_actionLabel(row), style: const TextStyle(fontSize: 13)),
                ),
                _cell(
                  context,
                  Text(
                    _f(row, 'targetId', 'target_id').isEmpty
                        ? '-'
                        : _f(row, 'targetId', 'target_id'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                _cell(
                  context,
                  Text(
                    _f(row, 'shopName', 'shop_name').isEmpty
                        ? storeName
                        : _f(row, 'shopName', 'shop_name'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                _cell(
                  context,
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SettingsStatusBadge(
                      label: _resultBadge(row).$2,
                      type: _resultBadge(row).$1,
                    ),
                  ),
                ),
                _cell(
                  context,
                  OutlinedButton(
                    onPressed: () => onDetail(row),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(54, 30),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('详情', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _header(BuildContext context, String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: context.cashier.inkMuted,
      ),
    ),
  );
}

Widget _cell(BuildContext context, Widget child) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    child: child,
  );
}

/// 兼容新旧接口字段读取：优先新接口 camelCase，回退旧接口 snake_case。
String _f(Map<String, Object?> row, String camel, [String? snake]) {
  final v = row[camel];
  if (v != null && '$v'.trim().isNotEmpty) return '$v';
  if (snake != null) {
    final s = row[snake];
    if (s != null && '$s'.trim().isNotEmpty) return '$s';
  }
  return '';
}

Widget _operatorCell(Map<String, Object?> row) {
  final realName = _f(row, 'realName', 'real_name');
  final displayName = _f(row, 'displayName', 'display_name');
  final opName = _f(row, 'operator_name', 'operatorName');
  final adminName = _f(row, 'adminName', 'userName');
  final id = _f(row, 'adminId', 'admin_id');

  final primaryName = realName.isNotEmpty
      ? realName
      : (displayName.isNotEmpty
          ? displayName
          : (opName.isNotEmpty ? opName : (adminName.isNotEmpty ? adminName : (id.isNotEmpty ? 'ID $id' : '-'))));

  final workNo = _f(row, 'workNo', 'work_no');
  final jobTitle = _f(row, 'jobTitle', 'job_title');

  final subInfoParts = [
    if (workNo.isNotEmpty) workNo,
    if (jobTitle.isNotEmpty) jobTitle,
    if (workNo.isEmpty && jobTitle.isEmpty && adminName.isNotEmpty && adminName != primaryName) adminName,
    if (workNo.isEmpty && jobTitle.isEmpty && id.isNotEmpty && primaryName != 'ID $id') 'ID $id',
  ];

  if (subInfoParts.isEmpty) {
    return Text(
      primaryName,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        primaryName,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 2),
      Text(
        subInfoParts.join(' · '),
        style: const TextStyle(fontSize: 11, color: Color(0xff848484)),
      ),
    ],
  );
}

Widget _shopCell(Map<String, Object?> row) {
  final shopName = _f(row, 'shopName', 'shop_name');
  return Text(
    shopName.isEmpty ? _f(row, 'shopId', 'shop_id') : shopName,
    style: const TextStyle(fontSize: 13),
  );
}

String _moduleLabel(Map<String, Object?> row) {
  final module = _f(row, 'module', 'module').toLowerCase();
  return switch (module) {
    'order' => '订单',
    'cashier' => '收银',
    'cashier_table' => '桌台',
    'member' => '会员',
    'report' => '报表',
    'security' => '权限',
    'kds' => 'KDS 厨显',
    'printing' => '打印',
    'pos' => '收银 POS',
    'auth' || 'login' => '登录',
    _ => module.isEmpty ? '-' : module,
  };
}

String _categoryLabel(Map<String, Object?> row) {
  final category = _f(row, 'category', 'category').toLowerCase();
  return switch (category) {
    'business' => '业务',
    'security' => '安全',
    'system' => '系统',
    _ => category.isEmpty ? '-' : category,
  };
}

Widget _categoryBadge(BuildContext context, Map<String, Object?> row) {
  final label = _categoryLabel(row);
  final category = _f(row, 'category', 'category').toLowerCase();
  final (textColor, bgColor) = switch (category) {
    'business' => (const Color(0xff0369a1), const Color(0xffe0f2fe)),
    'security' => (const Color(0xffb45309), const Color(0xfffef3c7)),
    'system' => (const Color(0xff6d28d9), const Color(0xffede9fe)),
    _ => (context.cashier.inkMuted, context.cashier.row),
  };

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: bgColor,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: textColor,
      ),
    ),
  );
}

String _actionLabel(Map<String, Object?> row) {
  final action = _f(row, 'action', 'action');
  final reason = _f(row, 'reason', 'reason');
  final code = switch (action) {
    'OPEN' => '开台',
    'CLEAR' => '清台',
    'force_delete' => '强删订单',
    'cashier_order_create' => '创建订单',
    'cashier_refund_dish' => '退菜退款',
    'admin_member_recharge' => '会员充值',
    'api_permission_updated' => '接口权限更新',
    'create_export' => '创建导出',
    _ => action,
  };
  return reason.isEmpty ? code : '$code · $reason';
}

/// 执行结果徽标：resultStatus（SUCCESS / FAILED / 其他）→ (类型, 文案)。
(StatusBadgeType, String) _resultBadge(Map<String, Object?> row) {
  final status = _f(row, 'resultStatus', 'result_status').toUpperCase();
  return switch (status) {
    'SUCCESS' => (StatusBadgeType.success, '成功'),
    'FAILED' || 'FAILURE' || 'ERROR' => (StatusBadgeType.danger, '失败'),
    'PENDING' || 'RUNNING' => (StatusBadgeType.warning, status),
    _ => status.isEmpty ? (StatusBadgeType.neutral, '-') : (StatusBadgeType.warning, status),
  };
}

/// 列表时间：ISO8601 / 数据库时间 → `MM-dd HH:mm`。
String _timeText(Map<String, Object?> row) {
  final raw = _f(row, 'createdAt', 'created_at');
  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
  }
  if (raw.length >= 16) return raw.substring(5, 16);
  return raw;
}

/// 详情时间：完整格式化。
String _fullTime(Map<String, Object?> row) {
  final raw = _f(row, 'createdAt', 'created_at');
  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    return _fullTimeDirect(parsed);
  }
  return raw;
}

String _fullTimeDirect(DateTime parsed) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)} '
      '${two(parsed.hour)}:${two(parsed.minute)}:${two(parsed.second)}';
}

String _dateOnlyDirect(DateTime parsed) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${parsed.year}-${two(parsed.month)}-${two(parsed.day)}';
}

String _timeDirect(DateTime parsed) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(parsed.month)}-${two(parsed.day)} ${two(parsed.hour)}:${two(parsed.minute)}';
}

/// JSON 字符串 → 格式化多行文本（失败时原样返回）。
String _jsonPretty(Object? raw) {
  final text = '$raw'.trim();
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(decoded);
  } catch (_) {
    return text;
  }
}

// =====================================================================
// 7. 三级详情弹窗：日志详情、归档任务详情、导出记录详情
// =====================================================================

class _LogDetailDialog extends StatefulWidget {
  const _LogDetailDialog({required this.row, required this.storeName});

  final Map<String, Object?> row;
  final String storeName;

  @override
  State<_LogDetailDialog> createState() => _LogDetailDialogState();
}

class _LogDetailDialogState extends State<_LogDetailDialog> {
  int _activeSnapshotTab = 0;
  final ScrollController _contentVScroll = ScrollController();
  final ScrollController _snapshotVScroll = ScrollController();
  final ScrollController _snapshotHScroll = ScrollController();

  @override
  void dispose() {
    _contentVScroll.dispose();
    _snapshotVScroll.dispose();
    _snapshotHScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final realName = _f(row, 'realName', 'real_name');
    final displayName = _f(row, 'displayName', 'display_name');
    final opName = _f(row, 'operator_name', 'operatorName');
    final adminName = _f(row, 'adminName', 'userName');
    final operatorId = _f(row, 'adminId', 'admin_id');
    final workNo = _f(row, 'workNo', 'work_no');
    final jobTitle = _f(row, 'jobTitle', 'job_title');

    final name = realName.isNotEmpty
        ? realName
        : (displayName.isNotEmpty ? displayName : (opName.isNotEmpty ? opName : adminName));
    final operatorText = [
      if (name.isNotEmpty) name,
      if (jobTitle.isNotEmpty) '[$jobTitle]',
      if (workNo.isNotEmpty) '($workNo)',
      if (operatorId.isNotEmpty && operatorId != name) 'ID $operatorId',
    ].join(' ');
    final shopName = _f(row, 'shopName', 'shop_name');
    final shopText = shopName.isNotEmpty
        ? shopName
        : (_f(row, 'shopId', 'shop_id').isEmpty ? widget.storeName : _f(row, 'shopId', 'shop_id'));
    final traceId = _f(row, 'traceId', 'trace_id');
    final resultCode = _f(row, 'resultCode', 'result_code');
    final (resultType, resultLabel) = _resultBadge(row);
    final reasonText = _f(row, 'reason', 'reason');
    final idText = _f(row, 'id', 'id');
    final ipText = _f(row, 'ip', 'ip');

    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.78).clamp(520.0, 840.0);
    final maxHeight = size.height * 0.86;

    final requestJson = _f(row, 'requestSnapshot', 'request_snapshot');
    final beforeJson = _f(row, 'beforeState', 'before_state');
    final afterJson = _f(row, 'afterState', 'after_state');

    final (activeRaw, activeLabel, activeHint) = switch (_activeSnapshotTab) {
      1 => (beforeJson, '变更前 beforeState', '（无变更前数据，可能为新建操作）'),
      2 => (afterJson, '变更后 afterState', '（无变更后数据，可能为删除操作）'),
      _ => (requestJson, '请求快照 requestSnapshot', '（无请求快照数据）'),
    };

    return AlertDialog(
      backgroundColor: context.cashier.surface,
      surfaceTintColor: context.cashier.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.receipt_long_outlined, size: 22),
          const SizedBox(width: 8),
          const Text('操作日志详情', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          _categoryBadge(context, row),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: maxHeight,
        child: Scrollbar(
          controller: _contentVScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _contentVScroll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 元数据网格
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.cashier.row,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.cashier.border),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _dialogPair(
                              context,
                              '时间',
                              _fullTime(row)),
                          ),
                          Expanded(
                            child: _dialogPair(
                              context,
                              '模块 / 动作',
                              '${_moduleLabel(row)} / ${_actionLabel(row)}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _dialogPair(
                              context,
                              '操作对象',
                              _f(row, 'targetId', 'target_id').isEmpty ? '-' : _f(row, 'targetId', 'target_id'),
                            ),
                          ),
                          Expanded(
                            child: _dialogPair(
                              context,
                              '操作人',
                              operatorText.isEmpty ? '-' : operatorText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _dialogPair(
                              context,
                              '所属门店',
                              shopText),
                          ),
                          Expanded(
                            child: _dialogPair(
                              context,
                              '客户端 IP',
                              ipText.isEmpty ? '-' : ipText,
                              mono: true,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _dialogPair(
                              context,
                              '记录 ID',
                              idText.isEmpty ? '-' : idText,
                              mono: true,
                            ),
                          ),
                          Expanded(
                            child: _dialogPair(
                              context,
                              '追踪 ID',
                              traceId.isEmpty ? '-' : traceId,
                              mono: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. 执行结果卡片
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: resultType == StatusBadgeType.danger
                        ? const Color(0xfffef2f2)
                        : (resultType == StatusBadgeType.success
                            ? const Color(0xfff0fdf4)
                            : context.cashier.row),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: resultType == StatusBadgeType.danger
                          ? const Color(0xfffecaca)
                          : (resultType == StatusBadgeType.success
                              ? const Color(0xffbbf7d0)
                              : context.cashier.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      SettingsStatusBadge(label: resultLabel, type: resultType),
                      if (resultCode.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Text(
                          'code $resultCode',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            color: context.cashier.inkMuted,
                          ),
                        ),
                      ],
                      if (reasonText.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            reasonText,
                            style: TextStyle(
                              fontSize: 13,
                              color: resultType == StatusBadgeType.danger
                                  ? const Color(0xffb91c1c)
                                  : context.cashier.ink,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 3. 数据快照（切换卡片）
                Row(
                  children: [
                    const Text(
                      '数据快照与状态变更',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('请求快照')),
                        ButtonSegment(value: 1, label: Text('变更前')),
                        ButtonSegment(value: 2, label: Text('变更后')),
                      ],
                      selected: {_activeSnapshotTab},
                      onSelectionChanged: (set) {
                        setState(() => _activeSnapshotTab = set.first);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // 双向滑动代码查看器
                _buildSnapshotViewer(
                  context,
                  label: activeLabel,
                  rawJson: activeRaw,
                  emptyHint: activeHint,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final summary = [
              '【操作日志摘要】',
              'ID: $idText',
              '时间: ${_fullTime(row)}',
              '模块/动作: ${_moduleLabel(row)} / ${_actionLabel(row)}',
              '操作人: $operatorText',
              '门店: $shopText',
              '对象: ${_f(row, "targetId", "target_id")}',
              '结果: $resultLabel ${resultCode.isNotEmpty ? "($resultCode)" : ""}',
              if (reasonText.isNotEmpty) '原因: $reasonText',
              if (traceId.isNotEmpty) '追踪ID: $traceId',
            ].join('\n');
            await Clipboard.setData(ClipboardData(text: summary));
            if (context.mounted) {
              showSettingsSaved(context, '已复制日志摘要');
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('复制日志摘要'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _dialogPair(BuildContext context, String k, String v, {bool mono = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 75,
            child: Text(
              k,
              style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
            ),
          ),
          Expanded(
            child: SelectableText(
              v.isEmpty ? '-' : v,
              style: TextStyle(
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: mono ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshotViewer(
    BuildContext context, {
    required String label,
    required String rawJson,
    required String emptyHint,
  }) {
    final pretty = _jsonPretty(rawJson);
    if (pretty.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.cashier.row,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.cashier.border),
        ),
        child: Text(
          emptyHint,
          style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff0b1220),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xff1f293d))),
            ),
            child: Row(
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xff94a3b8),
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: rawJson));
                    if (context.mounted) {
                      showSettingsSaved(context, '已复制 JSON 数据');
                    }
                  },
                  icon: const Icon(Icons.copy_rounded, size: 14, color: Color(0xff38bdf8),
                  ),
                  label: const Text('复制 JSON', style: TextStyle(fontSize: 12, color: Color(0xff38bdf8)),
                  ),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 26),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: Scrollbar(
              controller: _snapshotVScroll,
              thumbVisibility: true,
              child: Scrollbar(
                controller: _snapshotHScroll,
                thumbVisibility: true,
                notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
                child: SingleChildScrollView(
                  controller: _snapshotVScroll,
                  child: SingleChildScrollView(
                    controller: _snapshotHScroll,
                    scrollDirection: Axis.horizontal,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        pretty,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.5,
                          color: Color(0xffe2e8f0),
                        ),
                      ),
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
}

class _ArchiveJobDetailDialog extends StatelessWidget {
  const _ArchiveJobDetailDialog({
    required this.job,
    required this.onRefresh});

  final _ArchiveJob job;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.72).clamp(480.0, 680.0);
    final (badgeType, badgeLabel) = switch (job.status) {
      'DONE' => (StatusBadgeType.success, '已完成'),
      'FAILED' => (StatusBadgeType.danger, '失败'),
      'RUNNING' => (StatusBadgeType.warning, '检索中'),
      'PENDING' => (StatusBadgeType.info, '排队中'),
      _ => (StatusBadgeType.neutral, job.status),
    };
    final timeRangeStr = job.start == null || job.end == null
        ? '全部历史时间'
        : '${_dateOnlyDirect(job.start!)} 至 ${_dateOnlyDirect(job.end!)}';

    Widget metaItem(String label, String value, {bool mono = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
              ),
            ),
            Expanded(
              child: SelectableText(
                value.isEmpty ? '-' : value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: mono ? 'monospace' : null,
                  color: context.cashier.ink,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      backgroundColor: context.cashier.surface,
      surfaceTintColor: context.cashier.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.archive_outlined, size: 20),
          const SizedBox(width: 8),
          const Text('归档检索任务详情', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          SettingsStatusBadge(label: badgeLabel, type: badgeType),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cashier.row,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.cashier.border),
                ),
                child: Column(
                  children: [
                    metaItem('任务编号', '#${job.jobId}', mono: true),
                    metaItem('检索模块', job.module),
                    metaItem('检索动作', job.action),
                    metaItem('指定操作人', job.operator),
                    metaItem('检索时间跨度', timeRangeStr),
                    metaItem('提交时间', _fullTimeDirect(job.createdAt)),
                    metaItem('结果摘要', job.summary.isEmpty ? '（暂无摘要）' : job.summary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xffeff6ff),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xffbfdbfe)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 18, color: Color(0xff1d4ed8),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '在线 30 天以上的日志存储于归档冷存储中（最终保留 1 年）。任务完成后，结果可在服务端审计归档中留档，或联系系统管理员提取原始文件。',
                        style: TextStyle(fontSize: 12, color: Color(0xff1e40af), height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            onRefresh();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('刷新状态'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

class _ExportRecordDetailDialog extends StatelessWidget {
  const _ExportRecordDetailDialog({required this.record});

  final _ExportRecord record;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = (size.width * 0.72).clamp(480.0, 680.0);
    final timeRangeStr = record.start == null || record.end == null
        ? '全部历史时间'
        : '${_dateOnlyDirect(record.start!)} 至 ${_dateOnlyDirect(record.end!)}';

    Widget metaItem(String label, String value, {bool mono = false, Widget? suffix,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 100,
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: context.cashier.inkMuted),
              ),
            ),
            Expanded(
              child: SelectableText(
                value.isEmpty ? '-' : value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: mono ? 'monospace' : null,
                  color: context.cashier.ink,
                ),
              ),
            ),
            if (suffix != null) suffix,
          ],
        ),
      );
    }

    return AlertDialog(
      backgroundColor: context.cashier.surface,
      surfaceTintColor: context.cashier.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.download_done_rounded, size: 20),
          const SizedBox(width: 8),
          const Text('日志导出审计详情', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 10),
          const SettingsStatusBadge(label: '已提交', type: StatusBadgeType.success,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.cashier.row,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: context.cashier.border),
                ),
                child: Column(
                  children: [
                    metaItem(
                      '审计编号',
                      record.auditNo,
                      mono: true,
                      suffix: IconButton(
                        tooltip: '复制审计编号',
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24,
                        ),
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: record.auditNo),
                          );
                          if (context.mounted) {
                            showSettingsSaved(context, '已复制审计编号：${record.auditNo}',
                            );
                          }
                        },
                      ),
                    ),
                    metaItem('任务编号', '#${record.jobId}', mono: true),
                    metaItem('导出模块', record.module),
                    metaItem('导出用途', record.purpose),
                    metaItem('数据时间范围', timeRangeStr),
                    metaItem('提交时间', _fullTimeDirect(record.createdAt)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xfffef3c7),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xfffde68a)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.security_outlined, size: 18, color: Color(0xffb45309),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '合规说明：导出脱敏日志用于外部合规审计；此导出行为已写入系统全局操作审计日志，审计编号将永久留存。',
                        style: TextStyle(fontSize: 12, color: Color(0xff92400e), height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: record.auditNo));
            if (context.mounted) {
              showSettingsSaved(context, '已复制审计编号：${record.auditNo}');
            }
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('复制审计编号'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

// =====================================================================
// 8. 选项与工具方法
// =====================================================================

Widget _drop(
  String value,
  List<(String, String)> options,
  ValueChanged<String> onChanged, {
  double width = 150,
  String allLabel = '全部',
}) {
  return SizedBox(
    width: width,
    child: DropdownButton<String>(
      value: value.isEmpty ? null : value,
      isExpanded: true,
      hint: Text(allLabel),
      items: [
        DropdownMenuItem<String>(value: null, child: Text(allLabel)),
        ...options.map(
          (o) => DropdownMenuItem<String>(value: o.$1, child: Text(o.$2)),
        ),
      ],
      onChanged: (v) => onChanged(v ?? ''),
    ),
  );
}

/// 筛选下拉选项：值（接口 code）+ 中文标签。
const _moduleOptions = <(String, String)>[
  ('order', '订单'),
  ('cashier', '收银'),
  ('cashier_table', '桌台'),
  ('member', '会员'),
  ('report', '报表'),
  ('security', '权限'),
  ('kds', 'KDS 厨显'),
  ('printing', '打印'),
  ('pos', '收银 POS'),
];

const _categoryOptions = <(String, String)>[
  ('business', '业务'),
  ('security', '安全'),
  ('all', '全部'),
];

const _actionOptions = <(String, String)>[
  ('OPEN', '开台'),
  ('CLEAR', '清台'),
  ('force_delete', '强删订单'),
  ('cashier_order_create', '创建订单'),
  ('cashier_refund_dish', '退菜退款'),
  ('admin_member_recharge', '会员充值'),
  ('api_permission_updated', '接口权限更新'),
  ('create_export', '创建导出'),
];

int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

String _s(Object? value) => value == null ? '' : '$value';

Map<String, Object?> _asMap(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};
