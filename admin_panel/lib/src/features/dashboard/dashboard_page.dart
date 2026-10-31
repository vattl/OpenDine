import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/formatters.dart';
import '../reports/data/report_repository.dart';
import '../reports/domain/dashboard_report.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.appState,
    required this.repository,
  });

  final AppState appState;
  final ReportRepository repository;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DashboardReport? report;
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DashboardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appState.currentShopId != widget.appState.currentShopId) {
      _load();
    }
  }

  Future<void> _load() async {
    final shopId = widget.appState.currentShopId;
    if (shopId == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final next = await widget.repository.loadDashboard(shopId: shopId);
      if (mounted) setState(() => report = next);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = report;
    return ListView(
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Card(
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('经营总览加载失败'),
              subtitle: Text(error!),
              trailing: TextButton(onPressed: _load, child: const Text('重试')),
            ),
          ),
        if (current != null)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _MetricCard(
                title: '今日营业净额',
                value: money(current.businessRevenueNet),
                caption: '营业数据实时汇总',
              ),
              _MetricCard(
                title: '今日订单',
                value: '${current.todayOrderCount}',
                caption: 'todayPaidOrderCount / todayCount',
              ),
              _MetricCard(
                title: '会员成功充值',
                value: money(current.successRechargeTotal),
                caption: '仅汇总 status=success 流水',
              ),
              _MetricCard(
                title: '待处理外卖',
                value: '${current.pendingTakeoutCount}',
                caption: '配送异常与履约状态',
              ),
            ],
          ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('迁移范围', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                const _ScopeRow('P0', '应用 Shell、登录认证、权限、门店上下文、用户查询、经营总览。'),
                const _ScopeRow('P1', '订单、桌台、点餐收银、会员充值。'),
                const _ScopeRow('P2', '商品菜单、优惠券、日结、支付、打印。'),
                const _ScopeRow('P3', '库存成本、智能备货、数据分析、账号权限、日志。'),
                const _ScopeRow('P4', 'KDS 客户端、WebSocket、外卖深度履约、第三方集成。'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.caption,
  });

  final String title;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 150,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.labelLarge),
              const Spacer(),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(caption, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScopeRow extends StatelessWidget {
  const _ScopeRow(this.phase, this.text);

  final String phase;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 48, child: Chip(label: Text(phase))),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
