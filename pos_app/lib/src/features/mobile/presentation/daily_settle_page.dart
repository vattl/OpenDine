import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../data/api_providers.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 门店日结（PRD F05.4/5，仅老板/店长，路由侧已守卫 order:config + daily:settle）。
///
/// 遵循 WI-067 / INV-CLOSE-SEQ-001：
/// 客户端本机时间不作为日结权威；先调用不带 `stat_date` 的 `GET /admin/daily/pre-check`，
/// 以返回的 `stat_date/next_close_business_day` 作为该页面唯一目标营业日。
class DailySettlePage extends ConsumerStatefulWidget {
  const DailySettlePage({super.key});

  @override
  ConsumerState<DailySettlePage> createState() => _DailySettlePageState();
}

class _DailySettlePageState extends ConsumerState<DailySettlePage> {
  String? _authoritativeDate;
  bool _customDatePicked = false;
  Map<String, Object?>? _summary;
  List<Map<String, Object?>> _channels = const [];
  bool _loading = false;
  bool _settled = false;

  int _pendingDayCount = 0;
  bool _hasPreviousUnclosedDay = false;
  String? _precheckToken;
  List<String> _blockerMessages = const [];

  DateTime get _pickerInitialDate =>
      _authoritativeDate != null
          ? (DateTime.tryParse(_authoritativeDate!) ?? DateTime.now())
          : DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      // 单接口聚合调用：一次性获取权威营业日、Summary、Channels与阻断项，杜绝多接口参数与数据不对称
      final resp = await client.get(
        dailyContextEndpoint,
        query: {
          if (_customDatePicked && _authoritativeDate != null && _authoritativeDate!.isNotEmpty)
            'stat_date': _authoritativeDate!,
        },
      );
      final ctxMap = resp is Map ? resp.cast<String, Object?>() : const <String, Object?>{};

      final serverStatDate = ctxMap['stat_date']?.toString() ??
          ctxMap['next_close_business_day']?.toString() ??
          ctxMap['statDate']?.toString();

      if (!_customDatePicked && serverStatDate != null && serverStatDate.isNotEmpty) {
        _authoritativeDate = serverStatDate;
      } else if (_authoritativeDate == null && serverStatDate != null && serverStatDate.isNotEmpty) {
        _authoritativeDate = serverStatDate;
      }

      final pendingCount = (ctxMap['pending_day_count'] as num?)?.toInt() ??
          (ctxMap['pendingDayCount'] as num?)?.toInt() ??
          0;
      final hasPrevious = ctxMap['has_previous_unclosed_day'] == true ||
          ctxMap['hasPreviousUnclosedDay'] == true;
      final token = (ctxMap['precheck_token'] ?? ctxMap['precheckToken'])?.toString();
      final isSettled = ctxMap['is_already_settled'] == true ||
          ctxMap['isAlreadySettled'] == true ||
          ctxMap['settled'] == true;

      final blockersList = <String>[];
      final rawBlockers = ctxMap['blockers'];
      if (rawBlockers is List) {
        for (final b in rawBlockers) {
          if (b is Map) {
            blockersList.add('${b['message'] ?? b['code'] ?? '阻断项'}');
          } else if (b != null) {
            blockersList.add(b.toString());
          }
        }
      }

      final summary = ctxMap['summary'];
      final summaryMap = summary is Map ? summary.cast<String, Object?>() : null;

      final rawDetails = ctxMap['channel_details'];
      List<Map<String, Object?>> channelsList = [];
      if (rawDetails is List && rawDetails.isNotEmpty) {
        channelsList = rawDetails.whereType<Map>().map((m) => m.cast<String, Object?>()).toList();
      } else if (ctxMap['channels'] is Map) {
        final map = (ctxMap['channels'] as Map).cast<String, Object?>();
        channelsList = map.entries.map((e) => {
          'name': e.key,
          'amount': (e.value is num) ? (e.value as num).toDouble() : double.tryParse('${e.value}') ?? 0.0,
        }).toList();
      } else {
        channelsList = objectList(ctxMap['channels'] ?? ctxMap['income'] ?? ctxMap['list']);
      }

      setState(() {
        _summary = summaryMap;
        _settled = isSettled || (_summary != null && _summary!['settled'] == true);
        _channels = channelsList;
        _pendingDayCount = pendingCount;
        _hasPreviousUnclosedDay = hasPrevious;
        _precheckToken = token;
        _blockerMessages = blockersList;
        _loading = false;
      });
    } catch (error) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('查询失败：$error')));
    }
  }

  Future<void> _settle() async {
    final targetLabel = _authoritativeDate ?? '当前待结营业日';
    if (_blockerMessages.isNotEmpty) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('日结阻断'),
          content: Text(
            '存在未清零的阻断事项，暂无法日结：\n${_blockerMessages.map((m) => '• $m').join('\n')}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('日结确认'),
        content: Text('对营业日 $targetLabel 执行日结？\n日结后当日数据将锁定，请确认已核对现金与订单。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认日结'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _loading = true);
    try {
      final client = ref.read(apiClientProvider);
      await client.post(
        dailySettleEndpoint,
        body: {
          if (_authoritativeDate != null) 'stat_date': _authoritativeDate!,
          if (_precheckToken != null && _precheckToken!.isNotEmpty)
            'precheck_token': _precheckToken!,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日结成功')));
      }
      _customDatePicked = false;
      await _loadSummary();
    } catch (error) {
      if (mounted) {
        setState(() => _loading = false);
        final isSeqError = error.toString().contains('DAILY_CLOSE_OUT_OF_SEQUENCE') ||
            error.toString().contains('409');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isSeqError
                  ? '日结时序冲突：存在更早的未结营业日，正在自动刷新至最早待结日...'
                  : '日结失败：$error',
            ),
          ),
        );
        if (isSeqError) {
          _customDatePicked = false;
          await _loadSummary();
        }
      }
    }
  }

  Future<void> _pickDate() async {
    final initial = _pickerInitialDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year, initial.month + 1, 0),
    );
    if (picked != null) {
      final pickedStr =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() {
        _authoritativeDate = pickedStr;
        _customDatePicked = true;
      });
      _loadSummary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayDate = _authoritativeDate ?? '获取中...';
    final hasBacklog = _hasPreviousUnclosedDay || _pendingDayCount > 1;

    return Scaffold(
      appBar: AppBar(title: const Text('门店日结')),
      body: RefreshIndicator(
        onRefresh: _loadSummary,
        child: ListView(
          padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text('待日结营业日：$displayDate'),
                subtitle: Text(
                  hasBacklog
                      ? '历史积压 $_pendingDayCount 天 · 须按序完成关账'
                      : '关账窗口由服务端营业日权威确定',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickDate,
              ),
            ),
            if (hasBacklog) ...[
              const SizedBox(height: MobileMetrics.cardGap),
              Card(
                color: const Color(0xfffffbeb),
                child: Padding(
                  padding: MobileMetrics.cardPadding,
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xffd97706)),
                      const SizedBox(width: MobileMetrics.spaceSm),
                      Expanded(
                        child: Text(
                          '还有 $_pendingDayCount 个历史营业日待处理，请先完成此日期（$displayDate）的日结，完成后自动进入下一日。',
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
              ),
            ],
            const SizedBox(height: MobileMetrics.cardGap),
            if (_loading)
              const LoadingSkeleton(height: 180)
            else ...[
              _buildStatusCard(context),
              if (_blockerMessages.isNotEmpty) ...[
                const SizedBox(height: MobileMetrics.cardGap),
                _buildBlockersCard(context),
              ],
              const SizedBox(height: MobileMetrics.cardGap),
              _buildSummary(context),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(MobileMetrics.spaceLg),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
            ),
            onPressed: _settled || _loading || _blockerMessages.isNotEmpty ? null : _settle,
            icon: const Icon(Icons.event_available_outlined),
            label: Text(_settled
                ? '该营业日已日结'
                : _blockerMessages.isNotEmpty
                    ? '存在阻断无法日结'
                    : '一键日结'),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final displayDate = _authoritativeDate ?? '当前营业日';
    return Card(
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Row(
          children: [
            Icon(
              _settled ? Icons.check_circle_outline : Icons.pending_actions_outlined,
              color: _settled ? context.palette.success : const Color(0xffd97706),
              size: 26,
            ),
            const SizedBox(width: MobileMetrics.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _settled ? '$displayDate 已完成日结' : '$displayDate 待日结关账',
                    style: MobileTypography.sectionTitle,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _settled
                        ? '已固化不可变快照与渠道实收对账，营业数据已归档。'
                        : '实时数据已聚合，请核对以下财务实收与渠道对账，无误后点击下方「一键日结」。',
                    style: context.bodySecondaryStyle,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockersCard(BuildContext context) {
    return Card(
      color: const Color(0xfffef2f2),
      child: Padding(
        padding: MobileMetrics.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Color(0xffdc2626), size: 20),
                SizedBox(width: MobileMetrics.spaceSm),
                Text(
                  '日结前置阻断（须全部清零）',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff991b1b),
                  ),
                ),
              ],
            ),
            const SizedBox(height: MobileMetrics.spaceSm),
            for (final msg in _blockerMessages)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(color: Color(0xffdc2626), fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(
                        msg,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xff7f1d1d),
                          height: 1.4,
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

  Widget _buildSummary(BuildContext context) {
    final s = _summary ?? const <String, Object?>{};
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    final revenue = d(
      s['net_sales'] ?? s['total_amount'] ?? s['revenue'] ?? s['totalRevenue'] ?? s['businessRevenue'] ?? s['todayRevenue'] ?? s['gross_sales'],
    );
    final orders = i(s['order_count'] ?? s['orderCount'] ?? s['totalOrderCount'] ?? s['todayOrderCount']);
    final refund = d(s['refund_amount'] ?? s['refundAmount'] ?? s['totalRefundAmount']);
    final discount = d(s['discount_amount'] ?? s['discountAmount'] ?? s['totalDiscountAmount']);
    final grossProfit = d(s['grossProfit'] ?? s['profit'] ?? s['netProfit'] ?? (revenue - d(s['material_cost'])));
    return Column(
      children: [
        Card(
          child: Padding(
            padding: MobileMetrics.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('日结汇总', style: MobileTypography.sectionTitle),
                const SizedBox(height: MobileMetrics.spaceMd),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: MobileMetrics.spaceMd,
                  crossAxisSpacing: MobileMetrics.spaceMd,
                  childAspectRatio: 2.2,
                  children: [
                    _stat(context, '营业总额', AmountText(revenue)),
                    _stat(context, '订单数', Text('$orders', style: _valueStyle(context))),
                    _stat(context, '退款', AmountText(refund, style: _valueStyle(context).copyWith(color: context.palette.danger))),
                    _stat(context, '毛利', AmountText(grossProfit, style: _valueStyle(context).copyWith(color: context.palette.success))),
                  ],
                ),
                const SizedBox(height: MobileMetrics.spaceMd),
                Text('优惠合计 ¥${discount.toStringAsFixed(2)}', style: context.captionStyle),
              ],
            ),
          ),
        ),
        const SizedBox(height: MobileMetrics.cardGap),
        Card(
          child: Padding(
            padding: MobileMetrics.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('支付渠道对账', style: MobileTypography.sectionTitle),
                const SizedBox(height: MobileMetrics.spaceSm),
                if (_channels.isEmpty)
                  Text('暂无渠道数据', style: context.bodySecondaryStyle)
                else
                  for (final ch in _channels) _channelRow(context, ch),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _channelRow(BuildContext context, Map<String, Object?> row) {
    String s(Object? v) => v == null ? '' : '$v';
    double d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    var name = s(row['channel_label'] ?? row['channelLabel'] ?? row['name'] ?? row['label'] ?? row['channelName'] ?? row['channel_code'] ?? row['channel'] ?? row['paymentMethod']);
    if (name == 'wechat_native' || name == 'wechat') name = '微信支付';
    if (name == 'alipay') name = '支付宝';
    if (name == 'cash') name = '现金';
    final amount = (row['net_amount_fen'] is num)
        ? (row['net_amount_fen'] as num).toDouble() / 100.0
        : d(row['amount'] ?? row['totalAmount'] ?? row['net_amount']);
    final count = row['success_count'] ?? row['orderCount'] ?? row['count'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: MobileMetrics.spaceSm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: MobileTypography.body),
                if (count != null && count != 0)
                  Text('$count 笔支付', style: context.captionStyle),
              ],
            ),
          ),
          AmountText(amount, style: MobileTypography.itemTitle),
        ],
      ),
    );
  }

  TextStyle _valueStyle(BuildContext context) => MobileTypography.displayAmount.copyWith(
        color: context.palette.brandInk,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  Widget _stat(BuildContext context, String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label, style: context.captionStyle),
        const SizedBox(height: MobileMetrics.spaceXs),
        child,
      ],
    );
  }
}
