import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../cashier_shift/data/real_cashier_shift_repository.dart';
import '../../cashier_shift/domain/cashier_shift.dart';
import '../data/api_providers.dart';
import '../design/mobile_colors.dart';
import '../design/mobile_components.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';
import 'profile_page.dart' show currentShiftProvider;

/// 交接班（PRD F05）：开班 → 当前班次 → 交班（实收现金盘点）。
///
/// 真实数据来自 `RealCashierShiftRepository`（/cashier/shift/start|current|handover）。
class ShiftHandoverPage extends ConsumerStatefulWidget {
  const ShiftHandoverPage({super.key});

  @override
  ConsumerState<ShiftHandoverPage> createState() => _ShiftHandoverPageState();
}

class _ShiftHandoverPageState extends ConsumerState<ShiftHandoverPage> {
  final _startCashController = TextEditingController();
  final _endCashController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _startCashController.dispose();
    _endCashController.dispose();
    super.dispose();
  }

  RealCashierShiftRepository get _repo =>
      RealCashierShiftRepository(ref.read(apiClientProvider));

  Future<void> _startShift() async {
    final startCash = double.tryParse(_startCashController.text.trim()) ?? 0;
    if (startCash < 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('备用金不能为负')));
      return;
    }
    setState(() => _submitting = true);
    try {
      await _repo.startShift(startCash: startCash);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('开班成功')));
        ref.invalidate(currentShiftProvider);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('开班失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _handover(CashierShift shift) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('交班确认'),
        content: Text(
          '本班已收 ${shift.orderCount} 单，合计 ¥${shift.totalAmount.toStringAsFixed(2)}。\n'
          '交班后本班次结束并生成交班记录，是否继续？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认交班'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final endCash = await showModalBottomSheet<double?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(MobileMetrics.radiusSheet)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(MobileMetrics.spaceLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('盘点实收现金', style: MobileTypography.sectionTitle),
              const SizedBox(height: MobileMetrics.spaceSm),
              Text(
                '请清点本班现金实收并填写，用于交班对账。',
                style: context.bodySecondaryStyle,
              ),
              const SizedBox(height: MobileMetrics.spaceMd),
              TextField(
                controller: _endCashController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: '实收现金（元）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: MobileMetrics.spaceLg),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
                ),
                onPressed: () => Navigator.of(
                  sheetContext,
                ).pop(double.tryParse(_endCashController.text.trim()) ?? 0),
                child: const Text('确认交班'),
              ),
            ],
          ),
        ),
      ),
    );
    if (endCash == null || !mounted) return;
    setState(() => _submitting = true);
    try {
      final result = await _repo.handover(endCash: endCash);
      if (mounted) {
        ref.invalidate(currentShiftProvider);
        showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('交班完成'),
            content: Text(
              '本班共 $result 单，营业额 ¥${result.totalAmount.toStringAsFixed(2)}。',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('好的'),
              ),
            ],
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('交班失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftAsync = ref.watch(currentShiftProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('交接班')),
      body: shiftAsync.when(
        loading: () => const LoadingSkeleton(height: 200),
        error: (error, _) => ErrorState(
          message: '班次加载失败：$error',
          onRetry: () => ref.invalidate(currentShiftProvider),
        ),
        data: (shift) => shift == null
            ? _buildOpenShift(context)
            : _buildCurrentShift(context, shift),
      ),
      bottomNavigationBar: shiftAsync.maybeWhen(
        data: (shift) => shift == null ? null : _bottomBar(shift),
        orElse: () => null,
      ),
    );
  }

  Widget _buildOpenShift(BuildContext context) {
    return ListView(
      padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
      children: [
        Card(
          child: Padding(
            padding: MobileMetrics.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('当前无进行中的班次', style: MobileTypography.sectionTitle),
                const SizedBox(height: MobileMetrics.spaceSm),
                Text(
                  '开班后即可开始本班收银记录与交班对账。',
                  style: context.bodySecondaryStyle,
                ),
                const SizedBox(height: MobileMetrics.spaceMd),
                TextField(
                  controller: _startCashController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '备用金（元，默认 0）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: MobileMetrics.spaceLg),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
                  ),
                  onPressed: _submitting ? null : _startShift,
                  child: Text(_submitting ? '开班中…' : '开班'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentShift(BuildContext context, CashierShift shift) {
    final start = shift.startTime;
    final startLabel = start == null
        ? '未知'
        : '${start.month}月${start.day}日 ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}';
    return ListView(
      padding: MobileMetrics.pagePadding.copyWith(top: MobileMetrics.spaceLg),
      children: [
        Card(
          child: Padding(
            padding: MobileMetrics.cardPadding,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text('当班中', style: MobileTypography.sectionTitle),
                          const SizedBox(width: MobileMetrics.spaceSm),
                          const StatusTag('进行中', tone: SemanticTone.success),
                        ],
                      ),
                      const SizedBox(height: MobileMetrics.spaceXs),
                      Text(
                        '开班 $startLabel · 备用金 ¥${shift.startCash.toStringAsFixed(2)}',
                        style: context.captionStyle,
                      ),
                    ],
                  ),
                ),
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
                const Text('本班汇总', style: MobileTypography.sectionTitle),
                const SizedBox(height: MobileMetrics.spaceMd),
                Row(
                  children: [
                    _SummaryItem(label: '营业额', value: '¥${shift.totalAmount.toStringAsFixed(2)}', highlight: true),
                    _SummaryItem(label: '订单', value: '${shift.orderCount} 单'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(CashierShift shift) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(MobileMetrics.spaceLg),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(MobileMetrics.buttonHeightCta),
          ),
          onPressed: _submitting ? null : () => _handover(shift),
          icon: const Icon(Icons.assignment_return_outlined),
          label: Text(_submitting ? '交班中…' : '确认交班'),
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: context.captionStyle),
          const SizedBox(height: MobileMetrics.spaceXs),
          Text(
            value,
            style: MobileTypography.pageTitle.copyWith(
              fontSize: 22,
              color: highlight
                  ? context.palette.brandInk
                  : context.palette.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
