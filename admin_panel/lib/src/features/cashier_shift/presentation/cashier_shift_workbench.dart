import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../../cashier_shell/presentation/cashier_components.dart';
import '../../cashier_shell/presentation/cashier_tokens.dart';
import '../data/cashier_shift_repository.dart';
import '../domain/cashier_shift.dart';

class CashierShiftWorkbench extends StatelessWidget {
  const CashierShiftWorkbench({
    super.key,
    required this.shift,
    required this.workbench,
    required this.report,
    required this.dailySummary,
    required this.handoverResult,
    required this.canViewReport,
    required this.canSettleDaily,
    required this.busy,
    required this.onRefresh,
    required this.onStart,
    required this.onHandover,
    required this.onCashMovement,
    required this.onOpenShiftDetail,
    required this.onOpenShiftHistory,
    required this.onOpenPreviousCashEvents,
    required this.onOpenDailyClose,
    required this.onOpenZReport,
    required this.onOpenZReportHistory,
    required this.onReprintHandover,
    required this.now,
    this.reportLoading = false,
    this.reportError,
    this.onRetryReport,
    this.fallbackChannels,
    this.dailyPrecheck,
  });

  final CashierShift? shift;
  final CashierShiftWorkbenchData? workbench;
  final CashierTodayReport? report;
  final bool reportLoading;
  final String? reportError;
  final VoidCallback? onRetryReport;
  final Map<String, double>? fallbackChannels;
  final CashierDailySummary? dailySummary;
  final DailyPrecheckResult? dailyPrecheck;
  final CashierHandoverResult? handoverResult;
  final bool canViewReport;
  final bool canSettleDaily;
  final bool busy;
  final Future<void> Function() onRefresh;
  final VoidCallback onStart;
  final VoidCallback onHandover;
  final VoidCallback? onCashMovement;
  final VoidCallback? onOpenShiftDetail;
  final VoidCallback? onOpenShiftHistory;
  final VoidCallback? onOpenPreviousCashEvents;
  final VoidCallback? onOpenDailyClose;
  final VoidCallback? onOpenZReport;
  final VoidCallback? onOpenZReportHistory;
  final VoidCallback? onReprintHandover;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, viewport) => RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 32),
          children: [
            Center(
              child: ConstrainedBox(
                key: const Key('cashier-shift-content-frame'),
                constraints: BoxConstraints(
                  maxWidth: _contentMaxWidth(viewport.maxWidth),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WorkbenchHeading(
                      busy: busy,
                      onRefresh: onRefresh,
                      activeState: shift != null
                          ? 'active'
                          : (handoverResult != null ? 'closed' : 'inactive'),
                    ),
                    const SizedBox(height: 18),
                    _ResponsibilityHeader(
                      shift: shift,
                      workbench: workbench,
                      busy: busy,
                      onStart: onStart,
                      onHandover: onHandover,
                      onCashMovement: onCashMovement,
                    ),
                    if (handoverResult != null) ...[
                      const SizedBox(height: 16),
                      _HandoverResultBanner(
                        result: handoverResult!,
                        onViewReport: onOpenShiftDetail,
                        onReprint: onReprintHandover,
                      ),
                    ],
                    if (shift != null) ...[
                      const SizedBox(height: 16),
                      _MetricStrip(shift: shift!, now: now),
                    ],
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final stack = constraints.maxWidth < 920;
                        final drawer = _DrawerTaskCard(
                          fillHeight: !stack,
                          active: shift != null,
                          workbench: workbench,
                          shift: shift,
                          report: report,
                          onCashMovement: onCashMovement,
                          onHandover: shift == null ? null : onHandover,
                          onOpenDetail: onOpenShiftDetail,
                          onOpenHistory: onOpenShiftHistory,
                          onOpenCashEvents: onOpenPreviousCashEvents,
                        );
                        final daily = canSettleDaily
                            ? _BusinessDayTaskCard(
                                fillHeight: !stack,
                                summary: dailySummary,
                                readiness: workbench?.closeReadiness,
                                shiftOpen: shift != null,
                                onOpen: onOpenDailyClose,
                                onOpenZReport: onOpenZReport,
                                onOpenZReportHistory: onOpenZReportHistory,
                                dailyPrecheck: dailyPrecheck,
                              )
                            : null;
                        if (stack) {
                          return Column(
                            children: [
                              drawer,
                              if (daily != null) ...[
                                const SizedBox(height: 16),
                                daily,
                              ],
                            ],
                          );
                        }
                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: drawer),
                              if (daily != null) ...[
                                const SizedBox(width: 16),
                                Expanded(child: daily),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    _ChannelOverviewCard(
                      report: report,
                      canViewReport: canViewReport,
                      onOpenDailyClose: onOpenDailyClose,
                      loading: reportLoading,
                      error: reportError,
                      onRetry: onRetryReport,
                      fallbackChannels: fallbackChannels,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkbenchHeading extends StatelessWidget {
  const _WorkbenchHeading({
    required this.busy,
    required this.onRefresh,
    required this.activeState,
  });

  final bool busy;
  final Future<void> Function() onRefresh;
  final String activeState; // 'active', 'inactive', 'closed'

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CASHIER OPERATIONS · 班次与账本治理',
              style: TextStyle(
                color: context.cashier.inkMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                fontFamily: 'NotoSansSC',
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  '当班与日结',
                  style: TextStyle(
                    color: context.cashier.ink,
                    fontSize: 26,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.cashier.subtle,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: context.cashier.border),
                  ),
                  child: Text(
                    '双轨治理',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '先完成钱箱责任，再处理营业日关账；两套流程互不替代。',
              style: TextStyle(color: context.cashier.inkMuted, fontSize: 13),
            ),
          ],
        ),
      ),
      const SizedBox(width: 16),
      // Prototype state capsule bar
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: context.cashier.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: context.cashier.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatePill(
              context,
              label: '● 当班中',
              selected: activeState == 'active',
              dotColor: const Color(0xff22c55e),
            ),
            const SizedBox(width: 4),
            _buildStatePill(
              context,
              label: '○ 尚未开班',
              selected: activeState == 'inactive',
              dotColor: context.cashier.inkMuted,
            ),
            const SizedBox(width: 4),
            _buildStatePill(
              context,
              label: '✔ 已交班平账',
              selected: activeState == 'closed',
              dotColor: const Color(0xff3b82f6),
            ),
          ],
        ),
      ),
      const SizedBox(width: 10),
      Tooltip(
        message: '刷新当班与日结数据',
        child: SizedBox(
          height: 38,
          child: OutlinedButton.icon(
            onPressed: busy ? null : () => onRefresh(),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text(
              '刷新账本',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: context.cashier.ink,
              side: BorderSide(color: context.cashier.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _buildStatePill(
    BuildContext context, {
    required String label,
    required bool selected,
    required Color dotColor,
  }) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: selected ? context.cashier.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: selected ? context.cashier.surface : context.cashier.inkMuted,
      ),
    ),
  );
}

class _ResponsibilityHeader extends StatelessWidget {
  const _ResponsibilityHeader({
    required this.shift,
    required this.workbench,
    required this.busy,
    required this.onStart,
    required this.onHandover,
    required this.onCashMovement,
  });

  final CashierShift? shift;
  final CashierShiftWorkbenchData? workbench;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onHandover;
  final VoidCallback? onCashMovement;

  @override
  Widget build(BuildContext context) {
    final active = shift != null;
    return CashierCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 780;
          final identity = Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xff22c55e).withValues(alpha: 0.12)
                      : context.cashier.subtle,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active
                        ? const Color(0xff22c55e).withValues(alpha: 0.35)
                        : context.cashier.border,
                  ),
                ),
                child: Icon(
                  active ? Icons.schedule_rounded : Icons.pause_circle_outline,
                  color: active
                      ? const Color(0xff22c55e)
                      : context.cashier.inkMuted,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 10,
                      runSpacing: 6,
                      children: [
                        Text(
                          active ? '当班中' : '尚未开班',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: context.cashier.ink,
                          ),
                        ),
                        CashierStatusBadge(
                          label: active ? '钱箱已开启' : '钱箱未开启',
                          variant: active
                              ? CashierStatusBadgeVariant.success
                              : CashierStatusBadgeVariant.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      active
                          ? '${workbench?.operator?.fullIdentityText ?? workbench?.operator?.displayName ?? '当前收银员'} · 终端 ${workbench?.terminal?.displayName ?? shift?.terminalId ?? '当前终端'} · 钱箱 ${workbench?.drawer?.displayName ?? (shift?.drawerSessionId == null ? '已关联' : '#${shift!.drawerSessionId}')} · 营业日 ${workbench?.businessDay.isNotEmpty == true ? workbench!.businessDay : shift?.businessDay ?? '服务端当前营业日'}'
                          : '核对备用金后开班，系统将创建员工班次和钱箱会话。',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.end,
            children: [
              if (active && onCashMovement != null) ...[
                _WorkbenchButton(
                  key: const Key('cash-movement-open-button'),
                  label: '钱箱操作',
                  icon: Icons.currency_exchange_rounded,
                  onPressed: busy ? null : onCashMovement,
                ),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () {
                            HapticFeedback.heavyImpact();
                            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                              const SnackBar(
                                content: Text('钱箱电磁脉冲触发成功 (POP)'),
                                duration: Duration(seconds: 1),
                              ),
                            );
                          },
                    icon: const Icon(Icons.bolt_rounded, size: 18),
                    label: const Text(
                      '弹箱测试',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.cashier.ink,
                      side: BorderSide(color: context.cashier.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
              _WorkbenchButton(
                key: const Key('shift-handover-button'),
                label: active ? '盲盘交班' : '开班',
                icon: active
                    ? Icons.lock_outline_rounded
                    : Icons.play_arrow_rounded,
                danger: active,
                success: !active,
                selected: active,
                onPressed: busy ? null : (active ? onHandover : onStart),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [identity, const SizedBox(height: 16), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 20),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _WorkbenchButton extends StatelessWidget {
  const _WorkbenchButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.success = false,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
  final bool success;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final background = selected
        ? context.cashier.selected
        : danger
        ? context.cashier.danger
        : success
        ? context.cashier.success
        : context.cashier.surface;
    final foreground = danger || success || selected
        ? Colors.white
        : context.cashier.ink;
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledBackgroundColor: context.cashier.disabledBackground,
            disabledForegroundColor: context.cashier.disabledForeground,
            side: BorderSide(
              color: danger || success || selected
                  ? background
                  : context.cashier.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            textStyle: const TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          icon: Icon(icon, size: 18),
          label: Text(label),
        ),
      ),
    );
  }
}

class _MetricStrip extends StatelessWidget {
  const _MetricStrip({required this.shift, required this.now});

  final CashierShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final values = <(String, String, String)>[
      (
        '班次编号',
        '#${shift.id}',
        '钱箱会话 ${shift.drawerSessionId == null ? '--' : '#${shift.drawerSessionId}'} · 运行中',
      ),
      (
        '开班时间',
        _clock(shift.startTime),
        '已当班 ${_elapsed(shift.startTime, now)}',
      ),
      ('期初备用金', '¥ ${formatCashierMoney(shift.startCash)}', '现金流水建账基数'),
      ('本班订单', '${shift.orderCount} 笔', '去重支付账本已结'),
      ('净营收', '¥ ${formatCashierMoney(shift.totalAmount)}', '全渠道实收净额'),
    ];
    return CashierCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 620
              ? 2
              : constraints.maxWidth < 900
              ? 3
              : 5;
          final width = constraints.maxWidth / columns;
          return Wrap(
            children: [
              for (var index = 0; index < values.length; index++)
                SizedBox(
                  width: width,
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 96),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: context.cashier.border),
                        bottom: columns < 5 && index < values.length - columns
                            ? BorderSide(color: context.cashier.border)
                            : BorderSide.none,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          values[index].$1,
                          style: TextStyle(
                            color: context.cashier.inkMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          values[index].$2,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.5,
                            color: context.cashier.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          values[index].$3,
                          style: TextStyle(
                            color: context.cashier.inkMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DrawerTaskCard extends StatelessWidget {
  const _DrawerTaskCard({
    required this.fillHeight,
    required this.active,
    required this.workbench,
    this.shift,
    this.report,
    required this.onCashMovement,
    required this.onHandover,
    required this.onOpenDetail,
    required this.onOpenHistory,
    required this.onOpenCashEvents,
  });

  final bool fillHeight;
  final bool active;
  final CashierShiftWorkbenchData? workbench;
  final CashierShift? shift;
  final CashierTodayReport? report;
  final VoidCallback? onCashMovement;
  final VoidCallback? onHandover;
  final VoidCallback? onOpenDetail;
  final VoidCallback? onOpenHistory;
  final VoidCallback? onOpenCashEvents;

  @override
  Widget build(BuildContext context) {
    // Calculate theoretical cash formula values
    final startCash = shift?.startCash ?? 0.0;
    final cashSales =
        report?.revenueByPayChannel
            .where(
              (c) =>
                  c.code.toLowerCase().contains('cash') ||
                  c.label.contains('现金'),
            )
            .fold<double>(0.0, (sum, c) => sum + c.amount) ??
        0.0;
    const cashRefund = 0.0;
    const cashIn = 0.0;
    const cashOut = 0.0;
    final theoryCash = startCash + cashSales - cashRefund + cashIn - cashOut;

    return CashierCard(
      key: const Key('cashier-drawer-governance-card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.point_of_sale_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      '当前钱箱',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CashierStatusBadge(
                      label: active ? '会话正常' : '未开启',
                      variant: active
                          ? CashierStatusBadgeVariant.success
                          : CashierStatusBadgeVariant.neutral,
                    ),
                  ],
                ),
              ),
              Text(
                'DRAWER-01 · 终端 ${workbench?.terminal?.displayName ?? shift?.terminalId ?? 'POS-01'}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.cashier.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '现金收支与短长款责任属于当前钱箱物理抽屉，交班时必须执行盲盘清点。',
            style: TextStyle(color: context.cashier.inkMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),

          // Theoretical Cash Formula Card (.shift-formula-card)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.cashier.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.cashier.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '钱箱理论现金余额 (账面现金)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                    Text(
                      '¥ ${formatCashierMoney(theoryCash)}',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: context.cashier.ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: context.cashier.subtle,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '开班备用金 ¥${formatCashierMoney(startCash)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.ink,
                        ),
                      ),
                      Text(
                        '+',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                      Text(
                        '现金实收 ¥${formatCashierMoney(cashSales)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.ink,
                        ),
                      ),
                      Text(
                        '-',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                      Text(
                        '现金退款 ¥${formatCashierMoney(cashRefund)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.ink,
                        ),
                      ),
                      Text(
                        '+',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                      Text(
                        '临时存入 ¥${formatCashierMoney(cashIn)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.ink,
                        ),
                      ),
                      Text(
                        '-',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                      Text(
                        '临时支出 ¥${formatCashierMoney(cashOut)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '上期钱箱: ${workbench?.previousShift != null ? "#${workbench!.previousShift!.sessionId} 正常平账" : "无"}',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.cashier.inkMuted,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '最近事件: ${workbench?.latestCashMovement != null ? '已入账' : '暂无'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3 Task Drawers (.shift-task-item)
          _TaskLinkRow(
            icon: Icons.assignment_outlined,
            title: '本班详情 / 钱箱实时明细报告',
            subtitle: '查看现金流推导、渠道汇总、退菜损耗与审计总表',
            actionLabel: '查看明细 →',
            onPressed: onOpenDetail,
          ),
          const SizedBox(height: 6),
          _TaskLinkRow(
            icon: Icons.swap_vert_circle_outlined,
            title: '最近现金动作',
            subtitle: _latestMovementLabel(workbench?.latestCashMovement),
            actionLabel: '查看流水 →',
            onPressed: onOpenCashEvents,
          ),
          const SizedBox(height: 6),
          _TaskLinkRow(
            actionKey: const Key('shift-detail-open-button'),
            icon: Icons.history_rounded,
            title: '历史交班报告',
            subtitle: _previousShiftLabel(workbench?.previousShift),
            actionLabel: '查看报告 →',
            onPressed: onOpenHistory,
          ),
          if (fillHeight) const Spacer() else const SizedBox(height: 12),

          // Bottom Bar
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.cashier.border)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: context.cashier.inkMuted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '现金事件实时写入不可变流水',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: active ? onCashMovement : null,
                  child: const Text('记录现金动作'),
                ),
                if (active) ...[
                  const SizedBox(width: 6),
                  FilledButton(
                    onPressed: onHandover,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text(
                      '开始点钞',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskLinkRow extends StatelessWidget {
  const _TaskLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPressed,
    this.actionKey,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;
  final Key? actionKey;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: context.cashier.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: context.cashier.border),
            ),
            child: Icon(icon, size: 18, color: context.cashier.ink),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: context.cashier.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.cashier.inkMuted,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            actionLabel,
            key: actionKey,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.cashier.inkMuted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BusinessDayTaskCard extends StatelessWidget {
  const _BusinessDayTaskCard({
    required this.fillHeight,
    required this.summary,
    required this.readiness,
    required this.shiftOpen,
    required this.onOpen,
    required this.onOpenZReport,
    required this.onOpenZReportHistory,
    this.dailyPrecheck,
  });

  final bool fillHeight;
  final CashierDailySummary? summary;
  final CashierCloseReadiness? readiness;
  final bool shiftOpen;
  final VoidCallback? onOpen;
  final VoidCallback? onOpenZReport;
  final VoidCallback? onOpenZReportHistory;
  final DailyPrecheckResult? dailyPrecheck;

  @override
  Widget build(BuildContext context) {
    final settled = summary?.settled == true;
    final hasBacklog =
        dailyPrecheck != null &&
        (dailyPrecheck!.hasPreviousUnclosedDay ||
            dailyPrecheck!.pendingDayCount > 1);
    final openDrawers = readiness?.openDrawerCount ?? (shiftOpen ? 1 : 0);

    return CashierCard(
      key: const Key('cashier-daily-close-governance-card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_rounded, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    const Text(
                      '营业日关账与日结治理',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    CashierStatusBadge(
                      label: settled ? '已日结' : '未日结',
                      variant: settled
                          ? CashierStatusBadgeVariant.success
                          : CashierStatusBadgeVariant.warning,
                    ),
                  ],
                ),
              ),
              Text(
                '营业日 ${summary?.statDate ?? '2026-10-26'}',
                style: TextStyle(
                  fontSize: 12,
                  color: context.cashier.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '营业日关账为全店汇总账务节点；需钱箱全部交班后方可执行日结，最终以关账快照为准。',
            style: TextStyle(color: context.cashier.inkMuted, fontSize: 12),
          ),
          if (hasBacklog) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xfffffbeb),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xfffde68a)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xffd97706),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '积压 ${dailyPrecheck!.pendingDayCount} 天未关账 · 必须先关账 ${dailyPrecheck!.statDate}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff92400e),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),

          // 4 Readiness Rows (.shift-readiness-row)
          _ReadinessRow(
            ok: openDrawers == 0,
            title: openDrawers == 0 ? '钱箱会话已关闭' : '仍有 $openDrawers 个钱箱正在当班',
            subtitle: openDrawers == 0 ? '可进入日结预检' : '必须先完成交班关箱',
          ),
          const SizedBox(height: 6),
          _ReadinessRow(
            ok: readiness == null ? true : readiness!.unsettledOrderCount == 0,
            title: '未结桌台账单',
            subtitle: readiness == null
                ? '0 笔挂账桌台 (就绪)'
                : '${readiness!.unsettledOrderCount} 笔挂账桌台 (${readiness!.unsettledOrderCount == 0 ? '就绪' : '需结清'})',
          ),
          const SizedBox(height: 6),
          _ReadinessRow(
            ok: readiness == null ? true : readiness!.pendingPaymentCount == 0,
            title: '进行中线上支付',
            subtitle: readiness == null
                ? '0 笔待确认 (无异常)'
                : '${readiness!.pendingPaymentCount} 笔待确认 (${readiness!.pendingPaymentCount == 0 ? '无异常' : '需核对'})',
          ),
          const SizedBox(height: 6),
          _ReadinessRow(
            ok: readiness == null
                ? true
                : readiness!.unapprovedVarianceCount == 0,
            title: '长短款差异风控',
            subtitle: readiness == null
                ? '0 笔待审批长短款 (合规)'
                : '${readiness!.unapprovedVarianceCount} 笔待审批长短款 (${readiness!.unapprovedVarianceCount == 0 ? '合规' : '需主管审批'})',
          ),
          if (fillHeight) const Spacer() else const SizedBox(height: 12),

          // Bottom actions mirror the approved UI061 prototype.
          Container(
            padding: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.cashier.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    key: const Key('daily-close-open-button'),
                    onPressed: settled ? onOpenZReport : onOpen,
                    icon: Icon(
                      settled
                          ? Icons.description_outlined
                          : Icons.lock_outline_rounded,
                      size: 15,
                    ),
                    label: Text(settled ? '查看 Z 报表' : '营业日日结'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: TextButton.icon(
                    key: const Key('daily-close-current-z-button'),
                    onPressed: onOpenZReport,
                    icon: const Icon(Icons.bar_chart_rounded, size: 15),
                    label: const Text('当日 Z 报表'),
                  ),
                ),
                if (onOpenZReportHistory != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: TextButton.icon(
                      key: const Key('z-report-history-open-button'),
                      onPressed: onOpenZReportHistory,
                      icon: const Icon(Icons.archive_outlined, size: 15),
                      label: const Text('归档'),
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

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({
    required this.ok,
    required this.title,
    required this.subtitle,
  });

  final bool? ok;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final dotColor = ok == null
        ? context.cashier.inkMuted
        : ok!
        ? const Color(0xff22c55e)
        : const Color(0xffef4444);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: context.cashier.ink,
              ),
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ok == true
                  ? const Color(0xff22c55e)
                  : context.cashier.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelOverviewCard extends StatelessWidget {
  const _ChannelOverviewCard({
    required this.report,
    required this.canViewReport,
    required this.onOpenDailyClose,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.fallbackChannels,
  });

  final CashierTodayReport? report;
  final bool canViewReport;
  final VoidCallback? onOpenDailyClose;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Map<String, double>? fallbackChannels;

  @override
  Widget build(BuildContext context) {
    return CashierCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '今日支付渠道概览',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '当前营业日实时实收净额分布，最终以日结快照为准。',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (onOpenDailyClose != null)
                TextButton.icon(
                  onPressed: onOpenDailyClose,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                  label: const Text('查看关账明细 →', style: TextStyle(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!canViewReport)
            Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 18,
                  color: context.cashier.inkMuted,
                ),
                const SizedBox(width: 8),
                Text(
                  '暂无今日简报权限',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.cashier.inkMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '缺少 report:view',
                  style: TextStyle(
                    color: context.cashier.inkMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            )
          else if (loading && report == null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                  '正在加载今日渠道数据...',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                ),
              ],
            )
          else if (error != null && report == null)
            _buildErrorOrFallback(context)
          else if (report == null)
            Row(
              children: [
                Icon(
                  Icons.inbox_outlined,
                  size: 18,
                  color: context.cashier.inkMuted,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    '暂无今日支付渠道数据',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('刷新'),
                  ),
              ],
            )
          else
            _buildReportContent(context, report!),
        ],
      ),
    );
  }

  Widget _buildErrorOrFallback(BuildContext context) {
    if (fallbackChannels != null && fallbackChannels!.isNotEmpty) {
      final totalAmount = fallbackChannels!.values.fold<double>(
        0.0,
        (sum, item) => sum + item,
      );
      final tiles = <Widget>[
        _ChannelTile(
          label: '日结净额',
          value: '¥ ${formatCashierMoney(totalAmount)}',
          color: context.cashier.ink,
        ),
        for (final entry in fallbackChannels!.entries)
          _ChannelTile(
            label: cashierChannelLabel(entry.key),
            value: '¥ ${formatCashierMoney(entry.value)}',
            note: totalAmount <= 0
                ? null
                : '${(entry.value / totalAmount * 100).toStringAsFixed(1)}%',
            color: _colorForChannel(entry.key),
            progress: totalAmount <= 0 ? 0 : entry.value / totalAmount,
          ),
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.cashier.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: context.cashier.warning.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: context.cashier.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '实时看板暂不可用，已自动切换至日结对账通道数据',
                    style: TextStyle(fontSize: 12, color: context.cashier.ink),
                  ),
                ),
                if (onRetry != null)
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('重试实时', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth < 620 ? 2 : 4;
              final width =
                  (constraints.maxWidth - 10 * (columns - 1)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final tile in tiles) SizedBox(width: width, child: tile),
                ],
              );
            },
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 20,
            color: context.cashier.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '支付渠道概览加载失败',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  error ?? '网络或服务异常',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.cashier.inkMuted,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 8),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReportContent(BuildContext context, CashierTodayReport value) {
    final totalRev = value.revenue > 0 ? value.revenue : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final tiles = <Widget>[
              _ChannelTile(
                label: '今日订单',
                value: '${value.totalOrderCount} 笔',
                color: const Color(0xff6366f1),
              ),
              _ChannelTile(
                label: '营业收入',
                value: '¥ ${formatCashierMoney(value.revenue)}',
                color: const Color(0xff0ea5e9),
              ),
              _ChannelTile(
                label: '会员充值',
                value: '¥ ${formatCashierMoney(value.memberRechargeAmount)}',
                note: value.memberRechargeAmount <= 0 ? null : '营业时间充值',
                color: const Color(0xffa855f7),
              ),
              _ChannelTile(
                label: '待支付',
                value:
                    '${value.unpaidOrderCount} 单 · ¥ ${formatCashierMoney(value.unpaidAmount)}',
                note: value.unpaidAmount <= 0 ? null : '未结账',
                color: const Color(0xfff59e0b),
              ),
              _ChannelTile(
                label: '优惠金额',
                value: '¥ ${formatCashierMoney(value.discountAmount)}',
                note: value.discountAmount <= 0 ? null : '折扣让利',
                color: const Color(0xffef4444),
              ),
              for (final channel in value.revenueByPayChannel)
                _ChannelTile(
                  label: channel.label,
                  value: '¥ ${formatCashierMoney(channel.amount)}',
                  note: value.revenue <= 0
                      ? null
                      : '${(channel.amount / totalRev * 100).toStringAsFixed(1)}%',
                  color: _colorForChannel(channel.label),
                  progress: value.revenue <= 0
                      ? 0.0
                      : (channel.amount / totalRev).clamp(0.0, 1.0),
                ),
            ];
            final columns = constraints.maxWidth < 620
                ? 2
                : constraints.maxWidth < 980
                ? 3
                : 5;
            final width = (constraints.maxWidth - 10 * (columns - 1)) / columns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final tile in tiles) SizedBox(width: width, child: tile),
              ],
            );
          },
        ),

        const SizedBox(height: 16),

        // Business Deepdive Trio (.shift-deepdive-grid)
        LayoutBuilder(
          builder: (context, constraints) {
            final stack = constraints.maxWidth < 880;
            final box1 = _buildDeepdiveBox(
              context,
              icon: Icons.credit_card_rounded,
              title: '会员充值明细 (Member Recharge)',
              rows: [
                ('充值成功笔数', '${value.memberRechargeAmount > 0 ? 1 : 0} 笔'),
                (
                  '实收充值本金',
                  '¥${formatCashierMoney(value.memberRechargeAmount)}',
                ),
                ('赠送权益金', '¥0.00'),
                (
                  '会员账户实际入账',
                  '¥${formatCashierMoney(value.memberRechargeAmount)}',
                ),
              ],
              highlightLast: true,
              lastColor: const Color(0xffa855f7),
            );

            final originalSum =
                value.revenue + value.discountAmount + value.refundAmount;
            final box2 = _buildDeepdiveBox(
              context,
              icon: Icons.receipt_long_rounded,
              title: '订单原价与优惠汇总 (Sales Summary)',
              rows: [
                ('订单原始总额', '¥${formatCashierMoney(originalSum)}'),
                ('整单与单品优惠', '-¥${formatCashierMoney(value.discountAmount)}'),
                ('售后退款冲减', '-¥${formatCashierMoney(value.refundAmount)}'),
                ('全单净实收营收', '¥${formatCashierMoney(value.revenue)}'),
              ],
              highlightLast: true,
              lastColor: const Color(0xff22c55e),
            );

            final box3 = _buildDeepdiveBox(
              context,
              icon: Icons.soup_kitchen_rounded,
              title: '退菜与赠菜损耗 (Dish Operations)',
              rows: [
                ('退菜道数 / 金额', '0 道 · ¥0.00'),
                ('退菜主要原因', '超时未上菜 (0) · 点错 (0)'),
                ('赠菜道数 / 金额', '0 道 · ¥0.00'),
                ('赠菜主要项目', '餐前开胃凉菜 · 会员例汤'),
              ],
              highlightLast: false,
            );

            if (stack) {
              return Column(
                children: [
                  box1,
                  const SizedBox(height: 10),
                  box2,
                  const SizedBox(height: 10),
                  box3,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: box1),
                const SizedBox(width: 12),
                Expanded(child: box2),
                const SizedBox(width: 12),
                Expanded(child: box3),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildDeepdiveBox(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<(String, String)> rows,
    required bool highlightLast,
    Color? lastColor,
  }) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.cashier.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: context.cashier.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: context.cashier.ink),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.cashier.ink,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Divider(height: 1, color: context.cashier.border),
        const SizedBox(height: 10),
        for (var i = 0; i < rows.length; i++) ...[
          if (i == rows.length - 1 && highlightLast) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.only(top: 6),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: context.cashier.border,
                    style: BorderStyle.solid,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rows[i].$1,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: lastColor ?? context.cashier.ink,
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    rows[i].$1,
                    style: TextStyle(
                      fontSize: 11,
                      color: context.cashier.inkMuted,
                    ),
                  ),
                  Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: context.cashier.ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    ),
  );

  Color _colorForChannel(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('wechat') || lower.contains('微信')) {
      return const Color(0xff22c55e);
    }
    if (lower.contains('alipay') || lower.contains('支付宝')) {
      return const Color(0xff3b82f6);
    }
    if (lower.contains('cash') || lower.contains('现金')) {
      return const Color(0xfff59e0b);
    }
    if (lower.contains('member') || lower.contains('会员')) {
      return const Color(0xffa855f7);
    }
    if (lower.contains('credit') ||
        lower.contains('挂账') ||
        lower.contains('赊销')) {
      return const Color(0xffec4899);
    }
    return const Color(0xff6366f1);
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.label,
    required this.value,
    this.note,
    this.color,
    this.progress,
  });

  final String label;
  final String value;
  final String? note;
  final Color? color;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final channelColor = color ?? context.cashier.ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: context.cashier.subtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: context.cashier.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: channelColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: context.cashier.inkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (note != null)
                Text(
                  note!,
                  style: TextStyle(
                    color: context.cashier.inkMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.3,
              color: context.cashier.ink,
            ),
          ),
          if (progress != null) ...[
            const SizedBox(height: 8),
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: context.cashier.border,
                borderRadius: BorderRadius.circular(2),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: progress!.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: channelColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HandoverResultBanner extends StatelessWidget {
  const _HandoverResultBanner({
    required this.result,
    required this.onViewReport,
    required this.onReprint,
  });
  final CashierHandoverResult result;
  final VoidCallback? onViewReport;
  final VoidCallback? onReprint;

  @override
  Widget build(BuildContext context) => CashierCard(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xff22c55e),
              size: 26,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '交班完成',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xff22c55e),
                      ),
                    ),
                    SizedBox(width: 8),
                    CashierStatusBadge(
                      label: '账实相符 (零差额平账)',
                      variant: CashierStatusBadgeVariant.success,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${result.orderCount} 笔',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.cashier.ink,
                      ),
                    ),
                    Text(
                      '¥ ${formatCashierMoney(result.totalAmount)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: context.cashier.ink,
                      ),
                    ),
                    if (result.countedCash != null)
                      Text(
                        '盘点 ¥ ${formatCashierMoney(result.countedCash)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                    Text(
                      '备用金已归还',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.cashier.inkMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              key: const Key('handover-view-report-button'),
              onPressed: onViewReport,
              child: const Text('查看交班报告'),
            ),
            TextButton(onPressed: onReprint, child: const Text('补打交班小票')),
          ],
        ),
      ],
    ),
  );
}

class CashierShiftHistoryPage extends StatefulWidget {
  const CashierShiftHistoryPage({
    super.key,
    required this.repository,
    this.shopId,
  });

  final CashierShiftRepository repository;
  final int? shopId;

  @override
  State<CashierShiftHistoryPage> createState() =>
      _CashierShiftHistoryPageState();
}

class _CashierShiftHistoryPageState extends State<CashierShiftHistoryPage> {
  final List<ShiftSummaryReport> reports = [];
  int? cursor;
  bool hasMore = false;
  bool loading = true;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (!hasMore || loading)) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await widget.repository.loadShiftReports(
        shopId: widget.shopId,
        cursor: more ? cursor : null,
      );
      if (!mounted) return;
      setState(() {
        if (!more) reports.clear();
        reports.addAll(page.items);
        cursor = page.nextCursor;
        hasMore = page.hasMore;
        loading = false;
      });
    } catch (exception) {
      if (mounted) {
        setState(() {
          error = exception;
          loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => _SecondaryScaffold(
    eyebrow: 'CLOSED DRAWER SESSIONS',
    sectionLabel: '历史交班',
    title: '历史交班报告',
    subtitle: '仅展示已完成盲盘并关闭的钱箱会话。',
    onBack: () => Navigator.of(context).pop(),
    child: error != null && reports.isEmpty
        ? CashierStateView(
            state: CashierViewState.error,
            title: '历史交班加载失败',
            message: '$error',
            actionLabel: '重试',
            onAction: _load,
          )
        : loading && reports.isEmpty
        ? const CashierStateView(
            state: CashierViewState.loading,
            title: '正在读取历史交班',
            message: '请稍候',
          )
        : reports.isEmpty
        ? const CashierStateView(
            state: CashierViewState.empty,
            title: '暂无历史交班',
            message: '完成首个盲盘交班后会显示在这里。',
          )
        : Column(
            children: [
              for (final report in reports) ...[
                CashierCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '班次 #${report.sessionId} · ${report.operatorName ?? '操作员 #${report.operatorId ?? '--'}'}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${report.businessDay ?? '--'} · ${report.terminalName ?? report.terminalId ?? '未命名终端'} / ${report.drawerName ?? report.drawerCode ?? '未命名钱箱'} · ${_dateTime(report.closedAt)}',
                              style: TextStyle(color: context.cashier.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      CashierStatusBadge(
                        label: report.variance == 0
                            ? '已平账'
                            : '差额 ${_signedMoney(report.variance)}',
                        variant: report.variance == 0
                            ? CashierStatusBadgeVariant.success
                            : CashierStatusBadgeVariant.warning,
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => CashierShiftDetailPage(
                              sessionId: report.sessionId,
                              repository: widget.repository,
                              shopId: widget.shopId,
                            ),
                          ),
                        ),
                        child: const Text('查看报告'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute(
                            builder: (_) => CashierCashEventsPage(
                              sessionId: report.sessionId,
                              repository: widget.repository,
                              shopId: widget.shopId,
                            ),
                          ),
                        ),
                        child: const Text('现金流水'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (hasMore)
                TextButton.icon(
                  onPressed: loading ? null : () => _load(more: true),
                  icon: const Icon(Icons.expand_more_rounded),
                  label: Text(loading ? '加载中…' : '加载更多'),
                ),
            ],
          ),
  );
}

class CashierCashEventsPage extends StatefulWidget {
  const CashierCashEventsPage({
    super.key,
    required this.sessionId,
    required this.repository,
    this.shopId,
  });

  final int sessionId;
  final CashierShiftRepository repository;
  final int? shopId;

  @override
  State<CashierCashEventsPage> createState() => _CashierCashEventsPageState();
}

class _CashierCashEventsPageState extends State<CashierCashEventsPage> {
  CashierCashEventPage? page;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.repository.loadCashEvents(
        widget.sessionId,
        shopId: widget.shopId,
        limit: 100,
      );
      if (mounted) setState(() => page = value);
    } catch (exception) {
      if (mounted) setState(() => error = exception);
    }
  }

  @override
  Widget build(BuildContext context) => _SecondaryScaffold(
    eyebrow: 'IMMUTABLE CASH EVENTS',
    sectionLabel: '现金流水',
    title: '班次 #${widget.sessionId} · 现金流水',
    subtitle: '仅已关闭班次可查看金额；当前班次继续保持盲盘脱敏。',
    onBack: () => Navigator.of(context).pop(),
    child: error != null
        ? CashierStateView(
            state: CashierViewState.error,
            title: '现金流水加载失败',
            message: '$error',
            actionLabel: '重试',
            onAction: _load,
          )
        : page == null
        ? const CashierStateView(
            state: CashierViewState.loading,
            title: '正在读取现金流水',
            message: '请稍候',
          )
        : page!.items.isEmpty
        ? const CashierStateView(
            state: CashierViewState.empty,
            title: '暂无现金流水',
            message: '此班次没有现金事件。',
          )
        : CashierCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var index = 0; index < page!.items.length; index++)
                  _CashEventRow(
                    event: page!.items[index],
                    showDivider: index < page!.items.length - 1,
                  ),
              ],
            ),
          ),
  );
}

class _CashEventRow extends StatelessWidget {
  const _CashEventRow({required this.event, required this.showDivider});

  final CashierCashEvent event;
  final bool showDivider;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    decoration: BoxDecoration(
      border: showDivider
          ? Border(bottom: BorderSide(color: context.cashier.border))
          : null,
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _cashEventLabel(event.type),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                '${_dateTime(event.occurredAt)} · ${event.operatorName ?? '操作员待返回'} · ${event.referenceNo ?? '流水号待返回'}',
                style: TextStyle(color: context.cashier.inkMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          event.amountHidden || event.amount == null
              ? '金额已隐藏'
              : _signedMoney(event.amount!),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class CashierZReportHistoryListPage extends StatefulWidget {
  const CashierZReportHistoryListPage({
    super.key,
    required this.repository,
    required this.onOpenReport,
    this.onOpenDailyClose,
    this.shopId,
  });

  final CashierShiftRepository repository;
  final ValueChanged<String> onOpenReport;
  final ValueChanged<String>? onOpenDailyClose;
  final int? shopId;

  @override
  State<CashierZReportHistoryListPage> createState() =>
      _CashierZReportHistoryListPageState();
}

class _CashierZReportHistoryListPageState
    extends State<CashierZReportHistoryListPage> {
  CashierZReportHistoryPage? page;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.repository.loadZReports(
        shopId: widget.shopId,
        limit: 100,
      );
      if (mounted) setState(() => page = value);
    } catch (exception) {
      if (mounted) setState(() => error = exception);
    }
  }

  void _open(String businessDay) {
    Navigator.of(context).pop();
    widget.onOpenReport(businessDay);
  }

  void _goToDailyClose(String businessDay) {
    Navigator.of(context).pop();
    widget.onOpenDailyClose?.call(businessDay);
  }

  CashierStatusBadgeVariant _badgeVariant(String state) {
    switch (state.toUpperCase()) {
      case 'CLOSED':
        return CashierStatusBadgeVariant.success;
      case 'REOPENED':
        return CashierStatusBadgeVariant.warning;
      case 'PENDING':
      default:
        return CashierStatusBadgeVariant.warning;
    }
  }

  String _badgeLabel(String state) {
    switch (state.toUpperCase()) {
      case 'CLOSED':
        return '已结 (快照锁定)';
      case 'REOPENED':
        return '已重开';
      case 'PENDING':
      default:
        return '待日结';
    }
  }

  @override
  Widget build(BuildContext context) => _SecondaryScaffold(
    eyebrow: 'IMMUTABLE DAILY SNAPSHOTS',
    sectionLabel: '历史 Z 报表',
    title: '历史 Z 报表',
    subtitle: '按服务端连续营业日历及不可变关账快照重现，未关账营业日不伪造快照。',
    onBack: () => Navigator.of(context).pop(),
    child: error != null
        ? CashierStateView(
            state: CashierViewState.error,
            title: '历史 Z 报表加载失败',
            message: '$error',
            actionLabel: '重试',
            onAction: _load,
          )
        : page == null
        ? const CashierStateView(
            state: CashierViewState.loading,
            title: '正在读取历史 Z 报表',
            message: '请稍候',
          )
        : page!.items.isEmpty
        ? const CashierStateView(
            state: CashierViewState.empty,
            title: '暂无 Z 报表',
            message: '完成营业日关账后会显示在这里。',
          )
        : Column(
            children: [
              if ((page!.pendingDayCount > 1) ||
                  (page!.items.any((i) => i.closeState != 'CLOSED'))) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xfffffbeb),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xfffde68a)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        color: Color(0xffd97706),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          page!.pendingDayCount > 0
                              ? '当前共有 ${page!.pendingDayCount} 个营业日待日结。系统严格要求按时序流转，请优先处理标注「去日结」的最早待结日。'
                              : '连续营业日历概览。系统按时序关账，不可跨日跳结。',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xff92400e),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              for (final item in page!.items) ...[
                CashierCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  item.snapshotNo.isNotEmpty
                                      ? '${item.businessDay} · ${item.snapshotNo}'
                                      : item.businessDay,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (item.isNextCloseBusinessDay) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xffeff6ff),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: const Color(0xffbfdbfe),
                                      ),
                                    ),
                                    child: const Text(
                                      '最早待结日',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xff1d4ed8),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              item.closeState == 'PENDING'
                                  ? (item.canClose
                                        ? '未生成关账快照 · 请点击「去日结」完成该营业日关账'
                                        : '需先结更早营业日 · 营业数据待关账后锁定')
                                  : (item.closeState == 'REOPENED'
                                        ? '${item.orderCount} 笔 · 净销售额 ¥ ${formatCashierMoney(item.netSales)} · 快照已解除封锁待重新关账'
                                        : '${item.orderCount} 笔 · 净销售额 ¥ ${formatCashierMoney(item.netSales)} · ${_dateTime(item.closedAt)}'),
                              style: TextStyle(color: context.cashier.inkMuted),
                            ),
                          ],
                        ),
                      ),
                      CashierStatusBadge(
                        label: _badgeLabel(item.closeState),
                        variant: _badgeVariant(item.closeState),
                      ),
                      const SizedBox(width: 12),
                      if (item.canClose) ...[
                        FilledButton.tonal(
                          onPressed: () => _goToDailyClose(item.businessDay),
                          child: Text(
                            item.closeState == 'REOPENED' ? '重新日结' : '去日结',
                          ),
                        ),
                      ] else if (item.closeState == 'PENDING') ...[
                        const Text(
                          '需先结更早营业日',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xff94a3b8),
                          ),
                        ),
                      ],
                      if (item.closeState == 'CLOSED' || item.id != null) ...[
                        TextButton(
                          onPressed: () => _open(item.businessDay),
                          child: const Text('查看报表'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
  );
}

class CashierShiftDetailPage extends StatefulWidget {
  const CashierShiftDetailPage({
    super.key,
    required this.sessionId,
    required this.repository,
    this.shopId,
  });
  final int sessionId;
  final CashierShiftRepository repository;
  final int? shopId;

  @override
  State<CashierShiftDetailPage> createState() => _CashierShiftDetailPageState();
}

class _CashierShiftDetailPageState extends State<CashierShiftDetailPage> {
  ShiftSummaryReport? report;
  Object? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final value = await widget.repository.loadShiftReport(
        widget.sessionId,
        shopId: widget.shopId,
      );
      if (mounted) setState(() => report = value);
    } catch (e) {
      if (mounted) setState(() => error = e);
    }
  }

  @override
  Widget build(BuildContext context) => _SecondaryScaffold(
    eyebrow: 'CLOSED DRAWER SESSION',
    sectionLabel: '钱箱班次详情',
    title: report == null ? '钱箱班次详情' : '钱箱班次 #${report!.sessionId}',
    subtitle: '已关闭班次可查看完整现金恒等式；当前班次仍执行盲盘脱敏。',
    onBack: () => Navigator.of(context).pop(),
    trailing: Wrap(
      spacing: 10,
      children: [
        _WorkbenchButton(
          label: '重打交班小票',
          icon: Icons.print_outlined,
          onPressed: report == null ? null : () {},
        ),
        _WorkbenchButton(
          label: '返回工作台',
          icon: Icons.arrow_back_rounded,
          selected: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
    child: error != null
        ? CashierStateView(
            state: CashierViewState.error,
            title: '班次报告加载失败',
            message: '$error',
            actionLabel: '重试',
            onAction: _load,
          )
        : report == null
        ? const CashierStateView(
            state: CashierViewState.loading,
            title: '正在读取班次报告',
            message: '请稍候',
          )
        : _ShiftReportContent(report: report!),
  );
}

class _ShiftReportContent extends StatelessWidget {
  const _ShiftReportContent({required this.report});
  final ShiftSummaryReport report;

  @override
  Widget build(BuildContext context) => _DetailColumns(
    main: [
      CashierCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(child: _SectionTitle('班次身份')),
                CashierStatusBadge(
                  label: report.variance == 0 ? '已关闭 · 已平账' : '已关闭 · 有差异',
                  variant: report.variance == 0
                      ? CashierStatusBadgeVariant.success
                      : CashierStatusBadgeVariant.warning,
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              report.closedAt == null
                  ? '交班时间未提供'
                  : '${_dateTime(report.closedAt)} 完成交班',
              style: TextStyle(color: context.cashier.inkMuted),
            ),
            const SizedBox(height: 16),
            _InfoGrid(
              items: [
                (
                  '操作员',
                  report.operatorName ??
                      (report.operatorId == null
                          ? '未命名操作员'
                          : '#${report.operatorId}'),
                ),
                (
                  '终端 / 钱箱',
                  '${report.terminalName ?? report.terminalId ?? '未命名终端'} / ${report.drawerName ?? report.drawerCode ?? '未命名钱箱'}',
                ),
                ('营业日', report.businessDay ?? '--'),
                (
                  '持续时间',
                  report.durationSeconds > 0
                      ? _durationSeconds(report.durationSeconds)
                      : _duration(report.openedAt, report.closedAt),
                ),
              ],
            ),
          ],
        ),
      ),
      CashierCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('现金恒等式', icon: Icons.payments_outlined),
            const SizedBox(height: 14),
            _FormulaRow('期初备用金', report.openingFloat),
            _FormulaRow('现金销售', report.cashSales, prefix: '+'),
            _FormulaRow('现金退款', report.cashRefunds, prefix: '−'),
            _FormulaRow('零钱加钞', report.cashIn, prefix: '+'),
            _FormulaRow('现金支出', report.cashOut, prefix: '−'),
            _FormulaRow('大钞投库', report.cashDrop, prefix: '−'),
            const Divider(height: 22),
            _FormulaRow('系统应有现金', report.expectedCash, strong: true),
            _FormulaRow('实盘现金', report.countedCash, strong: true),
            _FormulaRow('长短款差额', report.variance, strong: true),
          ],
        ),
      ),
      CashierCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('本班支付渠道'),
            const SizedBox(height: 14),
            _ChannelTable(
              channels: {
                for (final item in report.channels) item.label: item.amount,
              },
              details: report.channels,
            ),
          ],
        ),
      ),
      if (report.memberRechargeSummary != null) ...[
        CashierCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('会员充值', icon: Icons.savings_outlined),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Expanded(child: Text('成功笔数')),
                    Text(
                      '${report.memberRechargeSummary!.successCount} 笔',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              _FormulaRow('充值本金', report.memberRechargeSummary!.principal),
              _FormulaRow('赠送金额', report.memberRechargeSummary!.gift),
              const Divider(height: 22),
              _FormulaRow(
                '会员入账合计',
                report.memberRechargeSummary!.creditedTotal,
                strong: true,
              ),
            ],
          ),
        ),
      ],
      if (report.orderSalesSummary != null) ...[
        CashierCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('交易明细', icon: Icons.receipt_long_outlined),
              const SizedBox(height: 6),
              Text(
                '已结订单 ${report.orderSalesSummary!.paidOrderCount} 单 · 总营收 ¥ ${formatCashierMoney(report.orderSalesSummary!.grossSales)}',
                style: TextStyle(color: context.cashier.inkMuted),
              ),
              const SizedBox(height: 14),
              _FormulaRow('总营收（订单原价）', report.orderSalesSummary!.grossSales),
              _FormulaRow(
                '优惠金额',
                report.orderSalesSummary!.discount,
                prefix: '−',
              ),
              _FormulaRow(
                '退款金额',
                report.orderSalesSummary!.refund,
                prefix: '−',
              ),
              _FormulaRow(
                '赠送金实付',
                report.orderSalesSummary!.giftPaid,
                prefix: '−',
              ),
              const Divider(height: 22),
              _FormulaRow(
                '净营收',
                report.orderSalesSummary!.netSales,
                strong: true,
              ),
            ],
          ),
        ),
      ],
      if (report.changeSummary != null &&
          (report.changeSummary!.totalChange > 0 ||
              report.changeSummary!.byChannel.isNotEmpty)) ...[
        CashierCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('现金找零', icon: Icons.change_circle_outlined),
              const SizedBox(height: 14),
              _FormulaRow('找零合计', report.changeSummary!.totalChange),
              if (report.changeSummary!.byChannel.isNotEmpty) ...[
                const Divider(height: 22),
                for (final entry in report.changeSummary!.byChannel.entries)
                  _FormulaRow(_changeChannelLabel(entry.key), entry.value),
              ],
            ],
          ),
        ),
      ],
      if (report.dishOperations != null &&
          (report.dishOperations!.refundDishCount > 0 ||
              report.dishOperations!.giveDishCount > 0)) ...[
        CashierCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('退菜 / 赠菜', icon: Icons.fastfood_outlined),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Expanded(child: Text('退菜')),
                    Text(
                      '${report.dishOperations!.refundDishCount} 道',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 18),
                    Text(
                      '¥ ${formatCashierMoney(report.dishOperations!.refundDishAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Expanded(child: Text('赠菜')),
                    Text(
                      '${report.dishOperations!.giveDishCount} 道',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 18),
                    Text(
                      '¥ ${formatCashierMoney(report.dishOperations!.giveDishAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ],
    side: [
      CashierCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('审计时间线'),
            const SizedBox(height: 14),
            if (report.auditEvents.isEmpty) ...[
              _TimelineItem(title: '交班完成', detail: _dateTime(report.closedAt)),
              _TimelineItem(
                title: '开班备用金 ¥ ${formatCashierMoney(report.openingFloat)}',
                detail: _dateTime(report.openedAt),
              ),
            ] else
              for (final event in report.auditEvents.reversed)
                _TimelineItem(
                  title:
                      '${_cashEventLabel(event.type)} ${event.amount == null ? '' : _signedMoney(event.amount!)}',
                  detail:
                      '${_dateTime(event.occurredAt)} · ${event.operatorName ?? '操作员待返回'} · ${event.referenceNo ?? '#${event.eventId}'}',
                ),
          ],
        ),
      ),
      CashierCard(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('报告完整性'),
            const SizedBox(height: 8),
            Text(
              '数据来自支付账本与现金事件，报告可重复查询但不可修改。',
              style: TextStyle(color: context.cashier.inkMuted),
            ),
            const SizedBox(height: 13),
            _HintBox(
              text:
                  '报告状态：${report.integrity['status'] ?? '待验证'}\n审批状态：${report.approvalStatus ?? (report.approvedBy == null ? '无需审批' : '已审批')} ${report.approvedByName ?? ''}\n版本：v${report.integrity['version'] ?? '--'}\n哈希：${report.integrity['report_hash'] ?? '待返回'}',
            ),
          ],
        ),
      ),
    ],
  );
}

typedef CashierDailySettleCallback =
    Future<void> Function({
      String? targetBusinessDay,
      DailyPrecheckResult? precheck,
      BuildContext? context,
    });

class CashierDailyClosePage extends StatefulWidget {
  const CashierDailyClosePage({
    super.key,
    required this.repository,
    required this.summary,
    required this.onSettle,
    this.shopId,
    this.targetBusinessDay,
  });
  final CashierShiftRepository repository;
  final CashierDailySummary summary;
  final CashierDailySettleCallback onSettle;
  final int? shopId;
  final String? targetBusinessDay;

  @override
  State<CashierDailyClosePage> createState() => _CashierDailyClosePageState();
}

class _CashierDailyClosePageState extends State<CashierDailyClosePage> {
  DailyPrecheckResult? precheck;
  bool loading = true;
  String? _effectiveStatDate;

  @override
  void initState() {
    super.initState();
    _effectiveStatDate = widget.targetBusinessDay;
    _load();
  }

  Future<void> _load({String? explicitDate}) async {
    setState(() => loading = true);
    final targetDate = explicitDate ?? _effectiveStatDate;
    try {
      final value = await widget.repository.loadDailyContext(
        statDate: targetDate,
        shopId: widget.shopId,
      );
      if (mounted) {
        setState(() {
          precheck = value;
          _effectiveStatDate = value.statDate.isNotEmpty
              ? value.statDate
              : targetDate;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
        final isSeqError =
            e.toString().contains('DAILY_CLOSE_OUT_OF_SEQUENCE') ||
            e.toString().contains('409');
        if (isSeqError) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('日结时序冲突：存在更早的未结营业日，已自动刷新至最早待结日。')),
          );
          try {
            final fallback = await widget.repository.loadDailyContext(
              shopId: widget.shopId,
            );
            if (mounted) {
              setState(() {
                precheck = fallback;
                _effectiveStatDate = fallback.statDate;
              });
            }
          } catch (_) {}
        }
      }
    }
  }

  Future<void> _viewZReport(String businessDay) async {
    try {
      final report = await widget.repository.loadZReport(
        statDate: businessDay,
        shopId: widget.shopId,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => CashierZReportPage(report: report, onPrint: () {}),
        ),
      );
    } catch (exception) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('获取 Z 报表失败：$exception')));
    }
  }

  Future<void> _viewZHistory() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => CashierZReportHistoryListPage(
          repository: widget.repository,
          shopId: widget.shopId,
          onOpenReport: _viewZReport,
          onOpenDailyClose: (businessDay) {
            _load(explicitDate: businessDay);
          },
        ),
      ),
    );
  }

  Future<void> _voidStaleTakeout(
    VoidableStalePackTakeoutSummary summary,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CashierDialogFrame(
        title: '作废超时打包外卖订单',
        subtitle: '作废处理将清理跑单阻断并释放资源',
        compact: true,
        width: 480,
        height: 380,
        onClose: () => Navigator.of(ctx).pop(false),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xfffff7ed),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xfffed7aa)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xffea580c),
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '系统将自动回退菜品库存、作废后厨KDS工单、取消配送单并释放收款意向，操作已接入特权审计。堂食订单不受任何影响。',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xff9a3412),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xfff8fafc),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xffe2e8f0)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '作废单数',
                        style: TextStyle(
                          color: Color(0xff64748b),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '${summary.count} 笔 (超时 ${summary.thresholdMinutes} 分钟)',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '涉及金额',
                        style: TextStyle(
                          color: Color(0xff64748b),
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        '¥ ${summary.amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Color(0xffdc2626),
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          CashierActionButton(
            label: '取消',
            variant: CashierActionButtonVariant.secondary,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          CashierActionButton(
            label: '确认全部作废',
            variant: CashierActionButtonVariant.danger,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await widget.repository.voidStaleTakeoutOrders(
        statDate: widget.summary.statDate,
        shopId: widget.shopId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '已成功作废 ${result.voidedCount} 笔超时打包单，金额 ¥${result.voidedAmount.toStringAsFixed(2)}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('作废失败：$e')));
    }
  }

  Widget _buildLedgerMismatchDiagnosticCard(DailyPrecheckBlocker blocker) {
    return Padding(
      padding: const EdgeInsets.only(left: 34, top: 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xfffef2f2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xfffecaca)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (blocker.reasonSummary != null &&
                blocker.reasonSummary!.isNotEmpty) ...[
              Text(
                '差异概要：${blocker.reasonSummary}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff991b1b),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (blocker.ledgerMismatches.isNotEmpty) ...[
              for (final item in blocker.ledgerMismatches)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xfffecaca)),
                        ),
                        child: Text(
                          item.orderNo,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xff7f1d1d),
                          ),
                        ),
                      ),
                      Text(
                        '订单: ¥${item.orderAmountYuan.toStringAsFixed(2)} | 流水: ¥${item.ledgerAmountYuan.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff475569),
                        ),
                      ),
                      Text(
                        '差额: ${item.differenceYuan >= 0 ? '+' : ''}¥${item.differenceYuan.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: item.differenceYuan < 0
                              ? const Color(0xffb91c1c)
                              : const Color(0xffb45309),
                        ),
                      ),
                      if (item.reason.isNotEmpty || item.reasonCode.isNotEmpty)
                        Text(
                          '(${item.reason.isNotEmpty ? item.reason : item.reasonCode})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff991b1b),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 6),
            const Text(
              '提示：存在流水事实与订单不一致硬阻断日结。请核对账单流水或前往对账中心处理。',
              style: TextStyle(fontSize: 11, color: Color(0xffb91c1c)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final blockers = precheck?.blockers ?? const <DailyPrecheckBlocker>[];
    final warnings = precheck?.warnings ?? const <DailyPrecheckWarning>[];
    final canClose =
        precheck?.canSettle == true &&
        blockers.isEmpty &&
        precheck?.precheckToken?.isNotEmpty == true;
    final previewChannels = <String, double>{};
    final previewChannelDetails = <CashierPayChannelRevenue>[];
    if (precheck != null && precheck!.channelDetails.isNotEmpty) {
      previewChannelDetails.addAll(precheck!.channelDetails);
      for (final ch in precheck!.channelDetails) {
        previewChannels[ch.code] = ch.amount;
      }
    } else if (precheck != null && precheck!.channels.isNotEmpty) {
      previewChannels.addAll(precheck!.channels);
      precheck!.channels.forEach((code, amount) {
        previewChannelDetails.add(
          CashierPayChannelRevenue(
            code: code,
            label: cashierChannelLabel(code),
            amount: amount,
          ),
        );
      });
    } else {
      final rawPreviewChannels = precheck?.preview['channels'];
      if (rawPreviewChannels is List) {
        for (final raw in rawPreviewChannels.whereType<Map>()) {
          final channel = CashierPayChannelRevenue.fromJson(
            raw.cast<String, Object?>(),
          );
          previewChannels[channel.code] = channel.amount;
          previewChannelDetails.add(channel);
        }
      }
    }
    final statDate =
        _effectiveStatDate ?? precheck?.statDate ?? widget.summary.statDate;
    final hasBacklog =
        precheck != null &&
        (precheck!.hasPreviousUnclosedDay || precheck!.pendingDayCount > 1);
    return _SecondaryScaffold(
      eyebrow: 'BUSINESS DAY CLOSE',
      sectionLabel: '日结中心',
      title: '营业日 $statDate',
      subtitle: precheck?.windowStart == null
          ? '关账窗口由服务端营业日规则确定'
          : '关账窗口：${_dateTime(precheck!.windowStart)} — ${_dateTime(precheck!.windowEnd)}',
      onBack: () => Navigator.of(context).pop(),
      trailing: Wrap(
        spacing: 10,
        children: [
          _WorkbenchButton(
            label: '重新预检',
            icon: Icons.refresh_rounded,
            onPressed: loading ? null : _load,
          ),
          _WorkbenchButton(
            label: '历史 Z 报表',
            icon: Icons.history_rounded,
            onPressed: _viewZHistory,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PrecheckBanner(loading: loading, precheck: precheck),
          if (hasBacklog) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xfffffbeb),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xfffde68a)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.history_toggle_off_rounded,
                    color: Color(0xffd97706),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '待日结营业日：$statDate（历史积压 ${precheck!.pendingDayCount} 天未关账）',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xff92400e),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          '系统遵循严格日结时序规范（INV-CLOSE-SEQ-001），请先完成此日期的日结，完成后将自动进入下一待结营业日。',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Color(0xffb45309),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          _DetailColumns(
            main: [
              CashierCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('阻断与警告'),
                    const SizedBox(height: 5),
                    Text(
                      '阻断项必须全部清零；警告项需要经理确认。',
                      style: TextStyle(color: context.cashier.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    if (loading)
                      const LinearProgressIndicator()
                    else if (precheck == null)
                      const _PrecheckItem(
                        code: '预检获取失败',
                        message: '请重新执行预检，未获取结果前不应关账。',
                        danger: true,
                      )
                    else if (blockers.isEmpty && warnings.isEmpty)
                      const _PrecheckItem(
                        code: '所有检查已通过',
                        message: '钱箱、订单、支付和差异审批均无阻断。',
                      )
                    else ...[
                      for (final blocker in blockers)
                        _PrecheckItem(
                          code: blocker.code,
                          message: blocker.message,
                          danger: true,
                          action:
                              (blocker.voidablePackTakeout != null &&
                                  blocker.voidablePackTakeout!.count > 0)
                              ? Align(
                                  alignment: Alignment.centerLeft,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 34),
                                    child: CashierActionButton(
                                      label:
                                          '一键作废超时打包单 (${blocker.voidablePackTakeout!.count}单 / ¥${blocker.voidablePackTakeout!.amount.toStringAsFixed(2)})',
                                      variant:
                                          CashierActionButtonVariant.danger,
                                      icon: Icons.auto_delete_outlined,
                                      onPressed: () => _voidStaleTakeout(
                                        blocker.voidablePackTakeout!,
                                      ),
                                    ),
                                  ),
                                )
                              : (blocker.code == 'ORDER_LEDGER_MISMATCH' &&
                                    (blocker.reasonSummary != null ||
                                        blocker.ledgerMismatches.isNotEmpty))
                              ? _buildLedgerMismatchDiagnosticCard(blocker)
                              : null,
                        ),
                      for (final warning in warnings)
                        _PrecheckItem(
                          code: warning.code,
                          message: warning.message,
                          warning: true,
                        ),
                    ],
                  ],
                ),
              ),
              CashierCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Expanded(child: _SectionTitle('关账预览')),
                        CashierStatusBadge(
                          label: '实时',
                          variant: CashierStatusBadgeVariant.neutral,
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      precheck?.isAlreadySettled == true
                          ? '该营业日已完成日结，展示不可变快照权威归档数据。'
                          : '实时数据仅用于预检；提交后生成不可变快照。',
                      style: TextStyle(color: context.cashier.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    _InfoGrid(
                      items: [
                        (
                          '总销售额',
                          '¥ ${formatCashierMoney(_previewMoney(precheck, 'gross_sales_fen', fallback: widget.summary.totalAmount))}',
                        ),
                        (
                          '优惠',
                          '− ¥ ${formatCashierMoney(_previewMoney(precheck, 'discount_amount_fen', fallback: widget.summary.discountAmount))}',
                        ),
                        (
                          '退款',
                          '− ¥ ${formatCashierMoney(_previewMoney(precheck, 'refund_amount_fen', fallback: widget.summary.refundAmount))}',
                        ),
                        (
                          '净销售额',
                          '¥ ${formatCashierMoney(_previewMoney(precheck, 'net_sales_fen', fallback: widget.summary.totalAmount - widget.summary.discountAmount - widget.summary.refundAmount))}',
                        ),
                        ('订单数', '${_previewInt(precheck, 'order_count')} 笔'),
                        (
                          '现金差异',
                          '¥ ${formatCashierMoney(_previewMoney(precheck, 'cash_variance_fen'))}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              CashierCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('支付渠道核对'),
                    const SizedBox(height: 14),
                    _ChannelTable(
                      channels: previewChannels.isEmpty
                          ? widget.summary.channels
                          : previewChannels,
                      details: previewChannelDetails,
                    ),
                  ],
                ),
              ),
            ],
            side: [
              CashierCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('关账检查'),
                    const SizedBox(height: 14),
                    _CheckRow(
                      label: '钱箱会话',
                      ok: !blockers.any((item) => item.code.contains('DRAWER')),
                      detail: _blockerCount(blockers, 'DRAWER'),
                    ),
                    _CheckRow(
                      label: '未结订单',
                      ok: !blockers.any((item) => item.code.contains('ORDER')),
                      detail: _blockerCount(blockers, 'ORDER'),
                    ),
                    _CheckRow(
                      label: '处理中支付',
                      ok: !blockers.any(
                        (item) => item.code.contains('PAYMENT'),
                      ),
                      detail: _blockerCount(blockers, 'PAYMENT'),
                    ),
                    _CheckRow(
                      label: '未审批超限差异',
                      ok: !blockers.any(
                        (item) => item.code.contains('VARIANCE'),
                      ),
                      detail: _blockerCount(blockers, 'VARIANCE'),
                    ),
                  ],
                ),
              ),
              CashierCard(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionTitle('快照规则'),
                    const SizedBox(height: 8),
                    Text(
                      '日结不会覆盖原流水。快照记录支付、现金、订单三条截止水位线与完整性哈希。',
                      style: TextStyle(color: context.cashier.inkMuted),
                    ),
                    const SizedBox(height: 14),
                    _WatermarkRow(
                      label: '支付账本',
                      value: _mapValue(
                        precheck?.watermarks ?? const {},
                        'payment_ledger_id',
                      ),
                    ),
                    _WatermarkRow(
                      label: '现金流水',
                      value: _mapValue(
                        precheck?.watermarks ?? const {},
                        'cash_event_id',
                      ),
                    ),
                    _WatermarkRow(
                      label: '订单',
                      value: _mapValue(
                        precheck?.watermarks ?? const {},
                        'order_id',
                      ),
                    ),
                    if (precheck?.precheckExpiresAt != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        '预检凭据有效至 ${_dateTime(precheck!.precheckExpiresAt)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.cashier.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          CashierCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    canClose
                        ? '预检已通过，日结时将进行管理员二次认证。'
                        : '当前存在阻断或预检未完成，服务端仍会在提交前再次校验。',
                    style: TextStyle(color: context.cashier.inkMuted),
                  ),
                ),
                const SizedBox(width: 16),
                _WorkbenchButton(
                  label: precheck?.isAlreadySettled == true
                      ? '该日已日结'
                      : '运行预检并日结',
                  icon: Icons.verified_user_outlined,
                  danger: precheck?.isAlreadySettled != true,
                  onPressed: loading
                      ? null
                      : () async {
                          final statDate =
                              _effectiveStatDate ??
                              precheck?.statDate ??
                              widget.summary.statDate;
                          await widget.onSettle(
                            targetBusinessDay: statDate,
                            precheck: precheck,
                            context: context,
                          );
                        },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class CashierZReportPage extends StatelessWidget {
  const CashierZReportPage({
    super.key,
    required this.report,
    required this.onPrint,
  });
  final CommercialZReport report;
  final VoidCallback onPrint;

  Future<void> _exportCsv(BuildContext context) async {
    try {
      final csv = generateCommercialZReportCsv(report);
      final bytes = utf8.encode(csv);
      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      final cleanDay = report.businessDay.replaceAll(RegExp(r'[^\d]'), '');
      final type = report.isClosed ? 'ZReport' : 'XReport';
      final fileName = 'daily_close_${report.shopId}_${cleanDay}_$type.csv';
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已成功导出日结对账单：${file.path}'),
          backgroundColor: Colors.green.shade800,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  Future<void> _copyPrintableText(BuildContext context) async {
    final text = report.printableText.isNotEmpty
        ? report.printableText
        : generateCommercialZReportCsv(report);
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('热敏对账小票文本已复制到剪贴板，可直接发送到微信/企微工作群'),
        duration: Duration(seconds: 3),
      ),
    );
  }

  void _showReceiptPreview(BuildContext context) {
    final text = report.printableText.isNotEmpty
        ? report.printableText
        : generateCommercialZReportCsv(report);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.receipt_long, size: 22),
            SizedBox(width: 8),
            Text('58mm 热敏小票打印预览'),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: SelectableText(
                text,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Color(0xFF1E293B),
                  height: 1.45,
                ),
              ),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制文本'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('小票文本已复制到剪贴板')));
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.print, size: 16),
            label: const Text('立即打印'),
            onPressed: () {
              Navigator.of(ctx).pop();
              onPrint();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => _SecondaryScaffold(
    eyebrow: report.isClosed
        ? 'IMMUTABLE CLOSE REPORT'
        : 'REALTIME PREVIEW REPORT',
    sectionLabel: report.isClosed ? 'Z 报表' : 'X 报表预览',
    title: '${report.isClosed ? 'Z 报表' : '实时日结预览'} · ${report.businessDay}',
    subtitle:
        '快照 ${report.snapshotNo ?? (report.isClosed ? '编号待返回' : 'X-PREVIEW-${report.businessDay}')} · ${report.closedAt == null ? '实时统计' : '${_dateTime(report.closedAt)} 关账'}${report.operatorName != null && report.operatorName!.isNotEmpty ? ' · 关账人：${report.operatorName}' : ''}${report.reviewerName != null && report.reviewerName!.isNotEmpty ? ' · 复核人：${report.reviewerName}' : ''}',
    onBack: () => Navigator.of(context).pop(),
    backLabel: '返回日结中心',
    trailing: Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        _WorkbenchButton(
          key: const Key('copy-z-report-button'),
          label: '复制对账文本',
          icon: Icons.copy_rounded,
          onPressed: () => _copyPrintableText(context),
        ),
        _WorkbenchButton(
          key: const Key('preview-z-report-button'),
          label: '小票预览',
          icon: Icons.receipt_long_outlined,
          onPressed: () => _showReceiptPreview(context),
        ),
        _WorkbenchButton(
          key: const Key('export-z-report-csv-button'),
          label: '导出 CSV',
          icon: Icons.download_rounded,
          onPressed: () => _exportCsv(context),
        ),
        _WorkbenchButton(
          key: const Key('print-z-report-button'),
          label: '打印完整报表',
          icon: Icons.print_outlined,
          selected: true,
          onPressed: onPrint,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 关账快照与安全审计
        CashierCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: report.isClosed
                          ? context.cashier.successBackground
                          : context.cashier.warningBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      report.isClosed
                          ? Icons.verified_rounded
                          : Icons.pending_actions_rounded,
                      color: report.isClosed
                          ? context.cashier.success
                          : context.cashier.warning,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionTitle(
                          report.isClosed ? '关账快照已锁定' : '营业中实时预览 (未关账)',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          report.isClosed
                              ? '后续退款或补录以调整单体现，不修改本快照。'
                              : '当前为营业中实时统计数据，实际关账时以签署确认的 Z 报表快照为准。',
                        ),
                      ],
                    ),
                  ),
                  CashierStatusBadge(
                    label: report.isClosed ? 'CLOSED (已关账)' : 'PREVIEW (实时预览)',
                    variant: report.isClosed
                        ? CashierStatusBadgeVariant.success
                        : CashierStatusBadgeVariant.warning,
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _InfoGrid(
                items: [
                  (
                    '快照编号',
                    report.snapshotNo ??
                        (report.isClosed
                            ? '未提供'
                            : 'X-PREVIEW-${report.businessDay}'),
                  ),
                  ('营业日', report.businessDay),
                  if (report.operatorName != null &&
                      report.operatorName!.isNotEmpty)
                    (
                      '关账责任人',
                      '${report.operatorName}${report.operatorWorkNo != null && report.operatorWorkNo!.isNotEmpty ? ' (${report.operatorWorkNo})' : ''}',
                    ),
                  if (report.reviewerName != null &&
                      report.reviewerName!.isNotEmpty)
                    ('审核复核人', report.reviewerName!),
                  if (report.windowStart != null && report.windowEnd != null)
                    (
                      '统计窗口',
                      '${_dateTime(report.windowStart)} ~ ${_dateTime(report.windowEnd)}',
                    ),
                ],
              ),
              if (report.snapshotHash != null &&
                  report.snapshotHash!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '快照完整性防伪哈希 (SHA-256)',
                      style: TextStyle(
                        color: context.cashier.inkMuted,
                        fontSize: 12,
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: report.snapshotHash!),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制快照哈希')),
                        );
                      },
                      child: Text(
                        '复制哈希',
                        style: TextStyle(
                          color: context.cashier.selected,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cashier.subtle,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: SelectableText(
                    report.snapshotHash!,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2. 核心营收与营运综合指标
        CashierCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle('核心营收与营运指标', icon: Icons.analytics_outlined),
              const SizedBox(height: 5),
              Text(
                '营业日综合营收、真实收款、折扣、退款、客流与翻台产能指标',
                style: TextStyle(color: context.cashier.inkMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              _InfoGrid(
                items: [
                  ('净销售额 (含挂账)', '¥ ${formatCashierMoney(report.netSales)}'),
                  (
                    '实际收款合计 (已入账)',
                    '¥ ${formatCashierMoney(report.actualCollections)}',
                  ),
                  ('账面原价销售额', '¥ ${formatCashierMoney(report.totalSales)}'),
                  ('折扣减免总额', '¥ ${formatCashierMoney(report.discountAmount)}'),
                  ('退款总额', '¥ ${formatCashierMoney(report.refundAmount)}'),
                  ('有效订单数', '${report.orderCount} 笔'),
                  (
                    '客单价 (单均)',
                    '¥ ${formatCashierMoney(report.avgOrderAmount)}',
                  ),
                  (
                    '用餐人数 (客均)',
                    '${report.dinerCount} 人 · ¥ ${formatCashierMoney(report.avgDinerAmount)}',
                  ),
                  (
                    '全店翻台率',
                    '${report.tableTurnoverRate.toStringAsFixed(1)} 次/台',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.cashier.subtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 14,
                      color: context.cashier.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '口径说明：净销售额按权责发生制计入挂账订单；实际收款合计为真实入账现金流（支付流水净额 + 当期应收回款 + 会员充值本金）。',
                        style: TextStyle(
                          color: context.cashier.inkMuted,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 2.1 挂账与应收对账专区 (v1.2.306 / WI-029 / WI-051)
        if (report.receivables != null) ...[
          CashierCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const _SectionTitle(
                      '挂账与应收对账专区',
                      icon: Icons.account_balance_wallet_outlined,
                    ),
                    if ((report.receivables?.cutoffLedgerId ?? 0) > 0)
                      CashierStatusBadge(
                        label: '流水水位 #${report.receivables!.cutoffLedgerId}',
                        variant: CashierStatusBadgeVariant.info,
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '展示营业日期间客户挂账消费、应收账款回款冲减、坏账核销与挂账撤销变动，以及期末应收总余额',
                  style: TextStyle(
                    color: context.cashier.inkMuted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                _InfoGrid(
                  items: [
                    (
                      '当期新增挂账 (Charged)',
                      '¥ ${formatCashierMoney(report.receivables!.chargedAmount)}',
                    ),
                    (
                      '当期应收回款 (Collected)',
                      '¥ ${formatCashierMoney(report.receivables!.collectedAmount)}',
                    ),
                    (
                      '坏账核销冲减 (Write-off)',
                      '¥ ${formatCashierMoney(report.receivables!.writeoffAmount)}',
                    ),
                    (
                      '挂账撤销重开 (Reversed)',
                      '¥ ${formatCashierMoney(report.receivables!.reversedAmount)}',
                    ),
                    (
                      '期末应收余额 (Outstanding)',
                      '¥ ${formatCashierMoney(report.receivables!.outstandingAmount)}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.cashier.subtle,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.cashier.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 16,
                            color: context.cashier.selected,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            '会计勾稽与对账指引',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '1. 净销售额 (¥ ${formatCashierMoney(report.netSales)}) 包含了当期新增挂账 (¥ ${formatCashierMoney(report.receivables!.chargedAmount)})；\n'
                        '2. 实际收款合计 (¥ ${formatCashierMoney(report.actualCollections)}) 已计入当期应收回款 (¥ ${formatCashierMoney(report.receivables!.collectedAmount)})，不含新增挂账；\n'
                        '3. 支付渠道实收明细仅统计实际到账资金，不重复计入挂账订单。',
                        style: TextStyle(
                          color: context.cashier.inkMuted,
                          fontSize: 11,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 3. 双列布局：支付渠道实收明细 + 收银钱箱现金盘点
        LayoutBuilder(
          builder: (context, constraints) {
            final drawer = report.dailyDetail?.cashDrawer;
            final channelSum = report.channelDetails.isNotEmpty
                ? report.channelDetails.fold<double>(
                    0.0,
                    (acc, e) => acc + e.amount,
                  )
                : report.channels.values.fold<double>(0.0, (acc, e) => acc + e);
            final baseSum = channelSum > 0 ? channelSum : report.netSales;
            final channelCard = CashierCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('支付渠道实收对账', icon: Icons.payment_outlined),
                  const SizedBox(height: 14),
                  if (report.channelDetails.isNotEmpty)
                    for (final ch in report.channelDetails) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  ch.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${ch.successCount} 笔',
                                  style: TextStyle(
                                    color: context.cashier.inkMuted,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  '¥ ${formatCashierMoney(ch.amount)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: baseSum > 0
                                    ? (ch.amount / baseSum).clamp(0.0, 1.0)
                                    : 0.0,
                                backgroundColor: context.cashier.subtle,
                                color: context.cashier.selected,
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ]
                  else
                    for (final entry in report.channels.entries)
                      _FormulaRow(dailyChannelLabel(entry.key), entry.value),
                  const Divider(height: 22),
                  _FormulaRow('渠道净额合计', baseSum, strong: true),
                  const SizedBox(height: 6),
                  Text(
                    '注：支付渠道仅统计真实入账资金，不包含挂账销售。',
                    style: TextStyle(
                      color: context.cashier.inkMuted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );

            final drawerCard = CashierCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle(
                    '收银钱箱现金盘点',
                    icon: Icons.point_of_sale_outlined,
                  ),
                  const SizedBox(height: 14),
                  if (drawer != null) ...[
                    _FormulaRow('开箱备用金 (Opening Float)', drawer.openingFloat),
                    _FormulaRow('+ 现金实收 (Cash In)', drawer.cashIn, prefix: '+'),
                    _FormulaRow(
                      '− 现金退款 (Cash Refund)',
                      drawer.cashRefund,
                      prefix: '−',
                    ),
                    const Divider(height: 16),
                    _FormulaRow(
                      '理论应有现金 (Theoretical)',
                      drawer.theoreticalCash,
                      strong: true,
                    ),
                    _FormulaRow(
                      '实际盘点现金 (Counted)',
                      drawer.countedCash,
                      strong: true,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: drawer.variance == 0
                            ? context.cashier.successBackground
                            : context.cashier.dangerBackground,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '长短款差额 (Variance)',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${drawer.variance >= 0 ? '+' : '−'} ¥ ${formatCashierMoney(drawer.variance.abs())}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: drawer.variance == 0
                                      ? context.cashier.success
                                      : context.cashier.danger,
                                ),
                              ),
                              const SizedBox(width: 8),
                              CashierStatusBadge(
                                label: drawer.variance == 0
                                    ? '账实相符'
                                    : (drawer.variance > 0 ? '长款' : '短款'),
                                variant: drawer.variance == 0
                                    ? CashierStatusBadgeVariant.success
                                    : CashierStatusBadgeVariant.danger,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _FormulaRow('钱箱总差异', report.totalCashVariance),
                  ],
                  if (report.drawerSummary.isNotEmpty) ...[
                    const Divider(height: 22),
                    Text(
                      '班次明细记录',
                      style: TextStyle(
                        color: context.cashier.inkMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _DrawerSummary(report.drawerSummary),
                  ],
                ],
              ),
            );

            if (constraints.maxWidth < 920) {
              return Column(
                children: [channelCard, const SizedBox(height: 16), drawerCard],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: channelCard),
                const SizedBox(width: 16),
                Expanded(child: drawerCard),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // 4. 三列布局：就餐方式 + 会员运营 + 异常风控
        LayoutBuilder(
          builder: (context, constraints) {
            final orderTypeCard = CashierCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('🍽️ 就餐方式与订单类型'),
                  const SizedBox(height: 12),
                  if (report.orderTypes.isNotEmpty)
                    for (final ot in report.orderTypes)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${ot.label} (${ot.orderCount} 单)',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '¥ ${formatCashierMoney(ot.amount)} (${ot.percentage.toStringAsFixed(1)}%)',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                  else
                    Text(
                      '暂无场景明细',
                      style: TextStyle(
                        color: context.cashier.inkMuted,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            );

            final memberCard = CashierCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('👑 会员储值与运营'),
                  const SizedBox(height: 12),
                  if (report.member != null) ...[
                    _infoTextRow(
                      '今日会员充值',
                      '¥ ${formatCashierMoney(report.member!.rechargeTotal)} (${report.member!.rechargeCount} 笔)',
                    ),
                    _infoTextRow(
                      '充值本金 (实际入账)',
                      '¥ ${formatCashierMoney(report.member!.rechargePrincipal)}',
                    ),
                    _infoTextRow(
                      '充值赠送支出',
                      '¥ ${formatCashierMoney(report.member!.rechargeGift)}',
                    ),
                    _infoTextRow(
                      '储值卡消费额',
                      '¥ ${formatCashierMoney(report.member!.memberConsumption)}',
                    ),
                    _infoTextRow('当期新增会员', '+${report.member!.newMembers} 人'),
                  ] else
                    Text(
                      '暂无会员储值数据',
                      style: TextStyle(
                        color: context.cashier.inkMuted,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            );

            final exceptionsCard = CashierCard(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('🛡️ 异常与风控审计'),
                  const SizedBox(height: 12),
                  if (report.exceptions != null) ...[
                    _infoTextRow(
                      '反结账/重开单',
                      '${report.exceptions!.uncheckoutCount} 次 (¥ ${formatCashierMoney(report.exceptions!.uncheckoutAmount)})',
                    ),
                    _infoTextRow(
                      '整单/部分退款',
                      '${report.exceptions!.refundCount} 笔 (¥ ${formatCashierMoney(report.exceptions!.refundAmount)})',
                    ),
                    _infoTextRow(
                      '赠菜 / 免单合计',
                      '${report.exceptions!.freeDishesCount} 份 (¥ ${formatCashierMoney(report.exceptions!.freeDishesAmount)})',
                    ),
                    _infoTextRow(
                      '手工折扣与抹零',
                      '¥ ${formatCashierMoney(report.exceptions!.discountAmount)}',
                    ),
                  ] else
                    Text(
                      '未检测到风控异常记录',
                      style: TextStyle(
                        color: context.cashier.inkMuted,
                        fontSize: 13,
                      ),
                    ),
                ],
              ),
            );

            if (constraints.maxWidth < 1000) {
              return Column(
                children: [
                  orderTypeCard,
                  const SizedBox(height: 16),
                  memberCard,
                  const SizedBox(height: 16),
                  exceptionsCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: orderTypeCard),
                const SizedBox(width: 16),
                Expanded(child: memberCard),
                const SizedBox(width: 16),
                Expanded(child: exceptionsCard),
              ],
            );
          },
        ),
        const SizedBox(height: 16),

        // 5. 菜品销售额排行 TOP 10 榜单
        CashierCard(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                '🔥 菜品销售额排行 TOP 10',
                icon: Icons.local_fire_department_outlined,
              ),
              const SizedBox(height: 5),
              Text(
                '单品销售份数、销售额与营收贡献占比',
                style: TextStyle(color: context.cashier.inkMuted, fontSize: 12),
              ),
              const SizedBox(height: 14),
              if (report.topDishes.isNotEmpty)
                Column(
                  children: report.topDishes.map((dish) {
                    final rankColor = dish.rank == 1
                        ? const Color(0xFFEAB308)
                        : (dish.rank == 2
                              ? const Color(0xFF94A3B8)
                              : (dish.rank == 3
                                    ? const Color(0xFFCA8A04)
                                    : context.cashier.inkMuted));
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6.0),
                      child: Row(
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: dish.rank <= 3
                                  ? rankColor.withValues(alpha: 0.18)
                                  : context.cashier.subtle,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${dish.rank}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: rankColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              dish.dishName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${dish.quantity} 份',
                            style: TextStyle(
                              color: context.cashier.inkMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Text(
                            '¥ ${formatCashierMoney(dish.amount)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 50,
                            child: Text(
                              '${dish.percentage.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color: context.cashier.inkMuted,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.end,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    '暂无菜品销售排行数据',
                    style: TextStyle(
                      color: context.cashier.inkMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 6. 水位线与日结后调整（若有）
        if (report.adjustments.isNotEmpty || report.watermarks.isNotEmpty) ...[
          const SizedBox(height: 16),
          CashierCard(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionTitle('快照水位线与调整记录'),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 24,
                  runSpacing: 8,
                  children: [
                    _WatermarkRow(
                      label: '支付账本',
                      value: _mapValue(report.watermarks, 'payment_ledger_id'),
                    ),
                    _WatermarkRow(
                      label: '现金流水',
                      value: _mapValue(report.watermarks, 'cash_event_id'),
                    ),
                    _WatermarkRow(
                      label: '订单',
                      value: _mapValue(report.watermarks, 'order_id'),
                    ),
                    if (report.watermarks.containsKey('receivable_ledger_id') ||
                        (report.receivables?.cutoffLedgerId ?? 0) > 0)
                      _WatermarkRow(
                        label: '应收流水',
                        value:
                            _mapValue(
                              report.watermarks,
                              'receivable_ledger_id',
                            ).isNotEmpty
                            ? _mapValue(
                                report.watermarks,
                                'receivable_ledger_id',
                              )
                            : '${report.receivables?.cutoffLedgerId ?? 0}',
                      ),
                  ],
                ),
                if (report.adjustments.isNotEmpty) ...[
                  const Divider(height: 20),
                  _HintBox(
                    text:
                        '日结后调整 ${report.adjustments.length} 项 · ¥ ${formatCashierMoney(report.totalAdjustment)}',
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _infoTextRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

String generateCommercialZReportCsv(CommercialZReport report) {
  final buffer = StringBuffer();
  buffer.write('\uFEFF'); // UTF-8 BOM for Excel

  void addRow(List<Object?> row) {
    buffer.writeln(
      row
          .map((e) => '"${e?.toString().replaceAll('"', '""') ?? ''}"')
          .join(','),
    );
  }

  addRow([
    '连锁餐饮收银日结对账单 (${report.isClosed ? 'Z-Report 已关账' : 'X-Report 实时预览'})',
  ]);
  addRow(['门店名称', report.shopName]);
  addRow(['营业日', report.businessDay]);
  addRow(['快照编号', report.snapshotNo ?? '']);
  addRow(['快照哈希', report.snapshotHash ?? '']);
  addRow(['关账责任人', report.operatorName ?? '']);
  addRow(['审核复核人', report.reviewerName ?? '']);
  if (report.windowStart != null && report.windowEnd != null) {
    addRow([
      '统计窗口',
      '${_dateTime(report.windowStart)} ~ ${_dateTime(report.windowEnd)}',
    ]);
  }
  addRow([]);

  addRow(['【核心营收与营运指标】', '']);
  addRow(['净销售额 (含挂账)', formatCashierMoney(report.netSales)]);
  addRow(['实际收款合计 (已入账)', formatCashierMoney(report.actualCollections)]);
  addRow(['账面原价销售额', formatCashierMoney(report.totalSales)]);
  addRow(['折扣减免总额', formatCashierMoney(report.discountAmount)]);
  addRow(['退款总额', formatCashierMoney(report.refundAmount)]);
  addRow(['有效订单数', '${report.orderCount} 笔']);
  addRow(['客单价 (单均)', formatCashierMoney(report.avgOrderAmount)]);
  addRow([
    '用餐人数 (客均)',
    '${report.dinerCount} 人 · ¥ ${formatCashierMoney(report.avgDinerAmount)}',
  ]);
  addRow(['全店翻台率', '${report.tableTurnoverRate.toStringAsFixed(1)} 次/台']);
  addRow([]);

  final rec = report.receivables;
  if (rec != null) {
    addRow(['【挂账与应收对账】', '']);
    addRow(['当期新增挂账 (Charged)', formatCashierMoney(rec.chargedAmount)]);
    addRow(['当期应收回款 (Collected)', formatCashierMoney(rec.collectedAmount)]);
    addRow(['坏账核销冲减 (Write-off)', formatCashierMoney(rec.writeoffAmount)]);
    addRow(['挂账撤销重开 (Reversed)', formatCashierMoney(rec.reversedAmount)]);
    addRow(['期末应收余额 (Outstanding)', formatCashierMoney(rec.outstandingAmount)]);
    if (rec.cutoffLedgerId > 0) {
      addRow(['应收流水截止水位', '${rec.cutoffLedgerId}']);
    }
    addRow([]);
  }

  addRow(['【支付渠道实收明细】', '', '', '']);
  addRow(['支付渠道', '交易笔数', '实收金额(元)', '占比']);
  final channelSum = report.channelDetails.isNotEmpty
      ? report.channelDetails.fold<double>(0.0, (acc, e) => acc + e.amount)
      : report.channels.values.fold<double>(0.0, (acc, e) => acc + e);
  final baseSum = channelSum > 0 ? channelSum : report.netSales;
  if (report.channelDetails.isNotEmpty) {
    for (final ch in report.channelDetails) {
      final pct = baseSum > 0
          ? ((ch.amount / baseSum) * 100).toStringAsFixed(1)
          : '0.0';
      addRow([
        ch.label,
        ch.successCount,
        formatCashierMoney(ch.amount),
        '$pct%',
      ]);
    }
  } else {
    for (final e in report.channels.entries) {
      final pct = baseSum > 0
          ? ((e.value / baseSum) * 100).toStringAsFixed(1)
          : '0.0';
      addRow([
        dailyChannelLabel(e.key),
        '-',
        formatCashierMoney(e.value),
        '$pct%',
      ]);
    }
  }
  addRow(['渠道实收合计', '', formatCashierMoney(baseSum), '100.0%']);
  addRow([]);

  addRow(['【收银钱箱现金对账】', '']);
  final drawer = report.dailyDetail?.cashDrawer;
  if (drawer != null) {
    addRow(['开箱备用金', formatCashierMoney(drawer.openingFloat)]);
    addRow(['现金实收 (Cash In)', formatCashierMoney(drawer.cashIn)]);
    addRow(['现金退款 (Cash Refund)', formatCashierMoney(drawer.cashRefund)]);
    addRow(['理论应有现金', formatCashierMoney(drawer.theoreticalCash)]);
    addRow(['实际盘点现金', formatCashierMoney(drawer.countedCash)]);
    addRow(['长短款差额 (Variance)', formatCashierMoney(drawer.variance)]);
    addRow([
      '对账状态',
      drawer.variance == 0 ? '账实相符' : (drawer.variance > 0 ? '长款' : '短款'),
    ]);
  } else {
    addRow(['钱箱总差异', formatCashierMoney(report.totalCashVariance)]);
  }
  addRow([]);

  if (report.orderTypes.isNotEmpty) {
    addRow(['【就餐方式与订单类型分布】', '', '', '']);
    addRow(['类型', '订单数', '金额(元)', '占比']);
    for (final ot in report.orderTypes) {
      addRow([
        ot.label,
        ot.orderCount,
        formatCashierMoney(ot.amount),
        '${ot.percentage.toStringAsFixed(1)}%',
      ]);
    }
    addRow([]);
  }

  if (report.member != null) {
    final m = report.member!;
    addRow(['【会员储值与运营简报】', '']);
    addRow(['今日会员充值总额', formatCashierMoney(m.rechargeTotal)]);
    addRow(['充值本金 (实际入账)', formatCashierMoney(m.rechargePrincipal)]);
    addRow(['充值赠送支出', formatCashierMoney(m.rechargeGift)]);
    addRow(['充值笔数', '${m.rechargeCount} 笔']);
    addRow(['储值消费总额', formatCashierMoney(m.memberConsumption)]);
    addRow(['当期新增会员', '+${m.newMembers} 人']);
    addRow([]);
  }

  if (report.exceptions != null) {
    final ex = report.exceptions!;
    addRow(['【异常与风控审计】', '']);
    addRow([
      '反结账/重开单',
      '${ex.uncheckoutCount} 次 (¥ ${formatCashierMoney(ex.uncheckoutAmount)})',
    ]);
    addRow([
      '整单/部分退款',
      '${ex.refundCount} 笔 (¥ ${formatCashierMoney(ex.refundAmount)})',
    ]);
    addRow([
      '赠菜/免单合计',
      '${ex.freeDishesCount} 份 (¥ ${formatCashierMoney(ex.freeDishesAmount)})',
    ]);
    addRow(['手工折扣与抹零', formatCashierMoney(ex.discountAmount)]);
    addRow([]);
  }

  if (report.topDishes.isNotEmpty) {
    addRow(['【热销菜品销售排行 TOP 10】', '', '', '', '']);
    addRow(['排名', '菜品名称', '销售份数', '销售金额(元)', '营收占比']);
    for (final d in report.topDishes) {
      addRow([
        d.rank,
        d.dishName,
        d.quantity,
        formatCashierMoney(d.amount),
        '${d.percentage.toStringAsFixed(1)}%',
      ]);
    }
    addRow([]);
  }

  return buffer.toString();
}

class _SecondaryScaffold extends StatelessWidget {
  const _SecondaryScaffold({
    required this.eyebrow,
    required this.sectionLabel,
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.child,
    this.trailing,
    this.backLabel = '当班与日结',
  });
  final String eyebrow;
  final String sectionLabel;
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final Widget child;
  final Widget? trailing;
  final String backLabel;

  @override
  Widget build(BuildContext context) => Material(
    color: context.cashier.canvas,
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, viewport) => ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            Center(
              child: ConstrainedBox(
                key: const Key('cashier-shift-secondary-content-frame'),
                constraints: BoxConstraints(
                  maxWidth: _contentMaxWidth(viewport.maxWidth - 48),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: onBack,
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(0, 38),
                          ),
                          child: Text(backLabel),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: Text(
                            '/',
                            style: TextStyle(color: context.cashier.inkMuted),
                          ),
                        ),
                        Text(
                          sectionLabel,
                          style: TextStyle(color: context.cashier.inkMuted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final heading = Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              eyebrow,
                              style: TextStyle(
                                color: context.cashier.inkMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              style: TextStyle(color: context.cashier.inkMuted),
                            ),
                          ],
                        );
                        if (constraints.maxWidth < 760) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              heading,
                              if (trailing != null) ...[
                                const SizedBox(height: 14),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: trailing!,
                                ),
                              ],
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(child: heading),
                            if (trailing != null) ...[
                              const SizedBox(width: 20),
                              trailing!,
                            ],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    child,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

double _contentMaxWidth(double availableWidth) =>
    availableWidth >= 1600 ? 1360 : 1120;

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.label, {this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
      Flexible(
        child: Text(
          label,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _DetailColumns extends StatelessWidget {
  const _DetailColumns({required this.main, required this.side});
  final List<Widget> main;
  final List<Widget> side;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      Widget stack(List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1) const SizedBox(height: 16),
          ],
        ],
      );
      if (constraints.maxWidth < 920) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [stack(main), const SizedBox(height: 16), stack(side)],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: stack(main)),
          const SizedBox(width: 16),
          SizedBox(width: 330, child: stack(side)),
        ],
      );
    },
  );
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.items});
  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final idealColumns = items.length == 6 ? 3 : 4;
      final columns = constraints.maxWidth < 620 ? 2 : idealColumns;
      const gap = 10.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final item in items)
            Container(
              width: width,
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: context.cashier.subtle,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.$1,
                    style: TextStyle(
                      color: context.cashier.inkMuted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.$2,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
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

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.title, required this.detail});
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(12, 8, 0, 12),
    decoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: context.cashier.selected, width: 2),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(
          detail,
          style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
        ),
      ],
    ),
  );
}

class _HintBox extends StatelessWidget {
  const _HintBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: context.cashier.selectedBackground,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 13, color: context.cashier.selected),
    ),
  );
}

class _ChannelTable extends StatelessWidget {
  const _ChannelTable({required this.channels, this.details = const []});
  final Map<String, double> channels;
  final List<CashierPayChannelRevenue> details;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const _HintBox(text: '暂无渠道数据，请检查支付汇总接口。');
    }
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.2),
        1: FlexColumnWidth(1.3),
        2: FlexColumnWidth(1.3),
        3: FlexColumnWidth(1.8),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: context.cashier.border),
      ),
      children: [
        _tableRow(context, const ['渠道', '交易笔数', '退款', '实收净额'], header: true),
        if (details.isNotEmpty)
          for (final item in details)
            _tableRow(context, [
              item.label,
              '${item.transactionCount}',
              '${item.refundCount}',
              '¥ ${formatCashierMoney(item.amount)}',
            ])
        else
          for (final entry in channels.entries)
            _tableRow(context, [
              dailyChannelLabel(entry.key),
              '--',
              '--',
              '¥ ${formatCashierMoney(entry.value)}',
            ]),
      ],
    );
  }

  TableRow _tableRow(
    BuildContext context,
    List<String> values, {
    bool header = false,
  }) => TableRow(
    decoration: BoxDecoration(color: header ? context.cashier.subtle : null),
    children: [
      for (var index = 0; index < values.length; index++)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Text(
            values[index],
            textAlign: index == values.length - 1
                ? TextAlign.right
                : TextAlign.left,
            style: TextStyle(
              fontSize: header ? 12 : 13,
              fontWeight: header || index == values.length - 1
                  ? FontWeight.w700
                  : FontWeight.w400,
              color: header ? context.cashier.inkMuted : null,
            ),
          ),
        ),
    ],
  );
}

class _PrecheckBanner extends StatelessWidget {
  const _PrecheckBanner({required this.loading, required this.precheck});
  final bool loading;
  final DailyPrecheckResult? precheck;

  @override
  Widget build(BuildContext context) {
    final isSettled = precheck?.isAlreadySettled == true;
    final blocked =
        !isSettled &&
        (precheck == null ||
            precheck!.blockers.isNotEmpty ||
            !precheck!.canSettle ||
            precheck!.precheckToken?.isNotEmpty != true);
    final color = isSettled
        ? const Color(0xff2563eb)
        : (blocked ? context.cashier.danger : context.cashier.success);
    final background = isSettled
        ? const Color(0xffeff6ff)
        : (blocked
              ? context.cashier.dangerBackground
              : context.cashier.successBackground);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: color.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          if (loading)
            SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: color),
            )
          else
            Icon(
              isSettled
                  ? Icons.task_alt_rounded
                  : (blocked
                        ? Icons.warning_amber_rounded
                        : Icons.check_circle_outline_rounded),
              color: color,
              size: 25,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loading
                      ? '正在执行关账预检'
                      : isSettled
                      ? '该营业日已完成日结'
                      : (blocked ? '当前不能日结' : '关账预检已通过'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  loading
                      ? '正在核对钱箱、订单、支付和差异审批。'
                      : isSettled
                      ? '已固化不可变快照与渠道实收，无需重复结账，可直接查看 Z 报表。'
                      : (blocked
                            ? '发现 ${precheck?.blockers.length ?? 0} 项阻断或预检未获取，处理后需重新预检。'
                            : '服务端已签发日结凭据，提交时将再次校验。'),
                ),
              ],
            ),
          ),
          CashierStatusBadge(
            label: loading
                ? '预检中'
                : isSettled
                ? '已日结归档'
                : (blocked ? '预检未通过' : '可以日结'),
            variant: isSettled
                ? CashierStatusBadgeVariant.info
                : (blocked
                      ? CashierStatusBadgeVariant.danger
                      : CashierStatusBadgeVariant.success),
          ),
        ],
      ),
    );
  }
}

class _PrecheckItem extends StatelessWidget {
  const _PrecheckItem({
    required this.code,
    required this.message,
    this.danger = false,
    this.warning = false,
    this.action,
  });
  final String code;
  final String message;
  final bool danger;
  final bool warning;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? context.cashier.danger
        : warning
        ? context.cashier.warning
        : context.cashier.success;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                danger
                    ? Icons.warning_amber_rounded
                    : warning
                    ? Icons.info_outline_rounded
                    : Icons.check_rounded,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      code,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(message, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.ok,
    required this.detail,
  });
  final String label;
  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded,
          color: ok ? context.cashier.success : context.cashier.danger,
          size: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(
                detail,
                style: TextStyle(fontSize: 12, color: context.cashier.inkMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _WatermarkRow extends StatelessWidget {
  const _WatermarkRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 9),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'NotoSansSC',
            fontWeight: FontWeight.w700,
            letterSpacing: .3,
          ),
        ),
      ],
    ),
  );
}

class _DrawerSummary extends StatelessWidget {
  const _DrawerSummary(this.summary);
  final Map<String, Object?> summary;

  @override
  Widget build(BuildContext context) {
    final sessions = summary['sessions'];
    if (sessions is! List || sessions.isEmpty) {
      return const _HintBox(text: '该营业日没有可展示的钱箱班次明细。');
    }
    return Column(
      children: [
        for (final raw in sessions.whereType<Map>())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${raw['terminal_id'] ?? '--'} / ${raw['drawer_code'] ?? '--'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    '${raw['operator_name'] ?? raw['operator_id'] ?? '待补充'}',
                  ),
                ),
                Text(
                  '差异 ${_signedMoney(raw['variance_fen'] == null ? safeMoney(raw['variance']) : safeFen(raw['variance_fen']))}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _dateTime(DateTime? value) {
  if (value == null) return '--';
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
}

String _duration(DateTime? start, DateTime? end) {
  if (start == null || end == null) return '--';
  return _durationSeconds(end.difference(start).inSeconds);
}

String _durationSeconds(int seconds) {
  final value = Duration(seconds: seconds);
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.inHours)}:${two(value.inMinutes % 60)}:${two(value.inSeconds % 60)}';
}

int _previewInt(DailyPrecheckResult? value, String key) {
  final summary = value?.summary;
  if (summary != null && summary.containsKey(key)) {
    final v = summary[key];
    if (v is num) return v.toInt();
    final parsed = int.tryParse('$v');
    if (parsed != null) return parsed;
  }
  final raw = value?.preview[key];
  return raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
}

double _previewMoney(
  DailyPrecheckResult? value,
  String fenKey, {
  double fallback = 0,
}) {
  final summary = value?.summary;
  if (summary != null && summary.isNotEmpty) {
    if (summary[fenKey] != null) return safeFen(summary[fenKey]);
    final yuanKey = fenKey.replaceAll('_fen', '');
    if (summary[yuanKey] != null) {
      final v = summary[yuanKey];
      return v is num ? v.toDouble() : double.tryParse('$v') ?? fallback;
    }
  }
  final raw = value?.preview[fenKey];
  return raw == null ? fallback : safeFen(raw);
}

String _blockerCount(List<DailyPrecheckBlocker> blockers, String token) {
  final count = blockers
      .where((item) => item.code.contains(token))
      .fold<int>(0, (sum, item) => sum + item.count);
  return count == 0 ? '0 项' : '$count 项未处理';
}

String _mapValue(Map<String, Object?> map, String key) {
  final value = map[key];
  return value == null ? '--' : '#$value';
}

String _latestMovementLabel(CashierCashEvent? event) {
  if (event == null) return '暂无现金动作';
  final amount = event.amountHidden || event.amount == null
      ? '金额按盲盘规则隐藏'
      : _signedMoney(event.amount!);
  return '${_cashEventLabel(event.type)} · $amount · ${_dateTime(event.occurredAt)}';
}

String _previousShiftLabel(CashierPreviousShift? shift) {
  if (shift == null) return '暂无已关闭班次';
  return '班次 #${shift.sessionId} · ${shift.balanced ? '已平账' : '存在差额'} · ${_dateTime(shift.closedAt)}';
}

String _cashEventLabel(String type) => switch (type.toUpperCase()) {
  'OPENING_FLOAT' => '开班备用金',
  'CASH_SALE' => '现金收款',
  'CASH_REFUND' => '现金退款',
  'CASH_IN' => '零钱加钞',
  'CASH_OUT' => '现金支出',
  'CASH_DROP' => '大钞投库',
  'COUNT' => '盘点提交',
  'ADJUSTMENT' => '现金调整',
  _ => type.isEmpty ? '现金事件' : type,
};

String _signedMoney(double amount) =>
    '${amount >= 0 ? '+' : '−'} ¥ ${formatCashierMoney(amount.abs())}';

String _changeChannelLabel(String code) => switch (code) {
  'wechat' => '微信找零',
  'cash' => '现金找零',
  'alipay' => '支付宝找零',
  _ => code.isEmpty ? '找零' : code,
};

class _FormulaRow extends StatelessWidget {
  const _FormulaRow(
    this.label,
    this.amount, {
    this.prefix = '',
    this.strong = false,
  });
  final String label;
  final double amount;
  final String prefix;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        Text(
          '$prefix${prefix.isEmpty ? '' : ' '}¥ ${formatCashierMoney(amount)}',
          style: TextStyle(
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

String _clock(DateTime? value) => value == null
    ? '--'
    : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _elapsed(DateTime? start, DateTime now) {
  if (start == null) return '开始时间待同步';
  final duration = now.difference(start);
  if (duration.isNegative) return '刚刚开班';
  return '已当班 ${duration.inHours.toString().padLeft(2, '0')}:${(duration.inMinutes % 60).toString().padLeft(2, '0')}';
}
