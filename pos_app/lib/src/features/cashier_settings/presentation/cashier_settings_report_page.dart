import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/crash_log.dart';
import '../../../core/api_contract.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import 'cashier_settings_shared.dart';

/// 设置页 · 数据报表（替换原 SettingsPrototypePage 占位）。
///
/// 数据口径一律来自 openapi.yaml（禁止 mock）：
/// - 数据看板：`/admin/analytics/business`、`/admin/analytics/business/trend`、`/admin/analytics/dishes`
/// - 导出任务：`/admin/reports/exports`（POST 创建 / GET 列表）、`/admin/reports/exports/{id}/download`
/// - 结算日设置：口径说明（结算窗口为 settle_time 前 12 小时，门店配置优先、默认截止 04:00）
class CashierSettingsReportPage extends StatefulWidget {
  const CashierSettingsReportPage({
    super.key,
    required this.client,
    required this.section,
    required this.storeName,
    this.currentShopId,
  });

  final AdminApiClient? client;
  final SettingsSectionSpec section;
  final String storeName;
  final int? currentShopId;

  @override
  State<CashierSettingsReportPage> createState() =>
      _CashierSettingsReportPageState();
}

class _CashierSettingsReportPageState extends State<CashierSettingsReportPage> {
  // ---------------- 看板状态 ----------------
  String _range = '7d'; // auto / today / yesterday / 7d / month / custom
  String _dim = 'business'; // natural / business
  String _gran = 'day'; // day / week / month / year
  late DateTime _start;
  late DateTime _end;
  bool _dashboardLoading = true;
  Object? _dashboardError;
  Map<String, Object?> _analytics = const {};
  Map<String, Object?> _trend = const {};
  List<Map<String, Object?>> _dishes = const [];

  // ---------------- 导出状态 ----------------
  String _reportType = 'daily'; // daily / weekly / monthly
  static const _exportFormat = 'csv';
  DateTime? _exportStart;
  DateTime? _exportEnd;
  bool _jobsLoading = true;
  bool _creating = false;
  Object? _jobsError;
  List<Map<String, Object?>> _jobs = const [];
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day - 6);
    _end = now;
    _exportStart = DateTime(now.year, now.month, now.day - 6);
    _exportEnd = now;
    _load();
  }

  @override
  void didUpdateWidget(covariant CashierSettingsReportPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section.id != widget.section.id ||
        oldWidget.client != widget.client) {
      _load();
    }
  }

  void _load() {
    if (widget.section.id == 'catalog') {
      _loadDashboard();
    } else if (widget.section.id == 'exports') {
      _loadJobs();
    }
  }

  // ================= 数据加载 =================

  /// 完整时间（自定义窗口用，含时分秒，后端精确保留）。
  String _fmt(DateTime t) => _fmtDateTime(t);

  /// 纯年月日（快捷预设用）：营业日截止时间由后端按门店 settle_time 自动补全
  /// （v1.2.280 契约：今日/昨日/近7天/近30天只传年月日）。
  String _fmtDate(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

  /// startTime/endTime 可选。默认态（auto）不传，由后端返回最近已完成
  /// 结算日的 [settle_time - 12h, settle_time) 窗口。
  bool get _useAutoWindow => _range == 'auto';

  Map<String, Object?> get _windowQuery {
    if (_useAutoWindow) return const {};
    if (_range == 'custom') {
      // 自定义时间：保留时分秒，精确保留用户输入区间。
      return {'startTime': _fmt(_start), 'endTime': _fmt(_end)};
    }
    // 快捷预设（今日/昨日/近7天/近30天）：仅传年月日，
    // 后端按营业日截止时间（settle_time）自动补全窗口。
    return {'startTime': _fmtDate(_start), 'endTime': _fmtDate(_end)};
  }

  /// 默认结算窗口（约 12h）不足以绘制日趋势；趋势请求仅传 6 天前的
  /// startTime（年月日），结束时间仍由后端解析为最近已完成结算日，得到连续的近 7 日数据。

  Map<String, Object?> get _trendWindow {
    if (!_useAutoWindow) return _windowQuery;
    final now = DateTime.now();
    return {
      'startTime': _fmtDate(DateTime(now.year, now.month, now.day - 6)),
    };
  }

  Future<void> _loadDashboard() async {
    final client = widget.client;
    if (client == null) return;
    setState(() {
      _dashboardLoading = true;
      _dashboardError = null;
    });
    try {
      final api = client.copyWith(shopId: widget.currentShopId);
      final window = _windowQuery;
      final results = await Future.wait<Object?>([
        api.get(analyticsBusinessEndpoint, query: window),
        api.get(
          analyticsBusinessTrendEndpoint,
          query: {..._trendWindow, 'granularity': _gran},
        ),
        api.get(analyticsDishesEndpoint, query: {...window, 'limit': 10}),
      ]);
      if (!mounted) return;
      setState(() {
        _analytics = _asMap(results[0]);
        _trend = _asMap(results[1]);
        _dishes = objectList(_asMap(results[2])['dishes']);
        _dashboardLoading = false;
      });
      CrashLog.instance.recordOperation(
        '报表·看板加载完成: 窗口=${_useAutoWindow ? 'recent-completed-settlement' : '${_fmt(_start)}~${_fmt(_end)}'} '
        '口径=$_dim 粒度=$_gran',
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _dashboardError = error;
        _dashboardLoading = false;
      });
      CrashLog.instance.write(
        'ERROR',
        '报表·看板加载失败: $error',
        stackTrace,
      );
    }
  }

  Future<void> _loadJobs() async {
    final client = widget.client;
    if (client == null) return;
    setState(() {
      _jobsLoading = true;
      _jobsError = null;
    });
    try {
      final data = await client.copyWith(shopId: widget.currentShopId).get(
        settingsReportExportsEndpoint,
        query: const {
          'jobType': 'REPORT_EXPORT',
          'page': 1,
          'pageSize': 20,
        },
      );
      if (!mounted) return;
      setState(() {
        _jobs = objectList(data);
        _jobsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _jobsError = error;
        _jobsLoading = false;
      });
    }
  }

  Future<void> _createJob() async {
    final client = widget.client;
    final start = _exportStart;
    if (client == null || start == null || _creating) return;
    final end = _exportEnd;
    if (_reportType != 'daily' && end == null) {
      _showMessage('周报和月报必须选择结束日期');
      return;
    }
    if (end != null && end.isBefore(start)) {
      _showMessage('结束日期不能早于开始日期');
      return;
    }
    if (_reportType != 'daily' && end!.difference(start).inDays + 1 > 92) {
      _showMessage('导出日期范围含首尾最多 92 天');
      return;
    }
    setState(() => _creating = true);
    try {
      final filters = <String, Object?>{
        if (_reportType == 'daily') 'date': _dateOnly(start),
        if (_reportType != 'daily') ...{
          'startDate': _dateOnly(start),
          if (_exportEnd != null) 'endDate': _dateOnly(_exportEnd!),
        },
      };
      await client.copyWith(shopId: widget.currentShopId).post(
            settingsReportExportCreateEndpoint,
            body: {
              'reportType': _reportType,
              'filters': filters,
              'format': _exportFormat,
            },
          );
      if (!mounted) return;
      setState(() => _creating = false);
      _showMessage('导出任务已创建，排队生成中');
      _loadJobs();
    } catch (error) {
      if (!mounted) return;
      setState(() => _creating = false);
      _showMessage(_exportErrorMessage(error));
    }
  }

  Future<void> _downloadJob(Map<String, Object?> job) async {
    final client = widget.client;
    if (client == null || _downloading) return;
    final url = _s(job['downloadUrl']);
    if (url.isEmpty) {
      _showMessage('下载链接已过期，请重新创建导出任务');
      return;
    }
    setState(() => _downloading = true);
    try {
      final uri = Uri.parse(url).hasScheme
          ? Uri.parse(url)
          : Uri.parse(client.baseUrl).resolve(url);
      final response = await http.get(uri).timeout(
        const Duration(seconds: 60),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode == 410) throw '下载链接已过期，请重新创建导出任务';
        if (response.statusCode == 404) throw '导出文件已被清理，请重新创建导出任务';
        throw '下载失败（HTTP ${response.statusCode}）';
      }
      final dir = await getDownloadsDirectory();
      if (dir == null) throw '未找到下载目录';
      final id = _s(job['jobId'] ?? job['id']).replaceAll(RegExp(r'[^\d]'), '');
      const ext = _exportFormat;
      final file = File('${dir.path}${Platform.pathSeparator}'
          'laofei-export-$id.$ext');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      if (!mounted) return;
      setState(() => _downloading = false);
      _showMessage('已保存到 ${file.path}');
    } catch (error) {
      if (!mounted) return;
      setState(() => _downloading = false);
      _showMessage('下载失败：$error');
    }
  }

  // ================= 工具 =================

  Map<String, Object?> _asMap(Object? value) =>
      value is Map ? value.cast<String, Object?>() : const {};

  String _dateOnly(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)}';
  }

  String _exportErrorMessage(Object error) {
    final value = '$error';
    if (value.contains('REPORT_RANGE_REQUIRED')) return '请选择完整的导出日期范围';
    if (value.contains('REPORT_RANGE_INVALID')) return '日期范围无效，含首尾最多 92 天';
    if (value.contains('REPORT_JOB_QUOTA_EXCEEDED')) return '未完成导出任务已达配额，请等待任务完成后再试';
    if (value.contains('REPORT_WORKER_CLOSED')) return '导出服务正在维护，请稍后重试';
    return '创建导出任务失败：$value';
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));
  }

  // ================= 渲染 =================

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    if (client == null) {
      return const SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            '暂无报表访问权限',
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }
    return switch (widget.section.id) {
      'catalog' => _DashboardView(
          loading: _dashboardLoading,
          error: _dashboardError,
          range: _range,
          dim: _dim,
          gran: _gran,
          start: _start,
          end: _end,
          analytics: _analytics,
          trend: _trend,
          dishes: _dishes,
          onSelectRange: _selectRange,
          onSelectDim: _selectDim,
          onSelectGran: _selectGran,
          onPickDate: _pickCustomDate,
          onReload: _loadDashboard,
        ),
      'exports' => _ExportsView(
          loading: _jobsLoading,
          creating: _creating,
          downloading: _downloading,
          error: _jobsError,
          reportType: _reportType,
          exportStart: _exportStart,
          exportEnd: _exportEnd,
          jobs: _jobs,
          onTypeChanged: (v) => setState(() => _reportType = v),
          onPickStart: () => _pickExportDate(isStart: true),
          onPickEnd: () => _pickExportDate(isStart: false),
          onCreate: _createJob,
          onDownload: _downloadJob,
          onReload: _loadJobs,
        ),
      _ => const _BusinessDayView(),
    };
  }

  void _selectRange(String range) {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;
    switch (range) {
      case 'auto':
        start = DateTime(now.year, now.month, now.day);
      case 'yesterday':
        start = DateTime(now.year, now.month, now.day - 1);
        end = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
      case '7d':
        start = DateTime(now.year, now.month, now.day - 6);
      case 'month':
        start = DateTime(now.year, now.month, 1);
      default:
        start = DateTime(now.year, now.month, now.day);
    }
    setState(() {
      _range = range;
      _start = start;
      _end = end;
    });
    CrashLog.instance.recordOperation('报表·选择时间窗: $range');
    _loadDashboard();
  }

  void _selectDim(String dim) {
    setState(() => _dim = dim);
    CrashLog.instance.recordOperation('报表·切换口径: $dim');
    _loadDashboard();
  }

  void _selectGran(String gran) {
    setState(() => _gran = gran);
    CrashLog.instance.recordOperation('报表·切换粒度: $gran');
    _loadDashboard();
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDialog<DateTimeRange>(
      context: context,
      builder: (ctx) => _CustomDateTimeRangeDialog(
        initialStart: _start,
        initialEnd: _end,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _range = 'custom';
      _start = picked.start;
      _end = picked.end;
    });
    CrashLog.instance.recordOperation(
      '报表·自定义时间窗: ${_fmtDateTime(_start)} ~ ${_fmtDateTime(_end)}',
    );
    _loadDashboard();
  }

  Future<void> _pickExportDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_exportStart ?? now) : (_exportEnd ?? now),
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: isStart ? '选择开始日期' : '选择结束日期',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _exportStart = picked;
        if (_exportEnd == null || _exportEnd!.isBefore(picked)) {
          _exportEnd = picked;
        }
      } else {
        _exportEnd = picked;
        if (_exportStart == null || _exportStart!.isAfter(picked)) {
          _exportStart = picked;
        }
      }
    });
  }
}

// ============================================================
// 数据看板
// ============================================================

class _DashboardView extends StatelessWidget {
  const _DashboardView({
    required this.loading,
    required this.error,
    required this.range,
    required this.dim,
    required this.gran,
    required this.start,
    required this.end,
    required this.analytics,
    required this.trend,
    required this.dishes,
    required this.onSelectRange,
    required this.onSelectDim,
    required this.onSelectGran,
    required this.onPickDate,
    required this.onReload,
  });

  final bool loading;
  final Object? error;
  final String range;
  final String dim;
  final String gran;
  final DateTime start;
  final DateTime end;
  final Map<String, Object?> analytics;
  final Map<String, Object?> trend;
  final List<Map<String, Object?>> dishes;
  final ValueChanged<String> onSelectRange;
  final ValueChanged<String> onSelectDim;
  final ValueChanged<String> onSelectGran;
  final VoidCallback onPickDate;
  final VoidCallback onReload;

  String get _rangeLabel {
    String d(DateTime t) => '${t.month}/${t.day}';
    switch (range) {
      case 'auto':
        return '最近已完成结算日（自动）';
      case 'yesterday':
        return '昨日';
      case '7d':
        return '近7天 ${d(start)}~${d(end)}';
      case 'month':
        return '本月';
      case 'custom':
        return '${_fmtDateTime(start)} ~ ${_fmtDateTime(end)}';
      default:
        return '今日';
    }
  }

  @override
  Widget build(BuildContext context) {
    final core = _map(analytics['core']);
    final derived = _map(
      analytics[dim == 'business' ? 'business_day' : 'natural_calendar'],
    );
    final derivedInner = _map(derived['derived']);
    final slots = objectList(
      analytics[dim == 'business'
          ? 'time_slots_business_anchor'
          : 'time_slots_natural_clock'],
    );
    final hourly = objectList(
      analytics[dim == 'business'
          ? 'time_slots_business_hourly'
          : 'time_slots_hourly'],
    );
    final payments = objectList(analytics['payment_channels']);
    final trendSeries = _map(
      trend[dim == 'business' ? 'business_day' : 'natural_calendar'],
    );
    final points = objectList(trendSeries['series']);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WindowBar(
            range: range,
            dim: dim,
            gran: gran,
            rangeLabel: _rangeLabel,
            onSelectRange: onSelectRange,
            onSelectDim: onSelectDim,
            onSelectGran: onSelectGran,
            onPickDate: onPickDate,
          ),
          const SizedBox(height: 16),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            _ErrorCard(message: '$error', onRetry: onReload)
          else ...[
            _MetricGrid(
              core: core,
              derived: derivedInner,
              dim: dim,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;
                final trendPanel = _Panel(
                  title: '营业趋势',
                  tag: '${dim == 'business' ? '营业日' : '自然日'} · '
                      '按${gran == 'day' ? '日' : gran == 'week' ? '周' : gran == 'month' ? '月' : '年'} · '
                      '${range == 'auto' ? '近7天' : _rangeLabel}',
                  child: points.isEmpty
                      ? const _EmptyHint(text: '当前时间窗无趋势数据')
                      : _TrendChart(
                          points: points
                              .map(
                                (p) => _TrendPoint(
                                  label: _s(p['bucket_label']),
                                  net: _d(p['net_revenue']),
                                  orders: _i(p['order_count']),
                                ),
                              )
                              .toList(),
                        ),
                );
                final slotPanel = _SlotPanel(
                  slots: slots,
                  hourly: hourly,
                  payments: payments,
                  dim: dim,
                );
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: trendPanel),
                      const SizedBox(width: 16),
                      Expanded(child: slotPanel),
                    ],
                  );
                }
                return Column(
                  children: [
                    trendPanel,
                    const SizedBox(height: 16),
                    slotPanel,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _Panel(
              title: '菜品销售 TOP${dishes.isEmpty ? '' : '${dishes.length > 10 ? 10 : dishes.length}'}',
              tag: '销售额排行 · 毛利档 · 动销标签',
              child: dishes.isEmpty
                  ? const _EmptyHint(text: '当前时间窗无菜品数据')
                  : _DishTable(dishes: dishes.take(10).toList()),
            ),
            const SizedBox(height: 16),
            const _EntryGrid(),
          ],
        ],
      ),
    );
  }
}

class _WindowBar extends StatelessWidget {
  const _WindowBar({
    required this.range,
    required this.dim,
    required this.gran,
    required this.rangeLabel,
    required this.onSelectRange,
    required this.onSelectDim,
    required this.onSelectGran,
    required this.onPickDate,
  });

  final String range;
  final String dim;
  final String gran;
  final String rangeLabel;
  final ValueChanged<String> onSelectRange;
  final ValueChanged<String> onSelectDim;
  final ValueChanged<String> onSelectGran;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final entry in const [
          ('auto', '最近结算日（默认）'),
          ('today', '今日'),
          ('yesterday', '昨日'),
          ('7d', '近7天'),
          ('month', '本月'),
        ])
          _Chip(
            label: entry.$2,
            selected: range == entry.$1,
            onTap: () => onSelectRange(entry.$1),
          ),
        _Chip(
          label: '自定义',
          selected: range == 'custom',
          onTap: onPickDate,
        ),
        _Segmented(
          options: const [('natural', '自然日'), ('business', '营业日')],
          selected: dim,
          onSelected: onSelectDim,
        ),
        _Segmented(
          options: const [
            ('day', '按日'),
            ('week', '按周'),
            ('month', '按月'),
            ('year', '按年'),
          ],
          selected: gran,
          onSelected: onSelectGran,
        ),
        InkWell(
          onTap: onPickDate,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '时间窗：$rangeLabel',
                  style: TextStyle(
                    color: range == 'custom'
                        ? context.cashier.selected
                        : context.cashier.inkMuted,
                    fontSize: 13,
                    fontWeight:
                        range == 'custom' ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (range == 'custom') ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.edit_calendar_outlined,
                    size: 15,
                    color: context.cashier.selected,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? tokens.selectedBackground : tokens.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? tokens.selected : tokens.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? tokens.selected : tokens.inkSecondary,
            fontSize: 14,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<(String, String)> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++)
            InkWell(
              onTap: () => onSelected(options[i].$1),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected == options[i].$1
                      ? tokens.selectedBackground
                      : Colors.transparent,
                  borderRadius: BorderRadius.only(
                    topLeft: i == 0 ? const Radius.circular(9) : Radius.zero,
                    bottomLeft: i == 0 ? const Radius.circular(9) : Radius.zero,
                    topRight: i == options.length - 1
                        ? const Radius.circular(9)
                        : Radius.zero,
                    bottomRight: i == options.length - 1
                        ? const Radius.circular(9)
                        : Radius.zero,
                  ),
                ),
                child: Text(
                  options[i].$2,
                  style: TextStyle(
                    color: selected == options[i].$1
                        ? tokens.selected
                        : tokens.inkSecondary,
                    fontSize: 14,
                    fontWeight: selected == options[i].$1
                        ? FontWeight.w600
                        : FontWeight.w400,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.core, required this.derived, required this.dim});

  final Map<String, Object?> core;
  final Map<String, Object?> derived;
  final String dim;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    double d(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final metrics = <(String, String, String)>[
      ('净收入（元）', _fmtAmountFull(d(core['net_revenue'])), '仅成功单'),
      ('订单数', '${i(core['order_count'])}', '含堂食 / 外卖'),
      ('客单价（元）', _fmtAmountFull(d(derived['avg_ticket'])), '净收入 ÷ 订单'),
      (
        '退款率',
        d(derived['refund_rate_on_gross']) == 0
            ? '—'
            : '${(d(derived['refund_rate_on_gross']) * 100).toStringAsFixed(1)}%',
        '按毛额',
      ),
      (
        '翻台率',
        d(derived['table_turnover_per_table_per_day']) == 0
            ? '—'
            : d(derived['table_turnover_per_table_per_day']).toStringAsFixed(2),
        '次 / 桌 / 日',
      ),
      (
        '上座率',
        d(derived['seat_occupancy_rate']) == 0
            ? '—'
            : '${(d(derived['seat_occupancy_rate']) * 100).toStringAsFixed(0)}%',
        '就餐人数口径',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1300
            ? 6
            : constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 480
            ? 2
            : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.9,
          children: [
            for (final m in metrics)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      m.$1,
                      style: TextStyle(
                        color: tokens.inkMuted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      m.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tokens.ink,
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      m.$3,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: tokens.inkMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.tag, required this.child});

  final String title;
  final String tag;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: tokens.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tag,
                  style: TextStyle(color: tokens.inkMuted, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SlotPanel extends StatefulWidget {
  const _SlotPanel({
    required this.slots,
    required this.hourly,
    required this.payments,
    required this.dim,
  });

  final List<Map<String, Object?>> slots;
  final List<Map<String, Object?>> hourly;
  final List<Map<String, Object?>> payments;
  final String dim;

  @override
  State<_SlotPanel> createState() => _SlotPanelState();
}

class _SlotPanelState extends State<_SlotPanel> {
  /// segments（早/午/晚/夜宵四段）与 hourly（逐时分布）互斥切换，不同时展示
  String _view = 'segments';

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final dim = widget.dim;
    final hourly = widget.hourly;
    return _Panel(
      title: '分时段营收',
      tag: dim == 'business' ? '营业锚点口径 · 净收入' : '墙钟口径 · 净收入',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Segmented(
                options: const [
                  ('segments', '分时段'),
                  ('hourly', '逐时'),
                ],
                selected: _view,
                onSelected: (v) => setState(() => _view = v),
              ),
              const Spacer(),
              if (_view == 'hourly')
                Text(
                  dim == 'business'
                      ? '营业日小时 · 锚 open_time（默认16:00）'
                      : '墙钟小时 00–23',
                  style: TextStyle(color: tokens.inkMuted, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_view == 'segments')
            widget.slots.isEmpty
                ? const _EmptyHint(text: '当前时间窗无分时段数据')
                : _SlotList(slots: widget.slots)
          else
            _HourlyChart(
              points: hourly
                  .map(
                    (h) => _HourlyPoint(
                      label: _s(h['start']),
                      endLabel: _s(h['end']),
                      net: _d(h['net_revenue']),
                      orders: _i(h['order_count']),
                      avgTicket: _d(h['avg_ticket']),
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 16),
          Divider(color: tokens.border, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '支付渠道占比',
                style: TextStyle(
                  color: tokens.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '金额口径',
                style: TextStyle(color: tokens.inkMuted, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          widget.payments.isEmpty
              ? const _EmptyHint(text: '当前时间窗无支付渠道数据')
              : _PaymentList(payments: widget.payments),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(
          text,
          style: TextStyle(color: context.cashier.inkMuted, fontSize: 14),
        ),
      ),
    );
  }
}

class _TrendPoint {
  const _TrendPoint({
    required this.label,
    required this.net,
    required this.orders,
  });

  final String label;
  final double net;
  final int orders;
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<_TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return SizedBox(
      height: 260,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendChartPainter(
          points: points,
          gridColor: tokens.border,
          axisColor: tokens.inkMuted,
          barColor: const Color(0xff91cbed),
          valueLabelColor: tokens.ink,
          lineColor: const Color(0xff52c41a),
          labelColor: tokens.inkMuted,
        ),
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  _TrendChartPainter({
    required this.points,
    required this.gridColor,
    required this.axisColor,
    required this.barColor,
    required this.valueLabelColor,
    required this.lineColor,
    required this.labelColor,
  });

  final List<_TrendPoint> points;
  final Color gridColor;
  final Color axisColor;
  final Color barColor;
  final Color valueLabelColor;
  final Color lineColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const leftPad = 48.0;
    const rightPad = 44.0;
    const topPad = 22.0;
    const bottomPad = 26.0;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final maxNet = points.map((p) => p.net).fold<double>(0, (a, b) => a > b ? a : b);
    final maxOrders = points.map((p) => p.orders).fold<int>(0, (a, b) => a > b ? a : b);
    final netTop = maxNet <= 0 ? 1.0 : maxNet;
    final ordTop = maxOrders <= 0 ? 1 : maxOrders;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final textStyle = TextStyle(color: labelColor, fontSize: 10);

    // 横向网格 + 左轴刻度
    const ticks = 4;
    for (var i = 0; i <= ticks; i++) {
      final y = topPad + chartHeight * i / ticks;
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(size.width - rightPad, y),
        gridPaint,
      );
      final value = netTop * (1 - i / ticks);
      final label = value >= 10000
          ? '${(value / 10000).toStringAsFixed(1)}万'
          : value >= 1000
          ? '${(value / 1000).toStringAsFixed(1)}k'
          : value.toStringAsFixed(0);
      final tp = TextPainter(
        text: TextSpan(text: label, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(leftPad - tp.width - 6, y - tp.height / 2),
      );
      // 右轴订单数刻度
      final ordLabel = (ordTop * (1 - i / ticks)).round().toString();
      final op = TextPainter(
        text: TextSpan(text: ordLabel, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      op.paint(
        canvas,
        Offset(size.width - rightPad + 6, y - op.height / 2),
      );
    }

    final slotWidth = chartWidth / points.length;
    final barWidth = slotWidth * 0.46;
    final barPaint = Paint()..color = barColor;

    final linePath = Path();
    final fillPath = Path();
    for (var i = 0; i < points.length; i++) {
      final cx = leftPad + slotWidth * i + slotWidth / 2;
      final netH = chartHeight * points[i].net / netTop;
      final barLeft = cx - barWidth / 2;
      final barTop = topPad + chartHeight - netH;
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(barLeft, barTop, barLeft + barWidth, topPad + chartHeight),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        barPaint,
      );
      // 柱顶金额标签（具体营业额数字）
      if (points[i].net > 0) {
        final vp = TextPainter(
          text: TextSpan(
            text: _fmtAmountFull(points[i].net),
            style: TextStyle(
              color: valueLabelColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = (cx - vp.width / 2)
            .clamp(leftPad, size.width - rightPad - vp.width);
        final labelY = barTop - vp.height - 3;
        vp.paint(
          canvas,
          Offset(labelX, labelY >= topPad ? labelY : topPad + 1),
        );
      }
      final ordY = topPad + chartHeight * (1 - points[i].orders / ordTop);
      if (i == 0) {
        linePath.moveTo(cx, ordY);
        fillPath.moveTo(cx, topPad + chartHeight);
        fillPath.lineTo(cx, ordY);
      } else {
        linePath.lineTo(cx, ordY);
        fillPath.lineTo(cx, ordY);
      }
      // x 轴标签（隔一个显示）
      if (i % 2 == 0 || points.length <= 6) {
        final tp = TextPainter(
          text: TextSpan(text: points[i].label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            (cx - tp.width / 2).clamp(leftPad, size.width - rightPad - tp.width),
            topPad + chartHeight + 6,
          ),
        );
      }
    }
    fillPath.lineTo(
      leftPad + slotWidth * (points.length - 1) + slotWidth / 2,
      topPad + chartHeight,
    );
    fillPath.close();

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);

    // 折线端点
    final dotPaint = Paint()..color = lineColor;
    for (var i = 0; i < points.length; i++) {
      final cx = leftPad + slotWidth * i + slotWidth / 2;
      final ordY = topPad + chartHeight * (1 - points[i].orders / ordTop);
      canvas.drawCircle(Offset(cx, ordY), 3.2, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.barColor != barColor ||
      oldDelegate.valueLabelColor != valueLabelColor ||
      oldDelegate.lineColor != lineColor;
}

class _SlotList extends StatelessWidget {
  const _SlotList({required this.slots});

  final List<Map<String, Object?>> slots;

  static const _names = {
    'breakfast': '早市',
    'lunch': '午市',
    'dinner': '晚市',
    'late_night': '夜宵',
    'bd_evening': '晚市(锚)',
    'bd_late_night': '夜宵(锚)',
    'bd_breakfast': '早市(锚)',
    'bd_lunch': '午市(锚)',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    double d(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final rows = slots.map((s) {
      final key = '${s['slot_key'] ?? ''}';
      return (
        name: _names[key] ?? key,
        net: d(s['net_revenue']),
        orders: i(s['order_count']),
      );
    }).toList();
    final maxNet = rows.fold<double>(0, (a, b) => a > b.net ? a : b.net);

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    row.name,
                    style: TextStyle(color: tokens.inkSecondary, fontSize: 14),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: maxNet <= 0 ? 0 : row.net / maxNet,
                      minHeight: 18,
                      backgroundColor: tokens.subtle,
                      valueColor: AlwaysStoppedAnimation(tokens.selected),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 158,
                  child: Text(
                    '¥${_fmtAmountFull(row.net)} · ${row.orders} 单',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: tokens.inkSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _PaymentList extends StatelessWidget {
  const _PaymentList({required this.payments});

  final List<Map<String, Object?>> payments;

  static const _names = {
    'wechat': '微信',
    'alipay': '支付宝',
    'cash': '现金',
    'member_balance': '会员余额',
    'other': '其他',
  };

  static const _colors = {
    'wechat': Color(0xff52c41a),
    'alipay': Color(0xff1677ff),
    'cash': Color(0xfffaad14),
    'member_balance': Color(0xff9a8cff),
    'other': Color(0xff8a8a8a),
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    double d(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final rows = payments.map((p) {
      final key = '${p['channel_key'] ?? ''}';
      return (
        name: _names[key] ?? key,
        net: d(p['net_revenue']),
        orders: i(p['order_count']),
        color: _colors[key] ?? tokens.selected,
      );
    }).toList();
    final total = rows.fold<double>(0, (a, b) => a + b.net);

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Text(
                    row.name,
                    style: TextStyle(color: tokens.inkSecondary, fontSize: 14),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: LinearProgressIndicator(
                      value: total <= 0 ? 0 : row.net / total,
                      minHeight: 16,
                      backgroundColor: tokens.subtle,
                      valueColor: AlwaysStoppedAnimation(row.color),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 186,
                  child: Text(
                    '¥${_fmtAmountFull(row.net)} · '
                    '${total <= 0 ? 0 : (row.net / total * 100).toStringAsFixed(0)}%'
                    ' · ${row.orders}单',
                    textAlign: TextAlign.right,
                    style: TextStyle(color: tokens.inkSecondary, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DishTable extends StatelessWidget {
  const _DishTable({required this.dishes});

  final List<Map<String, Object?>> dishes;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    double d(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    String s(Object? v) => v == null ? '' : '$v';

    Widget tag(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 12)),
    );

    final velocityMap = {
      'hot': ('热销', const Color(0xff52c41a)),
      'slow': ('滞销', const Color(0xffea6668)),
      'normal': ('正常', tokens.inkSecondary),
    };
    final marginMap = {
      'high': ('高', tokens.selected),
      'medium': ('中', const Color(0xfffaad14)),
      'low': ('低', const Color(0xffea6668)),
      'unknown': ('未知', tokens.inkMuted),
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 720;
        final headerStyle = TextStyle(
          color: tokens.inkMuted,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );
        final cellStyle = TextStyle(color: tokens.ink, fontSize: 14);

        Widget headerCell(String text) => SizedBox(
          width: compact ? 70 : 96,
          child: Text(text, style: headerStyle),
        );

        return Column(
          children: [
            Row(
              children: [
                SizedBox(width: 44, child: Text('排名', style: headerStyle)),
                Expanded(child: Text('菜品', style: headerStyle)),
                if (!compact) headerCell('销量（份）'),
                if (!compact) headerCell('销售额（元）'),
                headerCell('毛利档'),
                headerCell('动销'),
              ],
            ),
            const SizedBox(height: 6),
            for (var index = 0; index < dishes.length; index++)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: tokens.subtle),
                  ),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: index < 3
                              ? tokens.selectedBackground
                              : tokens.subtle,
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(
                            color: index < 3 ? tokens.selected : tokens.inkMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        s(dishes[index]['dish_name']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: cellStyle,
                      ),
                    ),
                    if (!compact)
                      SizedBox(
                        width: 96,
                        child: Text(
                          '${i(dishes[index]['total_quantity'])}',
                          style: cellStyle,
                        ),
                      ),
                    if (!compact)
                      SizedBox(
                        width: 112,
                        child: Text(
                          '${_fmtAmountFull(d(dishes[index]['total_sales']))}',
                          style: cellStyle,
                        ),
                      ),
                    SizedBox(
                      width: compact ? 64 : 96,
                      child: (() {
                        final m = marginMap[s(dishes[index]['margin_category'])];
                        if (m == null) return const SizedBox.shrink();
                        return tag(m.$1, m.$2);
                      })(),
                    ),
                    SizedBox(
                      width: compact ? 64 : 96,
                      child: (() {
                        final v = velocityMap[s(dishes[index]['velocity_tag'])];
                        if (v == null) return const SizedBox.shrink();
                        return tag(v.$1, v.$2);
                      })(),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

}

class _EntryGrid extends StatelessWidget {
  const _EntryGrid();

  static const _entries = [
    ('👥', '顾客分析', '新客/老客 · 复购 · 口味'),
    ('💳', '会员分析', '会员活跃 · 充值流水'),
    ('🎯', '营销分析', '活动转化 · 券核销'),
    ('🧑‍💼', '收银员业绩', '订单数 · 金额排行'),
    ('🏪', '门店利润', '多门店对比'),
    ('🆚', '同比 / 环比', '自然日 order_time'),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1200
            ? 4
            : constraints.maxWidth >= 760
            ? 3
            : constraints.maxWidth >= 380
            ? 2
            : 1;
        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 2.8,
          children: [
            for (final e in _entries)
              InkWell(
                onTap: () {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(
                        content: Text('「${e.$2}」详情将在后续版本接入'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tokens.selectedBackground,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(e.$1, style: const TextStyle(fontSize: 20)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.$2,
                              style: TextStyle(
                                color: tokens.ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              e.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tokens.inkMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ============================================================
// 结算日设置（口径说明）
// ============================================================

class _BusinessDayView extends StatelessWidget {
  const _BusinessDayView();

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    Widget card(String title, Widget child) => Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: tokens.ink,
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );

    Widget item(String label, String value, String note) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: tokens.inkMuted, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: tokens.ink,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          note,
          style: TextStyle(color: tokens.inkMuted, fontSize: 12),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          card(
            '结算日口径',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '所有报表（日报/周报/月报/菜品/收银员/利润）统一按结算日窗口统计；'
                  '未选择日期时，显示最近已完成结算日。',
                  style: TextStyle(color: tokens.inkSecondary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 720;
                    final itemWidth = wide
                        ? (constraints.maxWidth - 16) / 2
                        : constraints.maxWidth;
                    return Wrap(
                      spacing: 16,
                      runSpacing: 18,
                      children: [
                        SizedBox(
                          width: itemWidth,
                          child: item('窗口起点', '截止前 12 小时', '由结算截止时间向前计算'),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: item('结算截止时间', '04:00', 'settle_time · 门店可配置'),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: item('配置来源', '门店配置优先', '未覆盖时继承总店默认'),
                        ),
                        SizedBox(
                          width: itemWidth,
                          child: item('默认窗口', '前日 16:00 ～ 当日 04:00', '默认截止时间 04:00 时的兜底口径'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          card(
            '统计口径说明',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in const [
                  '金额口径：净收入 = 结账金额 + 服务费 − 优惠 − 退款（仅成功单）',
                  '自然日 vs 结算日：自然日按 00:00 分界；结算日为 settle_time 前 12 小时至 settle_time（右开）',
                  '翻台率 = 堂食订单数 ÷ 桌台数 ÷ 天数；上座率 = 堂食用餐人数 ÷ (桌台 × 餐位 × 天数 × 餐次)',
                  '分时段两套口径：墙钟（早 05–10 / 午 10–16 / 晚 16–22 / 夜宵其余）；营业锚点（固定 16:00 四段）',
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '· $line',
                      style: TextStyle(
                        color: tokens.inkSecondary,
                        fontSize: 14,
                        height: 1.6,
                      ),
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

// ============================================================
// 导出任务
// ============================================================

class _ExportsView extends StatelessWidget {
  const _ExportsView({
    required this.loading,
    required this.creating,
    required this.downloading,
    required this.error,
    required this.reportType,
    required this.exportStart,
    required this.exportEnd,
    required this.jobs,
    required this.onTypeChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onCreate,
    required this.onDownload,
    required this.onReload,
  });

  final bool loading;
  final bool creating;
  final bool downloading;
  final Object? error;
  final String reportType;
  final DateTime? exportStart;
  final DateTime? exportEnd;
  final List<Map<String, Object?>> jobs;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onCreate;
  final ValueChanged<Map<String, Object?>> onDownload;
  final VoidCallback onReload;

  String _two(int v) => v.toString().padLeft(2, '0');

  String _d(DateTime t) =>
      '${t.year}-${_two(t.month)}-${_two(t.day)}';

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final pending = jobs
        .where((j) =>
            '${j['status']}' == 'PENDING' || '${j['status']}' == 'RUNNING')
        .length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Panel(
            title: '创建导出任务',
            tag: '异步生成 · 下载令牌 15 分钟有效',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 20,
                  runSpacing: 14,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _Field(
                      label: '报表类型',
                      child: _Segmented(
                        options: const [
                          ('daily', '日报'),
                          ('weekly', '周报'),
                          ('monthly', '月报'),
                        ],
                        selected: reportType,
                        onSelected: onTypeChanged,
                      ),
                    ),
                    _Field(
                      label: reportType == 'daily' ? '日期' : '开始日期',
                      child: OutlinedButton(
                        onPressed: onPickStart,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.ink,
                          side: BorderSide(color: tokens.border),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          exportStart == null ? '选择日期' : _d(exportStart!),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                    ),
                    if (reportType != 'daily')
                      _Field(
                        label: '结束日期',
                        child: OutlinedButton(
                          onPressed: onPickEnd,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: tokens.ink,
                            side: BorderSide(color: tokens.border),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          child: Text(
                            exportEnd == null ? '选择日期' : _d(exportEnd!),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ),
                    const _Field(
                      label: '格式',
                      child: Text('CSV', style: TextStyle(fontSize: 14)),
                    ),
                    _Field(
                      label: ' ',
                      child: FilledButton(
                        onPressed: creating ? null : onCreate,
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.selected,
                          foregroundColor: const Color(0xff0d1b2a),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                        child: Text(
                          creating ? '创建中…' : '创建任务',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '周报/月报日期含首尾最多 92 天；日报以所选日期为准。'
                  '当前门店未完成任务：$pending / 4（全局 128）。',
                  style: TextStyle(color: tokens.inkMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _Panel(
            title: '导出任务列表',
            tag: downloading ? '下载中…' : 'jobType: REPORT_EXPORT',
            child: loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : error != null
                ? _ErrorCard(message: '$error', onRetry: onReload)
                : _JobTable(jobs: jobs, onDownload: onDownload),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: context.cashier.inkMuted, fontSize: 13),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _JobTable extends StatelessWidget {
  const _JobTable({required this.jobs, required this.onDownload});

  final List<Map<String, Object?>> jobs;
  final ValueChanged<Map<String, Object?>> onDownload;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    if (jobs.isEmpty) {
      return const _EmptyHint(text: '暂无导出任务');
    }
    String s(Object? v) => v == null ? '' : '$v';
    String typeName(String t) => switch (t) {
      'daily' => '日报',
      'weekly' => '周报',
      'monthly' => '月报',
      _ => t,
    };

    Widget statusBadge(String status) {
      final (label, color) = switch (status) {
        'PENDING' => ('排队中', tokens.inkMuted),
        'RUNNING' => ('生成中', tokens.selected),
        'DONE' => ('已完成', const Color(0xff52c41a)),
        'FAILED' => ('失败', const Color(0xffea6668)),
        _ => (status, tokens.inkMuted),
      };
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      );
    }

    Widget action(Map<String, Object?> job) {
      final status = s(job['status']);
      if (status == 'DONE') {
        final url = s(job['downloadUrl']);
        if (url.isEmpty) {
          return Text(
            '下载链接已过期（15 分钟）',
            style: TextStyle(color: tokens.inkMuted, fontSize: 12.5),
          );
        }
        return TextButton(
          onPressed: () => onDownload(job),
          style: TextButton.styleFrom(
            foregroundColor: tokens.selected,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: const Size(0, 32),
          ),
          child: const Text('下载', style: TextStyle(fontSize: 13.5)),
        );
      }
      if (status == 'FAILED') {
        final error = s(job['error']);
        return Tooltip(
          message: error.isEmpty ? '任务失败，请重新创建导出任务' : error,
          child: Text(
            error.isEmpty ? '任务失败，请重试' : '失败：$error',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: const Color(0xffea6668), fontSize: 12.5),
          ),
        );
      }
      return Text(
        status == 'RUNNING' ? '正在生成…' : '等待执行…',
        style: TextStyle(color: tokens.inkMuted, fontSize: 12.5),
      );
    }

    final headerStyle = TextStyle(
      color: tokens.inkMuted,
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    final cellStyle = TextStyle(color: tokens.ink, fontSize: 14);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        return Column(
          children: [
            Row(
              children: [
                SizedBox(width: 92, child: Text('任务ID', style: headerStyle)),
                SizedBox(width: 60, child: Text('类型', style: headerStyle)),
                if (!compact) Expanded(child: Text('日期范围', style: headerStyle)),
                SizedBox(width: 84, child: Text('状态', style: headerStyle)),
                if (!compact) SizedBox(width: 120, child: Text('创建时间', style: headerStyle)),
                if (!compact) SizedBox(width: 110, child: Text('完成时间', style: headerStyle)),
                SizedBox(width: 140, child: Text('操作', style: headerStyle)),
              ],
            ),
            const SizedBox(height: 6),
            for (final job in jobs)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: tokens.subtle)),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text('#${s(job['jobId'] ?? job['id'])}', style: cellStyle),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(typeName(s(job['reportType'] ?? job['jobType'] ?? '')),
                          style: cellStyle),
                    ),
                    if (!compact)
                      Expanded(
                        child: Text(
                          _range(job),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: cellStyle,
                        ),
                      ),
                    SizedBox(width: 84, child: statusBadge(s(job['status']))),
                    if (!compact)
                      SizedBox(
                        width: 120,
                        child: Text(
                          _time(s(job['createdAt'] ?? job['created_at'])),
                          style: TextStyle(color: tokens.inkSecondary, fontSize: 13),
                        ),
                      ),
                    if (!compact)
                      SizedBox(
                        width: 110,
                        child: Text(
                          _time(s(job['updatedAt'] ?? job['finishedAt'] ?? job['updated_at'] ?? job['finished_at'])),
                          style: TextStyle(color: tokens.inkSecondary, fontSize: 13),
                        ),
                      ),
                    SizedBox(width: 140, child: action(job)),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  String _time(String raw) {
    if (raw.isEmpty) return '—';
    final value = raw.replaceFirst('T', ' ').replaceFirst(RegExp(r'\.\d+$'), '');
    if (value.length >= 16) return value.substring(5, 16);
    return value;
  }

  String _text(Object? value) => value == null ? '' : '$value';

  String _range(Map<String, Object?> job) {
    final filters = job['filters'];
    if (filters is Map) {
      final date = _text(filters['date']);
      if (date.isNotEmpty) return date;
      final start = _text(filters['startDate']);
      final end = _text(filters['endDate']);
      if (start.isNotEmpty && end.isNotEmpty) return '$start ~ $end';
    }
    return _text(job['rangeText'] ?? job['dateRange'] ?? '—');
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.inkSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('重新加载'),
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.selected,
              side: BorderSide(color: tokens.border),
            ),
          ),
        ],
      ),
    );
  }
}

// 顶层工具（与 shared 页内解析保持一致）
Map<String, Object?> _map(Object? value) =>
    value is Map ? value.cast<String, Object?>() : const {};

String _s(Object? value) => value == null ? '' : '$value';

double _d(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

/// 千分位 + 两位小数（精确到分），营业额统一使用
String _fmtAmountFull(double v) {
  final fixed = v.toStringAsFixed(2);
  final dot = fixed.indexOf('.');
  final intPart = fixed.substring(0, dot);
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    buf.write(intPart[i]);
    final remaining = intPart.length - 1 - i;
    if (remaining > 0 && remaining % 3 == 0) buf.write(',');
  }
  return '$buf${fixed.substring(dot)}';
}

int _i(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;


// ============================================================
// 逐时分布（v1.2.238：time_slots_hourly / time_slots_business_hourly）
// ============================================================

class _HourlyPoint {
  const _HourlyPoint({
    required this.label,
    required this.endLabel,
    required this.net,
    required this.orders,
    required this.avgTicket,
  });

  final String label;
  final String endLabel;
  final double net;
  final int orders;
  final double avgTicket;
}

class _HourlyChart extends StatefulWidget {
  const _HourlyChart({required this.points});

  final List<_HourlyPoint> points;

  @override
  State<_HourlyChart> createState() => _HourlyChartState();
}

class _HourlyChartState extends State<_HourlyChart> {
  int _selected = -1;

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final tokens = context.cashier;
    if (points.isEmpty) {
      return const _EmptyHint(text: '该口径下无逐时数据');
    }
    var maxIndex = 0;
    for (var i = 1; i < points.length; i++) {
      if (points[i].net > points[maxIndex].net) maxIndex = i;
    }
    final detailIndex =
        _selected >= 0 && _selected < points.length ? _selected : maxIndex;
    final detail = points[detailIndex];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return GestureDetector(
              onTapUp: (details) {
                final n = points.length;
                final slot = (width - 12) / n;
                final idx = (details.localPosition.dx / slot)
                    .floor()
                    .clamp(0, n - 1);
                setState(() => _selected = _selected == idx ? -1 : idx);
              },
              child: SizedBox(
                height: 148,
                width: width,
                child: CustomPaint(
                  painter: _HourlyPainter(
                    points: points,
                    selectedIndex: detailIndex,
                    gridColor: tokens.border,
                    barColor: tokens.selected,
                    labelColor: tokens.inkMuted,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: tokens.subtle,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${detail.label}–${detail.endLabel}  '
            '¥${_fmtAmountFull(detail.net)} · ${detail.orders} 单 · '
            '平均单笔 ¥${_fmtAmountFull(detail.avgTicket)}',
            style: TextStyle(color: tokens.inkSecondary, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

class _HourlyPainter extends CustomPainter {
  _HourlyPainter({
    required this.points,
    required this.selectedIndex,
    required this.gridColor,
    required this.barColor,
    required this.labelColor,
  });

  final List<_HourlyPoint> points;
  final int selectedIndex;
  final Color gridColor;
  final Color barColor;
  final Color labelColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const leftPad = 6.0;
    const rightPad = 6.0;
    const topPad = 20.0;
    const bottomPad = 22.0;
    final chartWidth = size.width - leftPad - rightPad;
    final chartHeight = size.height - topPad - bottomPad;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    final maxNet =
        points.fold<double>(0, (a, b) => a > b.net ? a : b.net);
    final top = maxNet <= 0 ? 1.0 : maxNet;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const textStyle = TextStyle(fontSize: 9.5);

    canvas.drawLine(
      Offset(leftPad, size.height - bottomPad),
      Offset(size.width - rightPad, size.height - bottomPad),
      gridPaint,
    );
    // 顶部参考线
    canvas.drawLine(
      Offset(leftPad, topPad),
      Offset(size.width - rightPad, topPad),
      gridPaint,
    );

    final slotWidth = chartWidth / points.length;
    final barWidth = (slotWidth * 0.62).clamp(6.0, 34.0);
    final showLabels = points.length <= 12;
    final labelStep = points.length <= 12 ? 1 : (points.length / 12).ceil();

    for (var i = 0; i < points.length; i++) {
      final cx = leftPad + slotWidth * i + slotWidth / 2;
      final h = chartHeight * (points[i].net / top);
      final barLeft = cx - barWidth / 2;
      final barTop = size.height - bottomPad - h;
      final selected = i == selectedIndex;
      final fillPaint = Paint()..color = barColor.withValues(alpha: selected ? 1.0 : 0.55);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(barLeft, barTop, barLeft + barWidth, size.height - bottomPad),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        fillPaint,
      );
      if (selected) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromLTRB(barLeft - 1.5, barTop - 1.5, barLeft + barWidth + 1.5, size.height - bottomPad + 1.5),
            topLeft: const Radius.circular(4),
            topRight: const Radius.circular(4),
          ),
          Paint()
            ..color = barColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
      // x 轴标签（桶多时抽样显示）
      if (i % labelStep == 0 || i == points.length - 1) {
        final tp = TextPainter(
          text: TextSpan(text: points[i].label, style: textStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            (cx - tp.width / 2).clamp(leftPad, size.width - rightPad - tp.width),
            size.height - bottomPad + 5,
          ),
        );
      }
      // 柱顶金额（桶少时直接显示，精确到分）
      if (showLabels && points[i].net > 0) {
        final vp = TextPainter(
          text: TextSpan(
            text: _fmtAmountFull(points[i].net),
            style: TextStyle(
              color: barColor,
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final labelX = (cx - vp.width / 2)
            .clamp(leftPad, size.width - rightPad - vp.width);
        final labelY = barTop - vp.height - 2;
        vp.paint(
          canvas,
          Offset(labelX, labelY >= topPad ? labelY : topPad + 1),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HourlyPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.barColor != barColor;
}

// ================= 自定义精确时间窗口弹窗与时间解析 =================

@visibleForTesting
String fmtReportDateTime(DateTime t) => _fmtDateTime(t);

@visibleForTesting
DateTime? parseCustomDateTime(String raw) => _parseCustomDateTime(raw);

String _fmtDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final base = '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
  if (t.millisecond > 0) {
    return '$base.${t.millisecond.toString().padLeft(3, '0')}';
  }
  return base;
}

DateTime? _parseCustomDateTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  // Replace '/' with '-'
  final normalized = text.replaceAll('/', '-');

  // Match: YYYY-M-D H:M:S(.SSS)?
  final regex = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2}))?(?:\.(\d{1,3}))?)?$',
  );
  final match = regex.firstMatch(normalized);
  if (match != null) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final hour = match.group(4) != null ? int.parse(match.group(4)!) : 0;
    final minute = match.group(5) != null ? int.parse(match.group(5)!) : 0;
    final second = match.group(6) != null ? int.parse(match.group(6)!) : 0;
    int millisecond = 0;
    if (match.group(7) != null) {
      final msStr = match.group(7)!.padRight(3, '0').substring(0, 3);
      millisecond = int.parse(msStr);
    }

    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    if (hour < 0 || hour > 23) return null;
    if (minute < 0 || minute > 59) return null;
    if (second < 0 || second > 59) return null;
    if (millisecond < 0 || millisecond > 999) return null;

    try {
      final dt = DateTime(year, month, day, hour, minute, second, millisecond);
      if (dt.month != month || dt.day != day) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  return null;
}

class _CustomDateTimeRangeDialog extends StatefulWidget {
  const _CustomDateTimeRangeDialog({
    required this.initialStart,
    required this.initialEnd,
  });

  final DateTime initialStart;
  final DateTime initialEnd;

  @override
  State<_CustomDateTimeRangeDialog> createState() =>
      _CustomDateTimeRangeDialogState();
}

class _CustomDateTimeRangeDialogState
    extends State<_CustomDateTimeRangeDialog> {
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  String? _errorMsg;

  @override
  void initState() {
    super.initState();
    _startCtrl = TextEditingController(text: _fmtDateTime(widget.initialStart));
    _endCtrl = TextEditingController(text: _fmtDateTime(widget.initialEnd));
    _validate();
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _validate() {
    final s = _parseCustomDateTime(_startCtrl.text);
    final e = _parseCustomDateTime(_endCtrl.text);
    String? err;
    if (s == null) {
      err = '开始时间格式无效（示例：2026-09-30 16:00:00）';
    } else if (e == null) {
      err = '结束时间格式无效（示例：2026-09-30 16:00:00）';
    } else if (e.isBefore(s)) {
      err = '结束时间不能早于开始时间';
    }
    if (_errorMsg != err) {
      setState(() => _errorMsg = err);
    }
  }

  void _applyPreset({
    required DateTime start,
    required DateTime end,
  }) {
    _startCtrl.text = _fmtDateTime(start);
    _endCtrl.text = _fmtDateTime(end);
    _validate();
  }

  Future<void> _pickDateFor(TextEditingController ctrl) async {
    final current = _parseCustomDateTime(ctrl.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(current.year - 5),
      lastDate: DateTime(current.year + 2),
      helpText: '选择日期',
    );
    if (picked == null) return;
    final updated = DateTime(
      picked.year,
      picked.month,
      picked.day,
      current.hour,
      current.minute,
      current.second,
      current.millisecond,
    );
    ctrl.text = _fmtDateTime(updated);
    _validate();
  }

  Future<void> _pickTimeFor(TextEditingController ctrl) async {
    final current = _parseCustomDateTime(ctrl.text) ?? DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: '选择时间',
    );
    if (picked == null) return;
    final updated = DateTime(
      current.year,
      current.month,
      current.day,
      picked.hour,
      picked.minute,
      current.second,
      current.millisecond,
    );
    ctrl.text = _fmtDateTime(updated);
    _validate();
  }

  void _setTimeShortcut(
    TextEditingController ctrl,
    int h,
    int m,
    int s, [
    int ms = 0,
  ]) {
    final current = _parseCustomDateTime(ctrl.text) ?? DateTime.now();
    final updated = DateTime(
      current.year,
      current.month,
      current.day,
      h,
      m,
      s,
      ms,
    );
    ctrl.text = _fmtDateTime(updated);
    _validate();
  }

  void _setNow(TextEditingController ctrl) {
    ctrl.text = _fmtDateTime(DateTime.now());
    _validate();
  }

  void _confirm() {
    final s = _parseCustomDateTime(_startCtrl.text);
    final e = _parseCustomDateTime(_endCtrl.text);
    if (s != null && e != null && !e.isBefore(s)) {
      Navigator.of(context).pop(DateTimeRange(start: s, end: e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final now = DateTime.now();
    final today0 = DateTime(now.year, now.month, now.day, 0, 0, 0);

    return Dialog(
      backgroundColor: tokens.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    color: tokens.selected,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '自定义时间范围',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: tokens.ink,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: tokens.inkMuted,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '快捷时间段预设：',
                style: TextStyle(fontSize: 12, color: tokens.inkSecondary),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _PresetButton(
                    label: '今日至今 (00:00~现在)',
                    onPressed: () => _applyPreset(
                      start: today0,
                      end: now,
                    ),
                  ),
                  _PresetButton(
                    label: '昨日整天',
                    onPressed: () => _applyPreset(
                      start:
                          DateTime(now.year, now.month, now.day - 1, 0, 0, 0),
                      end: DateTime(
                        now.year,
                        now.month,
                        now.day - 1,
                        23,
                        59,
                        59,
                      ),
                    ),
                  ),
                  _PresetButton(
                    label: '近7天 (今天-6 00:00~现在)',
                    onPressed: () => _applyPreset(
                      start:
                          DateTime(now.year, now.month, now.day - 6, 0, 0, 0),
                      end: now,
                    ),
                  ),
                  _PresetButton(
                    label: '本月至今',
                    onPressed: () => _applyPreset(
                      start: DateTime(now.year, now.month, 1, 0, 0, 0),
                      end: now,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(height: 1, color: tokens.border),
              const SizedBox(height: 16),
              _buildDateTimeSection(
                title: '开始时间',
                controller: _startCtrl,
                tokens: tokens,
              ),
              const SizedBox(height: 14),
              _buildDateTimeSection(
                title: '结束时间',
                controller: _endCtrl,
                tokens: tokens,
              ),
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: tokens.danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _errorMsg!,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.danger,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      '取消',
                      style: TextStyle(color: tokens.inkSecondary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _errorMsg == null ? _confirm : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: tokens.selected,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: tokens.disabledBackground,
                      disabledForegroundColor: tokens.disabledForeground,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      '确定应用',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeSection({
    required String title,
    required TextEditingController controller,
    required CashierTokens tokens,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.ink,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '支持秒及毫秒（如 2026-9-30 16:00:00 或 2026-09-30 16:00:00.000）',
                style: TextStyle(fontSize: 11, color: tokens.inkMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: (_) => _validate(),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  color: tokens.ink,
                ),
                decoration: InputDecoration(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: tokens.subtle,
                  hintText: 'yyyy-MM-dd HH:mm:ss',
                  hintStyle: TextStyle(fontSize: 13, color: tokens.inkMuted),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: tokens.selected, width: 1.5),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Tooltip(
              message: '在日历中选择日期',
              child: IconButton(
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                color: tokens.selected,
                onPressed: () => _pickDateFor(controller),
              ),
            ),
            Tooltip(
              message: '在表盘中选择时间',
              child: IconButton(
                icon: const Icon(Icons.access_time_outlined, size: 18),
                color: tokens.selected,
                onPressed: () => _pickTimeFor(controller),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _TimeShortcutButton(
              label: '00:00:00',
              onPressed: () => _setTimeShortcut(controller, 0, 0, 0),
            ),
            _TimeShortcutButton(
              label: '16:00:00',
              onPressed: () => _setTimeShortcut(controller, 16, 0, 0),
            ),
            _TimeShortcutButton(
              label: '23:59:59',
              onPressed: () => _setTimeShortcut(controller, 23, 59, 59),
            ),
            _TimeShortcutButton(
              label: '当前时间',
              onPressed: () => _setNow(controller),
            ),
          ],
        ),
      ],
    );
  }
}

class _PresetButton extends StatelessWidget {
  const _PresetButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.inkSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _TimeShortcutButton extends StatelessWidget {
  const _TimeShortcutButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: tokens.subtle,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: tokens.border),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, color: tokens.inkSecondary),
        ),
      ),
    );
  }
}

