import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../reports/data/business_report_query.dart';
import '../../reports/domain/daily_report.dart';
import '../data/api_providers.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 营业报表（PRD F06，仅老板/授权账号可见，路由侧已 bossOnly 守卫）。
///
/// 三个 Tab：营业概况（日报/周报/月报）、收银员业绩（本人/全部）、菜品排行。
/// 数据来自 `/admin/report/*`，响应为宽松结构，本页用兼容字段名解析。
class BossReportsPage extends ConsumerWidget {
  const BossReportsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('营业报表'),
          bottom: const TabBar(
            tabs: [
              Tab(text: '营业概况'),
              Tab(text: '收银员业绩'),
              Tab(text: '菜品排行'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SummaryTab(),
            _CashierTab(),
            _DishRankingTab(),
          ],
        ),
      ),
    );
  }
}

enum ReportPeriod { day, week, month }

/// 周期选择：日 / 周 / 月，默认今天 / 本周 / 本月。
class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.period,
    required this.onChanged,
  });

  final ReportPeriod period;
  final ValueChanged<ReportPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ReportPeriod>(
      segments: const [
        ButtonSegment(value: ReportPeriod.day, label: Text('日报')),
        ButtonSegment(value: ReportPeriod.week, label: Text('周报')),
        ButtonSegment(value: ReportPeriod.month, label: Text('月报')),
      ],
      selected: {period},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// 宽松解析的营业概况。
class _ReportSummary {
  const _ReportSummary({
    required this.revenue,
    required this.orderCount,
    required this.refundAmount,
    required this.discountAmount,
    required this.periodLabel,
  });

  final double revenue;
  final int orderCount;
  final double refundAmount;
  final double discountAmount;
  final String periodLabel;

  double get avgOrderAmount => orderCount > 0 ? revenue / orderCount : 0;

  factory _ReportSummary.fromJson(Object? raw, {required String periodLabel}) {
    final m =
        raw is Map ? raw.cast<String, Object?>() : const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final revenue =
        d(m['revenue'] ?? m['totalRevenue'] ?? m['businessRevenue'] ?? m['todayRevenue'] ?? m['salesAmount']);
    return _ReportSummary(
      revenue: revenue,
      orderCount: i(
        m['orderCount'] ?? m['totalOrderCount'] ?? m['todayOrderCount'] ?? m['orderNum'],
      ),
      refundAmount: d(
        m['refundAmount'] ?? m['totalRefundAmount'] ?? m['refund'],
      ),
      discountAmount: d(
        m['discountAmount'] ?? m['totalDiscountAmount'] ?? m['discount'],
      ),
      periodLabel: periodLabel,
    );
  }
}

class _SummaryTab extends ConsumerStatefulWidget {
  const _SummaryTab();

  @override
  ConsumerState<_SummaryTab> createState() => _SummaryTabState();
}

class _SummaryTabState extends ConsumerState<_SummaryTab> {
  ReportPeriod _period = ReportPeriod.day;
  DateTime _selectedBusinessDate = DateTime.now();

  String _rangeLabel() {
    final now = _selectedBusinessDate;
    return switch (_period) {
      ReportPeriod.day => '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      ReportPeriod.week => '第${_weekNumber(now)}周 · ${_weekRange(now)}',
      ReportPeriod.month => '${now.year}年${now.month}月',
    };
  }

  static int _weekNumber(DateTime d) => ((d.day - 1) ~/ 7) + 1;

  static String _weekRange(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    final sunday = monday.add(const Duration(days: 6));
    String f(DateTime x) =>
        '${x.month}/${x.day}';
    return '${f(monday)}~${f(sunday)}';
  }

  Future<Object?> _load() {
    final client = ref.read(apiClientProvider);
    return switch (_period) {
      ReportPeriod.day => client.get(
          reportDailyEndpoint,
          query: dailyBusinessReportQuery(_selectedBusinessDate, detail: true),
        ),
      ReportPeriod.week => _loadWeek(client),
      ReportPeriod.month => client.get(
          reportMonthlyEndpoint,
          query: monthlyBusinessReportQuery(_selectedBusinessDate),
        ),
    };
  }

  Future<Object?> _loadWeek(AdminApiClient client) async {
    final monday = _selectedBusinessDate.subtract(
      Duration(days: _selectedBusinessDate.weekday - 1),
    );
    final sunday = monday.add(const Duration(days: 6));
    return client.get(
      reportWeeklyEndpoint,
      query: weeklyBusinessReportQuery(monday, sunday),
    );
  }

  Future<void> _pickDate() async {
    final now = _selectedBusinessDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year, now.month + 1, 0),
    );
    if (picked != null) {
      setState(() => _selectedBusinessDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      child: ListView(
        padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
        children: [
          Row(
            children: [
              Expanded(
                child: _PeriodSelector(
                  period: _period,
                  onChanged: (p) => setState(() => _period = p),
                ),
              ),
              const SizedBox(width: MobileMetrics.spaceMd),
              IconButton(
                tooltip: '选择营业日',
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
              ),
            ],
          ),
          const SizedBox(height: MobileMetrics.spaceMd),
          Text(_rangeLabel(), style: context.captionStyle),
          const SizedBox(height: MobileMetrics.cardGap),
          FutureBuilder<Object?>(
            future: _load(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingSkeleton(height: 220);
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: '报表加载失败：${snapshot.error}',
                  onRetry: () => setState(() {}),
                );
              }
              final raw = _unwrap(snapshot.data);
              if (_period == ReportPeriod.day) {
                final dailyReport = DailyReport.fromJson(raw);
                return _buildDailyDetail(context, dailyReport);
              }
              final summary = _ReportSummary.fromJson(
                raw,
                periodLabel: _rangeLabel(),
              );
              return _buildSummary(context, summary);
            },
          ),
        ],
      ),
    );
  }

  Object? _unwrap(Object? data) {
    if (data is Map) {
      final report = data['report'];
      if (report is Map) return report;
      for (final k in const ['data', 'result', 'payload']) {
        final v = data[k];
        if (v is Map) return v;
      }
    }
    return data;
  }

  Widget _buildDailyDetail(BuildContext context, DailyReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Metadata & Status Banner
        Card(
          elevation: 0,
          color: context.palette.surfaceSubtle,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MobileMetrics.radiusCard),
            side: BorderSide(color: context.palette.border),
          ),
          child: Padding(
            padding: MobileMetrics.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        r.metadata.shopName.isNotEmpty ? r.metadata.shopName : '收银门店',
                        style: MobileTypography.sectionTitle.copyWith(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    StatusTag(
                      r.metadata.isSettled ? '已关账 (Z-Report)' : '实时预览 (X-Report)',
                      tone: r.metadata.isSettled
                          ? SemanticTone.success
                          : SemanticTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: MobileMetrics.spaceSm),
                Text(
                  '营业日：${r.metadata.businessDay.isNotEmpty ? r.metadata.businessDay : _rangeLabel()}',
                  style: context.captionStyle,
                ),
                if (r.metadata.windowStart.isNotEmpty) ...[
                  const SizedBox(height: MobileMetrics.spaceXs),
                  Text(
                    '统计窗口：${r.metadata.windowStart} ~ ${r.metadata.windowEnd}',
                    style: context.captionStyle.copyWith(fontSize: 11),
                  ),
                ],
                const SizedBox(height: MobileMetrics.spaceSm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '关账人：${r.metadata.operatorName}',
                      style: context.captionStyle,
                    ),
                    if (r.printableText != null && r.printableText!.isNotEmpty)
                      InkWell(
                        onTap: () => _showPrintPreview(context, r.printableText!),
                        child: Text(
                          '🖨️ 小票预览',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.palette.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: MobileMetrics.cardGap),

        // 2. 核心营收指标
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: MobileMetrics.cardGap,
          crossAxisSpacing: MobileMetrics.cardGap,
          childAspectRatio: 1.6,
          children: [
            _metric(context, '实收营业额 (净入账)', AmountText(r.summary.netRevenue)),
            _metric(context, '账面原价销售额', AmountText(r.summary.grossRevenue)),
            _metric(
              context,
              '折扣减免总额',
              AmountText(
                r.summary.totalDiscount,
                style: _valueStyle(context).copyWith(color: context.palette.textSecondary, fontSize: 24),
              ),
            ),
            _metric(
              context,
              '退款总额',
              AmountText(
                r.summary.totalRefund,
                style: _valueStyle(context).copyWith(color: context.palette.danger),
              ),
            ),
            _metric(context, '有效订单数', Text('${r.summary.orderCount} 单', style: _valueStyle(context))),
            _metric(context, '客单价 (单均)', AmountText(r.summary.avgOrderAmount)),
            _metric(
              context,
              '用餐人数 (客均)',
              Text(
                '${r.summary.dinerCount}人 / ¥${r.summary.avgDinerAmount.toStringAsFixed(1)}',
                style: _valueStyle(context).copyWith(fontSize: 18),
              ),
            ),
            _metric(
              context,
              '翻台率',
              Text(
                '${r.summary.tableTurnoverRate.toStringAsFixed(1)} 次/台',
                style: _valueStyle(context).copyWith(fontSize: 18),
              ),
            ),
          ],
        ),
        const SizedBox(height: MobileMetrics.cardGap),

        // 3. 支付渠道实收明细
        _buildSectionCard(
          context,
          title: '💳 支付渠道实收明细',
          child: r.paymentChannels.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('暂无渠道交易数据', style: TextStyle(color: Colors.grey)),
                )
              : Column(
                  children: r.paymentChannels.map((ch) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(ch.channelLabel, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${ch.orderCount} 笔', style: context.captionStyle),
                              AmountText(ch.amount, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (ch.percentage / 100.0).clamp(0.0, 1.0),
                                    backgroundColor: context.palette.border,
                                    color: context.palette.brand,
                                    minHeight: 5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 45,
                                child: Text(
                                  '${ch.percentage.toStringAsFixed(1)}%',
                                  style: context.captionStyle.copyWith(fontSize: 11),
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: MobileMetrics.cardGap),

        // 4. 收银钱箱与现金盘点
        _buildSectionCard(
          context,
          title: '🪙 收银钱箱与现金盘点',
          child: Column(
            children: [
              _infoRow('开箱备用金', '¥${r.cashDrawer.openingFloat.toStringAsFixed(2)}'),
              _infoRow('现金实收 (Cash In)', '¥${r.cashDrawer.cashIn.toStringAsFixed(2)}'),
              _infoRow('现金退款 (Cash Refund)', '¥${r.cashDrawer.cashRefund.toStringAsFixed(2)}'),
              _infoRow('理论应有现金', '¥${r.cashDrawer.theoreticalCash.toStringAsFixed(2)}'),
              _infoRow('实际盘点现金', '¥${r.cashDrawer.countedCash.toStringAsFixed(2)}'),
              const Divider(),
              _infoRow(
                '长短款差额 (Variance)',
                '¥${r.cashDrawer.variance.toStringAsFixed(2)} (${r.cashDrawer.variance == 0 ? '账实相符' : (r.cashDrawer.variance > 0 ? '长款' : '短款')})',
                valueColor: r.cashDrawer.variance == 0 ? context.palette.success : context.palette.danger,
                isBold: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: MobileMetrics.cardGap),

        // 5. 就餐方式与订单类型分布
        _buildSectionCard(
          context,
          title: '🍽️ 就餐方式与订单类型',
          child: Column(
            children: r.orderTypes.map((ot) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(ot.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${ot.orderCount} 单', style: context.captionStyle),
                    Text('¥${ot.amount.toStringAsFixed(2)} (${ot.percentage.toStringAsFixed(1)}%)',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: MobileMetrics.cardGap),

        // 6. 会员储值与运营简报
        _buildSectionCard(
          context,
          title: '👑 会员储值与运营',
          child: Column(
            children: [
              _infoRow('今日会员充值总额', '¥${r.member.rechargeTotal.toStringAsFixed(2)}', valueColor: context.palette.brand),
              _infoRow('充值笔数', '${r.member.rechargeCount} 笔'),
              _infoRow('充值本金 (实际入账)', '¥${r.member.rechargePrincipal.toStringAsFixed(2)}'),
              _infoRow('充值赠送支出', '¥${r.member.rechargeGift.toStringAsFixed(2)}'),
              _infoRow('储值消费总额', '¥${r.member.memberConsumption.toStringAsFixed(2)}'),
              _infoRow('当期新增会员', '+${r.member.newMembers} 人'),
            ],
          ),
        ),
        const SizedBox(height: MobileMetrics.cardGap),

        // 7. 异常与风控审计
        _buildSectionCard(
          context,
          title: '🛡️ 异常与风控审计',
          child: Column(
            children: [
              _infoRow('反结账/重开次数', '${r.exceptions.uncheckoutCount} 次 (¥${r.exceptions.uncheckoutAmount.toStringAsFixed(2)})'),
              _infoRow('整单/部分退款', '${r.exceptions.refundCount} 笔 (¥${r.exceptions.refundAmount.toStringAsFixed(2)})',
                  valueColor: r.exceptions.refundCount > 0 ? context.palette.danger : null),
              _infoRow('赠菜 / 免单合计', '${r.exceptions.freeDishesCount} 份 (¥${r.exceptions.freeDishesAmount.toStringAsFixed(2)})'),
              _infoRow('手工折扣与抹零', '¥${r.exceptions.discountAmount.toStringAsFixed(2)}'),
            ],
          ),
        ),
        const SizedBox(height: MobileMetrics.cardGap),

        // 8. 菜品热销榜 TOP 10
        _buildSectionCard(
          context,
          title: '🔥 热销菜品 TOP 10',
          child: r.topDishes.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('暂无菜品销售数据', style: TextStyle(color: Colors.grey)),
                )
              : Column(
                  children: r.topDishes.map((dish) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            alignment: Alignment.center,
                            child: Text(
                              '#${dish.rank}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: dish.rank <= 3 ? context.palette.warning : context.palette.textSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              dish.dishName,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${dish.quantity} 份', style: context.captionStyle),
                          const SizedBox(width: 12),
                          AmountText(dish.amount, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
        const SizedBox(height: MobileMetrics.space2xl),
      ],
    );
  }

  void _showPrintPreview(BuildContext context, String text) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🖨️ 热敏小票打印预览'),
        content: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(12),
            color: Colors.black12,
            child: Text(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, {required String title, required Widget child}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MobileMetrics.radiusCard),
        side: BorderSide(color: context.palette.border),
      ),
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: MobileTypography.sectionTitle.copyWith(fontWeight: FontWeight.bold)),
            const Divider(),
            child,
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, _ReportSummary s) {
    return Column(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: MobileMetrics.cardGap,
          crossAxisSpacing: MobileMetrics.cardGap,
          childAspectRatio: 1.6,
          children: [
            _metric(context, '营业额', AmountText(s.revenue)),
            _metric(context, '订单数', Text('${s.orderCount}', style: _valueStyle(context))),
            _metric(context, '客单价', AmountText(s.avgOrderAmount)),
            _metric(
              context,
              '退款金额',
              AmountText(
                s.refundAmount,
                style: _valueStyle(context).copyWith(color: context.palette.danger),
              ),
            ),
            _metric(
              context,
              '优惠合计',
              AmountText(
                s.discountAmount,
                style: _valueStyle(context).copyWith(
                  color: context.palette.textSecondary,
                  fontSize: 24,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  TextStyle _valueStyle(BuildContext context) => MobileTypography.displayAmount.copyWith(
        color: context.palette.brandInk,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _metric(BuildContext context, String label, Widget child) {
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: context.captionStyle),
            const SizedBox(height: MobileMetrics.spaceSm),
            child,
          ],
        ),
      ),
    );
  }
}

/// 收银员业绩（PRD F06.5）：默认本人（JWT 过滤），老板/店长可切换查看全部。
class _CashierTab extends ConsumerStatefulWidget {
  const _CashierTab();

  @override
  ConsumerState<_CashierTab> createState() => _CashierTabState();
}

class _CashierTabState extends ConsumerState<_CashierTab> {
  bool _allCashiers = false;

  Future<List<Map<String, Object?>>> _load() async {
    final client = ref.read(apiClientProvider);
    final now = DateTime.now();
    String f(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final data = await client.get(
      reportCashierPerformanceEndpoint,
      query: {
        'startDate': f(DateTime(now.year, now.month, 1)),
        'endDate': f(now),
        if (_allCashiers) 'scope': 'all',
      },
    );
    return objectList(data);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: ListView(
        padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
        children: [
          SwitchListTile(
            title: const Text('查看全部收银员'),
            subtitle: const Text('关闭时仅展示本人业绩'),
            value: _allCashiers,
            onChanged: (v) => setState(() => _allCashiers = v),
          ),
          const SizedBox(height: MobileMetrics.spaceSm),
          FutureBuilder<List<Map<String, Object?>>>(
            future: _load(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingSkeleton(height: 200);
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: '业绩加载失败：${snapshot.error}',
                  onRetry: () => setState(() {}),
                );
              }
              final rows = snapshot.data ?? const [];
              if (rows.isEmpty) {
                return const EmptyState(message: '本月暂无收银员业绩数据');
              }
              return Card(
                child: Column(
                  children: [
                    for (var i = 0; i < rows.length; i++) ...[
                      _row(context, rows[i]),
                      if (i < rows.length - 1) const Divider(height: 1),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, Map<String, Object?> row) {
    String s(Object? v) => v == null ? '' : '$v';
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final name = s(row['userName'] ?? row['adminName'] ?? row['cashierName'] ?? row['name'] ?? '收银员');
    final revenue = d(row['revenue'] ?? row['totalAmount'] ?? row['amount']);
    final orders = i(row['orderCount'] ?? row['count'] ?? row['orders']);
    return ListTile(
      title: Text(name),
      subtitle: Text('${orders} 单', style: context.captionStyle),
      trailing: AmountText(revenue, style: MobileTypography.itemTitle),
    );
  }
}

/// 菜品销量榜（PRD F06.6 排行）。
class _DishRankingTab extends ConsumerStatefulWidget {
  const _DishRankingTab();

  @override
  ConsumerState<_DishRankingTab> createState() => _DishRankingTabState();
}

class _DishRankingTabState extends ConsumerState<_DishRankingTab> {
  Future<List<Map<String, Object?>>> _load() async {
    final client = ref.read(apiClientProvider);
    final now = DateTime.now();
    String f(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    final data = await client.get(
      reportDishRankingEndpoint,
      query: {
        'startDate': f(DateTime(now.year, now.month, 1)),
        'endDate': f(now),
      },
    );
    return objectList(data);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => setState(() {}),
      child: FutureBuilder<List<Map<String, Object?>>>(
        future: _load(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ErrorState(
              message: '排行加载失败：${snapshot.error}',
              onRetry: () => setState(() {}),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return const EmptyState(message: '本月暂无菜品销量数据');
          }
          return ListView.builder(
            padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
            itemCount: rows.length,
            itemBuilder: (context, index) {
              final row = rows[index];
              String s(Object? v) => v == null ? '' : '$v';
              double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
              int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
              final name = s(row['dishName'] ?? row['name'] ?? row['dish']);
              final quantity = i(row['quantity'] ?? row['soldCount'] ?? row['count']);
              final revenue = d(row['revenue'] ?? row['salesAmount'] ?? row['amount']);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: context.palette.brandSoft,
                  child: Text('${index + 1}', style: TextStyle(color: context.palette.brandInk)),
                ),
                title: Text(name),
                subtitle: Text('销量 $quantity', style: context.captionStyle),
                trailing: AmountText(revenue, style: MobileTypography.itemTitle),
              );
            },
          );
        },
      ),
    );
  }
}
