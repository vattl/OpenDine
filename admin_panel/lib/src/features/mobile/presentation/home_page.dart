import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/api_providers.dart';
import '../data/auth_state.dart';
import '../data/dashboard_repository.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 首页唯一数据源：`GET /admin/report/dashboard`（服务端聚合运营看板）。
/// 默认读取最近已完成结算日；不再调用 analytics/ranking 等其它端点。
final todaySummaryProvider = FutureProvider<DashboardSummary>(
  (ref) => ref.watch(dashboardRepositoryProvider).loadDashboardSummary(),
);

/// 员工工作台概览：`GET /admin/order/todayCount` + `/todayUnsettledAmount` + 桌台状态。
/// 仅暴露订单数/待结/待清台，不包含营收净额（PRD F02 权限收敛）。
final staffSummaryProvider = FutureProvider<StaffSummary>(
  (ref) => ref.watch(dashboardRepositoryProvider).loadStaffSummary(),
);

/// 指标卡数值样式：28px 加粗等宽数字 + 加深橙（#FF7A00 白底仅 2.6:1，
/// 大字号也需 ≥3:1，统一用 brandInk 4.6:1，原型文档 §四.2A「暖橙高亮数值」）。
TextStyle _metricValueStyle(BuildContext context) =>
    MobileTypography.displayAmount.copyWith(
      color: context.palette.brandInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final boss = auth.isBoss;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(boss ? '经营看板' : '工作台'),
            Text(
              auth.currentShop?.name ?? '门店助手',
              style: context.captionStyle,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            tooltip: '通知',
            onPressed: () => context.push('/notifications'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(todaySummaryProvider);
          ref.invalidate(staffSummaryProvider);
        },
        child: ListView(
          padding: MobileMetrics.pagePadding.copyWith(
            top: MobileMetrics.spaceLg,
            bottom: MobileMetrics.spaceLg,
          ),
          children: boss
              ? [
                  const _BossQuickAccess(),
                  const SizedBox(height: MobileMetrics.cardGap),
                  const _TodayCards(),
                  const SizedBox(height: MobileMetrics.cardGap),
                  const _PayChannelCard(),
                  const SizedBox(height: MobileMetrics.cardGap),
                  const _RechargeCard(),
                  const SizedBox(height: MobileMetrics.cardGap),
                  const _RepurchaseCard(),
                ]
              : [
                  const _StaffQuickAccess(),
                  const SizedBox(height: MobileMetrics.cardGap),
                  const _StaffSummaryCard(),
                ],
        ),
      ),
    );
  }
}

/// 结算日经营概览：businessDay 全量六指标（营收/订单/客单价/退款/优惠/未收），
/// 底部标注服务端返回的最近已完成结算窗口。
class _TodayCards extends ConsumerWidget {
  const _TodayCards();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(todaySummaryProvider);
    return summary.when(
      loading: () => const LoadingSkeleton(height: 264),
      error: (error, _) => ErrorState(
        message: '经营数据加载失败，请下拉重试',
        onRetry: () => ref.invalidate(todaySummaryProvider),
      ),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: MobileMetrics.cardGap,
            crossAxisSpacing: MobileMetrics.cardGap,
            childAspectRatio: 1.6,
            children: [
              _Metric(
                label: '结算日营业额',
                child: AmountText(data.revenue, style: _metricValueStyle(context)),
              ),
              _Metric(
                label: '结算日订单',
                sub: '已结 ${data.paidOrderCount} 单',
                child: Text(
                  '${data.orderCount}',
                  style: _metricValueStyle(context),
                ),
              ),
              _Metric(
                label: '客单价',
                child: AmountText(data.avgOrderAmount, style: _metricValueStyle(context)),
              ),
              _Metric(
                label: '退款金额',
                child: AmountText(
                  data.refundAmount,
                  style: _metricValueStyle(context).copyWith(
                    color: context.palette.danger,
                  ),
                ),
              ),
              _Metric(
                label: '优惠合计',
                child: AmountText(
                  data.discountAmount,
                  style: _metricValueStyle(context).copyWith(
                    color: context.palette.textSecondary,
                    fontSize: 24,
                  ),
                ),
              ),
              _Metric(
                label: '未收金额',
                sub: '未结账订单待收款',
                child: AmountText(
                  data.unpaidAmount,
                  style: _metricValueStyle(context).copyWith(
                    color: context.palette.textSecondary,
                    fontSize: 24,
                  ),
                ),
              ),
            ],
          ),
          if (data.settlementWindowLabel != null) ...[
            const SizedBox(height: MobileMetrics.spaceSm),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MobileMetrics.spaceXs,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule_outlined,
                    size: 14,
                    color: context.palette.textMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    data.settlementWindowLabel!,
                    style: context.captionStyle,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 老板二级入口宫格：营业报表 / 员工管理 / 门店日结（对应 PRD F06/F07/F05，页面由 T-12..T-15 提供）。
class _BossQuickAccess extends ConsumerWidget {
  const _BossQuickAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final entries = <(IconData, String, String?, bool)>[
      (Icons.bar_chart_outlined, '营业报表', '/boss-reports', true),
      (Icons.group_outlined, '员工管理', '/boss-staff', auth.canManageStaff),
      (Icons.event_note_outlined, '门店日结', '/daily-settle', auth.hasPermission('order:config')),
      (Icons.settings_outlined, '门店设置', '/shop-settings', true),
    ];
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('经营入口', style: MobileTypography.sectionTitle),
            const SizedBox(height: MobileMetrics.spaceMd),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: MobileMetrics.spaceSm,
              crossAxisSpacing: MobileMetrics.spaceSm,
              childAspectRatio: 1.05,
              children: [
                for (final (icon, label, route, visible) in entries)
                  if (visible)
                    _QuickAccessCell(
                      icon: icon,
                      label: label,
                      onTap: () => context.push(route!),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 员工工作台大按钮（PRD F02.1）：快捷操作按权限显隐。
class _StaffQuickAccess extends ConsumerWidget {
  const _StaffQuickAccess();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final canOrder = auth.hasPermission('order:operate');
    final canViewOrder = auth.hasPermission('order:view');
    final canShift = auth.hasPermission('order:config');
    final entries = <(IconData, String, String?, bool)>[
      (Icons.table_restaurant_outlined, '桌台', '/tables', true),
      (Icons.add_shopping_cart_outlined, '开台点餐', '/tables', canOrder),
      (Icons.receipt_long_outlined, '今日订单', '/orders', canViewOrder),
      (Icons.assignment_return_outlined, '交接班', '/shift-handover', canShift),
      (Icons.notifications_outlined, '通知', '/notifications', true),
      (Icons.card_membership_outlined, '会员', '/member', auth.hasPermission('user:view')),
    ];
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('快捷操作', style: MobileTypography.sectionTitle),
            const SizedBox(height: MobileMetrics.spaceMd),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: MobileMetrics.spaceSm,
              crossAxisSpacing: MobileMetrics.spaceSm,
              childAspectRatio: 1.05,
              children: [
                for (final (icon, label, route, visible) in entries)
                  if (visible)
                    _QuickAccessCell(
                      icon: icon,
                      label: label,
                      onTap: () => context.push(route!),
                    ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAccessCell extends StatelessWidget {
  const _QuickAccessCell({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: MobileMetrics.controlRadius,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: context.palette.brandInk,
            size: MobileMetrics.iconSize + 2,
          ),
          const SizedBox(height: MobileMetrics.spaceXs),
          Text(
            label,
            style: MobileTypography.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// 员工工作台结算日概览（PRD F02.1）：结算日订单数 / 待结金额与单数 / 待清台数。
/// 不含营收净额等经营数据（权限收敛）。
class _StaffSummaryCard extends ConsumerWidget {
  const _StaffSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(staffSummaryProvider);
    return summary.when(
      loading: () => const LoadingSkeleton(height: 160),
      error: (error, _) => ErrorState(
        message: '结算日概览加载失败，请下拉重试',
        onRetry: () => ref.invalidate(staffSummaryProvider),
      ),
      data: (data) => Card(
        child: Padding(
          padding: MobileMetrics.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('今日概览', style: MobileTypography.sectionTitle),
              const SizedBox(height: MobileMetrics.spaceMd),
              Row(
                children: [
                  _staffMetric(context, '今日订单', '${data.todayOrderCount} 单'),
                  _staffMetric(context, '待结金额', AmountText(data.unsettledAmount, style: MobileTypography.itemTitle)),
                  _staffMetric(context, '待清台', '${data.pendingClearCount} 桌'),
                ],
              ),
              if (data.unsettledCount > 0) ...[
                const SizedBox(height: MobileMetrics.spaceMd),
                Text(
                  '另有 ${data.unsettledCount} 单未结账，请及时收银',
                  style: context.captionStyle,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static Widget _staffMetric(BuildContext context, String label, Object value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: MobileMetrics.spaceXs),
          if (value is String)
            Text(
              value,
              style: MobileTypography.itemTitle.copyWith(
                color: context.palette.brandInk,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            value as Widget,
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.child, this.sub});

  final String label;
  final Widget child;
  final String? sub;

  @override
  Widget build(BuildContext context) {
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
            if (sub != null) ...[
              const SizedBox(height: MobileMetrics.spaceXs),
              Text(sub!, style: context.captionStyle),
            ],
          ],
        ),
      ),
    );
  }
}

/// 收款构成：dashboard `revenueByPayChannel` 渠道实收（微信/支付宝/余额/现金/赠送）。
class _PayChannelCard extends ConsumerWidget {
  const _PayChannelCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(todaySummaryProvider);
    return summary.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) {
        final channels = data.payChannels.where((c) => c.amount > 0).toList();
        return Card(
          child: Padding(
            padding: MobileMetrics.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('收款构成', style: MobileTypography.sectionTitle),
                const SizedBox(height: MobileMetrics.spaceSm),
                if (channels.isEmpty)
                  Text('今日暂无收款', style: context.bodySecondaryStyle)
                else
                  for (var i = 0; i < channels.length; i++) ...[
                    _channelRow(context, channels[i]),
                    if (i < channels.length - 1) const Divider(height: 1),
                  ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _channelRow(BuildContext context, PayChannel channel) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MobileMetrics.spaceMd),
      child: Row(
        children: [
          Icon(
            _icon(channel.code),
            size: MobileMetrics.iconSize,
            color: context.palette.brandInk,
          ),
          const SizedBox(width: MobileMetrics.spaceMd),
          Expanded(child: Text(channel.label, style: MobileTypography.body)),
          AmountText(channel.amount, style: MobileTypography.itemTitle),
        ],
      ),
    );
  }

  static IconData _icon(String code) => switch (code) {
        'wechat' => Icons.qr_code_2,
        'alipay' => Icons.account_balance_wallet_outlined,
        'balance' => Icons.card_membership_outlined,
        'cash' => Icons.payments_outlined,
        'gift' => Icons.redeem_outlined,
        _ => Icons.payments_outlined,
      };
}

/// 今日会员充值：dashboard `todayMemberRecharge*`（入账=本金+赠送，仅 status=success）。
class _RechargeCard extends ConsumerWidget {
  const _RechargeCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(todaySummaryProvider);
    return summary.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) => Card(
        child: Padding(
          padding: MobileMetrics.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('今日会员充值', style: MobileTypography.sectionTitle),
                  ),
                  AmountText(
                    data.memberRechargeAmount,
                    style: _metricValueStyle(context).copyWith(fontSize: 24),
                  ),
                ],
              ),
              const SizedBox(height: MobileMetrics.spaceMd),
              Row(
                children: [
                  _stat(
                    context,
                    '本金',
                    _money(data.memberRechargePrincipal),
                  ),
                  _stat(context, '赠送', _money(data.memberRechargeGift)),
                  _stat(context, '成功笔数', '${data.memberRechargeCount} 笔'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _money(double v) => v.toStringAsFixed(2);

  static Widget _stat(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: MobileMetrics.spaceXs),
          Text(
            value,
            style: MobileTypography.itemTitle.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 复购与注册：dashboard 同响应顶层的复购率（周/月/新客）与注册人数。
class _RepurchaseCard extends ConsumerWidget {
  const _RepurchaseCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(todaySummaryProvider);
    return summary.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) => Card(
        child: Padding(
          padding: MobileMetrics.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('复购与注册', style: MobileTypography.sectionTitle),
              const SizedBox(height: MobileMetrics.spaceMd),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stat(
                    context,
                    '周复购率',
                    _pct(data.weeklyRepurchase.repurchaseRate),
                    sub:
                        '${data.weeklyRepurchase.repurchasedBuyers}/${data.weeklyRepurchase.buyers} 人',
                  ),
                  _stat(
                    context,
                    '月复购率',
                    _pct(data.monthlyRepurchase.repurchaseRate),
                    sub:
                        '${data.monthlyRepurchase.repurchasedBuyers}/${data.monthlyRepurchase.buyers} 人',
                  ),
                ],
              ),
              const SizedBox(height: MobileMetrics.spaceLg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _stat(
                    context,
                    '新客复购率',
                    _pct(data.newCustomerRepurchase.repurchaseRate),
                    sub:
                        '近${data.newCustomerRepurchase.windowDays}天 ${data.newCustomerRepurchase.repurchasedNewBuyers}/${data.newCustomerRepurchase.newBuyers} 人',
                  ),
                  _stat(
                    context,
                    '近7天注册',
                    '${data.register.sevenDays} 人',
                    sub:
                        '本月 ${data.register.thisMonth} · 上月 ${data.register.lastMonth} 人',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _pct(double rate) => '${(rate * 100).toStringAsFixed(1)}%';

  static Widget _stat(
    BuildContext context,
    String label,
    String value, {
    String? sub,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: MobileMetrics.spaceXs),
          Text(
            value,
            style: MobileTypography.itemTitle.copyWith(
              fontSize: 20,
              color: context.palette.brandInk,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: MobileMetrics.spaceXs),
            Text(sub, style: context.captionStyle),
          ],
        ],
      ),
    );
  }
}
