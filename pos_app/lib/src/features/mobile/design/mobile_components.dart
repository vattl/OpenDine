import 'package:flutter/material.dart';

import 'mobile_colors.dart';
import 'mobile_metrics.dart';
import 'mobile_typography.dart';

/// 状态标签（浅背景+深前景+文字，app_ui_standard.md §6.4）。
class StatusTag extends StatelessWidget {
  const StatusTag(this.text, {super.key, required this.tone});

  final String text;
  final SemanticTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MobileMetrics.spaceSm,
        vertical: MobileMetrics.spaceXs,
      ),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(MobileMetrics.radiusPill),
      ),
      child: Text(
        text,
        style: MobileTypography.captionBase.copyWith(
          color: tone.foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 空状态（说明原因+下一步操作，§6.8）。
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MobileMetrics.space2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: context.palette.textDisabled,
            ),
            const SizedBox(height: MobileMetrics.spaceMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.bodySecondaryStyle,
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: MobileMetrics.spaceLg),
              FilledButton.tonal(
                onPressed: onAction,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, MobileMetrics.buttonHeight),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 错误状态（可理解原因+重试，§6.8）。
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(MobileMetrics.space2xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: context.palette.danger,
            ),
            const SizedBox(height: MobileMetrics.spaceMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: context.bodySecondaryStyle,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: MobileMetrics.spaceLg),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: MobileMetrics.iconSizeSmall),
                label: const Text('重试'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(120, MobileMetrics.buttonHeight),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 骨架屏占位（保持布局稳定，§6.8）。
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: context.palette.surfaceSubtle,
        borderRadius: MobileMetrics.cardRadius,
      ),
      child: const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }
}

/// 桌台卡片（状态文字+边框语义色+白底，app_ui_standard.md §6.6 修正：
/// 状态不能只靠颜色，必须保证文字对比度；危险动作不能单击卡片直接执行）。
class TableCard extends StatelessWidget {
  const TableCard({
    super.key,
    required this.number,
    required this.statusText,
    required this.tone,
    this.people,
    this.amount,
    this.onTap,
  });

  final String number;
  final String statusText;
  final SemanticTone tone;
  final int? people;
  final double? amount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '桌台 $number，状态 $statusText'
          '${people != null ? '，$people 人' : ''}'
          '${amount != null ? '，金额 $amount 元' : ''}',
      button: onTap != null,
      child: Material(
        color: context.palette.surface,
        borderRadius: MobileMetrics.cardRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: MobileMetrics.cardRadius,
          child: Container(
            constraints: const BoxConstraints(
              minHeight: MobileMetrics.tableCardHeight,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: tone.foreground, width: 1.5),
              borderRadius: MobileMetrics.cardRadius,
            ),
            padding: MobileMetrics.cardPaddingCompact,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(number, style: MobileTypography.itemTitle),
                    StatusTag(statusText, tone: tone),
                  ],
                ),
                const SizedBox(height: MobileMetrics.spaceXs),
                if (people != null || amount != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (people != null)
                        Text('$people 人', style: context.captionStyle),
                      if (amount != null)
                        Text(
                          '¥ ${amount!.toStringAsFixed(2)}',
                          style: MobileTypography.label.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部固定操作栏（吸附安全区，§4.3）。
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.palette.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(MobileMetrics.spaceLg),
          child: child,
        ),
      ),
    );
  }
}
