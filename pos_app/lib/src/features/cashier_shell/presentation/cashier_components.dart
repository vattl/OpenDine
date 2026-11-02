import 'package:flutter/material.dart';

import 'cashier_design_tokens.dart';

abstract final class CashierColors {
  static const ink = CashierPalette.ink;
  static const page = CashierPalette.canvas;
  static const row = CashierPalette.row;
  static const textSecondary = CashierPalette.inkMuted;
  static const border = CashierPalette.border;
  static const selected = CashierPalette.selected;
  static const selectedBackground = CashierPalette.selectedBackground;
  static const focus = CashierPalette.focus;
  static const danger = CashierPalette.danger;
  static const success = CashierPalette.successBackground;
  static const successText = CashierPalette.success;
  static const warning = CashierPalette.warning;
}

class CashierCard extends StatelessWidget {
  const CashierCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: margin,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CashierMetrics.cardRadius),
          side: BorderSide(color: theme.dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

enum CashierActionButtonVariant { primary, secondary, danger, success }

class CashierActionButton extends StatelessWidget {
  const CashierActionButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = CashierActionButtonVariant.primary,
    this.icon,
    this.busy = false,
    this.minimumWidth = 160,
    this.height = 60,
  });

  final String label;
  final VoidCallback? onPressed;
  final CashierActionButtonVariant variant;
  final IconData? icon;
  final bool busy;
  final double minimumWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final (background, foreground, border) = switch (variant) {
      CashierActionButtonVariant.primary => (
        dark ? scheme.primary : CashierColors.ink,
        dark ? scheme.onPrimary : Colors.white,
        dark ? scheme.primary : CashierColors.ink,
      ),
      CashierActionButtonVariant.secondary => (
        scheme.surface,
        scheme.onSurface,
        theme.dividerColor,
      ),
      CashierActionButtonVariant.danger => (
        CashierColors.danger,
        Colors.white,
        CashierColors.danger,
      ),
      CashierActionButtonVariant.success => (
        CashierColors.success,
        CashierColors.ink,
        CashierColors.success,
      ),
    };

    return Semantics(
      button: true,
      label: label,
      enabled: onPressed != null && !busy,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: minimumWidth,
          minHeight: height < CashierMetrics.buttonHeight
              ? CashierMetrics.buttonHeight
              : height,
        ),
        child: FilledButton(
          onPressed: busy ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            side: BorderSide(color: border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(CashierMetrics.controlRadius),
            ),
            textStyle: const TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[
                SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: foreground,
                  ),
                ),
                const SizedBox(width: 8),
              ] else if (icon != null) ...[
                Icon(icon, size: 24),
                const SizedBox(width: 8),
              ],
              Text(busy ? '提交中…' : label),
            ],
          ),
        ),
      ),
    );
  }
}

enum CashierViewState { loading, empty, error, unauthorized }

class CashierStateView extends StatelessWidget {
  const CashierStateView({
    super.key,
    required this.state,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final CashierViewState state;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (state) {
      CashierViewState.loading => Icons.hourglass_top_rounded,
      CashierViewState.empty => Icons.inbox_outlined,
      CashierViewState.error => Icons.error_outline_rounded,
      CashierViewState.unauthorized => Icons.lock_outline_rounded,
    };
    return Semantics(
      liveRegion:
          state == CashierViewState.loading || state == CashierViewState.error,
      label: '$title。$message',
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 72,
              color: state == CashierViewState.error
                  ? CashierColors.danger
                  : scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 20),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              CashierActionButton(label: actionLabel!, onPressed: onAction),
            ],
          ],
        ),
      ),
    );
  }
}

enum CashierStatusBadgeVariant { neutral, info, success, warning, danger }

class CashierStatusBadge extends StatelessWidget {
  const CashierStatusBadge({
    super.key,
    required this.label,
    this.variant = CashierStatusBadgeVariant.neutral,
    this.icon,
  });

  final String label;
  final CashierStatusBadgeVariant variant;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, defaultIcon) = switch (variant) {
      CashierStatusBadgeVariant.neutral => (
        scheme.onSurfaceVariant,
        Icons.info_outline,
      ),
      CashierStatusBadgeVariant.info => (CashierColors.selected, Icons.sync),
      CashierStatusBadgeVariant.success => (
        CashierColors.successText,
        Icons.check_circle_outline,
      ),
      CashierStatusBadgeVariant.warning => (
        CashierColors.warning,
        Icons.warning_amber,
      ),
      CashierStatusBadgeVariant.danger => (
        CashierColors.danger,
        Icons.error_outline,
      ),
    };
    return Semantics(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withAlpha(24),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon ?? defaultIcon, size: 20, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class CashierAmountText extends StatelessWidget {
  const CashierAmountText({
    super.key,
    required this.amount,
    this.refund = false,
    this.style,
  });

  final num amount;
  final bool refund;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final value = '${amount < 0 ? '−' : ''}¥ ${_groupAmount(amount.abs())}';
    return Semantics(
      label: refund ? '退款 $value' : value,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ).merge(style),
          ),
          if (refund) ...[
            const SizedBox(width: 8),
            const Text(
              '退款',
              style: TextStyle(
                color: CashierColors.danger,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String _groupAmount(num amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final grouped = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$grouped.${parts.last}';
}

class CashierDialogFrame extends StatelessWidget {
  const CashierDialogFrame({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.onClose,
    this.busy = false,
    this.width = 760,
    this.height = 480,
    this.subtitle,
    this.compact = false,
    this.titleFontSize,
    this.subtitleFontSize,
    this.headerHeight,
    this.bodyPadding,
    this.footerHeight,
    this.dialogRadius,
    this.dialogBackgroundColor,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final VoidCallback? onClose;
  final bool busy;
  final double width;
  final double height;
  final String? subtitle;
  final bool compact;
  // 细粒度外观覆盖（用于向已批准原型做保真还原；不传则维持既有默认）。
  final double? titleFontSize;
  final double? subtitleFontSize;
  final double? headerHeight;
  final EdgeInsetsGeometry? bodyPadding;
  final double? footerHeight;
  final double? dialogRadius;
  final Color? dialogBackgroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final bottomInset = viewInsets.bottom;
    // 键盘弹起时 Dialog 组件自身会按 viewInsets 上移；
    // 这里限制最大高度不超过「屏幕高-键盘高-顶部安全边距」，
    // 让弹窗高度自适应收缩（内容区 SingleChildScrollView 保持可滚动），
    // 避免固定高度弹窗在键盘弹出后顶部溢出、输入框被遮挡。
    final screenSize = MediaQuery.sizeOf(context);
    final maxDialogHeight = screenSize.height - bottomInset - 24;
    final maxDialogWidth = screenSize.width - 24;
    final effectiveWidth = width > maxDialogWidth ? maxDialogWidth : width;
    final effectiveHeight = height > maxDialogHeight ? maxDialogHeight : height;

    return PopScope(
      canPop: !busy,
      child: Dialog(
        backgroundColor: dialogBackgroundColor ?? theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
            dialogRadius ?? CashierMetrics.dialogRadius,
          ),
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: maxDialogHeight,
            maxWidth: maxDialogWidth,
          ),
          child: SizedBox(
            width: effectiveWidth,
            height: effectiveHeight,
            child: Column(
              children: [
                SizedBox(
                  height: headerHeight ??
                      (compact
                          ? (subtitle == null ? 70 : 82)
                          : CashierMetrics.dialogHeaderHeight),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 22 : 32,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  fontSize:
                                      titleFontSize ?? (compact ? 21 : 28),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (subtitle != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: subtitleFontSize ?? 13,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (onClose != null)
                          Semantics(
                            button: true,
                            label: '关闭',
                            child: Tooltip(
                              message: '关闭',
                              child: SizedBox.square(
                                dimension: compact ? 42 : 56,
                                child: IconButton(
                                  onPressed: busy ? null : onClose,
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: theme.dividerColor),
                Expanded(
                  child: SingleChildScrollView(
                    padding: bodyPadding ??
                        EdgeInsets.all(compact ? 22 : 32),
                    child: body,
                  ),
                ),
                if (actions.isNotEmpty) ...[
                  Divider(height: 1, color: theme.dividerColor),
                  SizedBox(
                    height: footerHeight ?? (compact ? 78 : 88),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 22 : 32,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: actions
                            .expand(
                              (action) => [const SizedBox(width: 12), action],
                            )
                            .skip(1)
                            .toList(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
