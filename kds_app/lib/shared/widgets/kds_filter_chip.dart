import 'package:flutter/material.dart';
import 'package:kds_app/core/theme/kds_theme.dart';

/// 顶栏主 Tab：待制作 / 待传菜 / 已完成
class KdsMainTab extends StatelessWidget {
  const KdsMainTab({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: KdsSpacing.minTouch),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        alignment: Alignment.center,
        child: _BadgeLabel(
          label: label,
          badge: badge,
          textStyle: selected
              ? KdsTypography.mainTabSelected
              : KdsTypography.mainTabNormal,
        ),
      ),
    );
  }
}

/// 堂食/全部 分段控件 — 深灰底 + 浅灰选中块
class KdsSegmentControl<T> extends StatelessWidget {
  const KdsSegmentControl({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
  });

  final List<T> items;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KdsColors.segmentBg,
      borderRadius: BorderRadius.circular(KdsSpacing.segmentRadius),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++)
            _SegmentItem(
              label: labelOf(items[i]),
              selected: items[i] == selected,
              onTap: () => onChanged(items[i]),
              roundLeft: i == 0,
              roundRight: i == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.roundLeft,
    required this.roundRight,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool roundLeft;
  final bool roundRight;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? KdsColors.segmentActive : Colors.transparent,
      borderRadius: BorderRadius.horizontal(
        left: roundLeft
            ? const Radius.circular(KdsSpacing.segmentRadius)
            : Radius.zero,
        right: roundRight
            ? const Radius.circular(KdsSpacing.segmentRadius)
            : Radius.zero,
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: KdsSpacing.filterChipHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: KdsSpacing.filterChipHPad),
            child: Center(
              child: Text(
                label,
                style: selected
                    ? KdsTypography.chipLabelActive
                    : KdsTypography.chipLabelInactive,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 筛选 Pill：全部 / 超时 / 催菜 — 选中实心浅灰，未选中描边
class KdsFilterChip extends StatelessWidget {
  const KdsFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  static const _badgeSize = 17.0;
  static const _badgeFontSize = 10.0;

  @override
  Widget build(BuildContext context) {
    final count = badge ?? 0;
    final showBadge = count > 0;
    return Padding(
      padding: EdgeInsets.only(
        right: showBadge ? 12 : 6,
        top: showBadge ? 7 : 0,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: selected ? KdsColors.segmentActive : Colors.transparent,
            clipBehavior: Clip.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(KdsSpacing.filterChipRadius),
              side: selected
                  ? BorderSide.none
                  : const BorderSide(color: KdsColors.pillBorder, width: 1),
            ),
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: KdsSpacing.filterChipHeight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: KdsSpacing.filterChipHPad),
                  child: Center(
                    child: Text(
                      label,
                      style: selected
                          ? KdsTypography.chipLabelActive
                          : KdsTypography.chipLabelInactive,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (showBadge)
            Positioned(
              right: -4,
              top: -7,
              child: Material(
                color: Colors.transparent,
                elevation: 4,
                shape: const CircleBorder(),
                clipBehavior: Clip.none,
                child: _KdsCountBadge(
                  count: count,
                  size: _badgeSize,
                  fontSize: _badgeFontSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _KdsCountBadge extends StatelessWidget {
  const _KdsCountBadge({
    required this.count,
    required this.size,
    required this.fontSize,
  });

  final int count;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: size, minHeight: size),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: KdsColors.headerOverdue,
        shape: BoxShape.circle,
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}

class _BadgeLabel extends StatelessWidget {
  const _BadgeLabel({
    required this.label,
    required this.textStyle,
    this.badge,
  });

  final String label;
  final TextStyle textStyle;
  final int? badge;

  static const _badgeSize = 20.0;
  static const _fontSize = 11.0;

  @override
  Widget build(BuildContext context) {
    final count = badge ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: EdgeInsets.only(right: count > 0 ? _badgeSize * 0.5 : 0),
          child: Text(label, style: textStyle),
        ),
        if (count > 0)
          Positioned(
            right: -_badgeSize * 0.35,
            top: -_badgeSize * 0.45,
            child: Container(
              constraints: const BoxConstraints(
                  minWidth: _badgeSize, minHeight: _badgeSize),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: KdsColors.headerOverdue,
                shape: BoxShape.circle,
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 视图切换：菜品 | 订单
class KdsViewToggle extends StatelessWidget {
  const KdsViewToggle({
    super.key,
    required this.isDishView,
    required this.onChanged,
  });

  final bool isDishView;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return KdsSegmentControl<bool>(
      items: const [true, false],
      selected: isDishView,
      onChanged: onChanged,
      labelOf: (v) => v ? '菜品' : '订单',
    );
  }
}

/// 顶栏圆形图标按钮 — 对齐设计稿描边圆
class KdsCircleIconButton extends StatelessWidget {
  const KdsCircleIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.filled = false,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    final child = Material(
      color: filled ? KdsColors.wsOffline : Colors.transparent,
      shape: CircleBorder(
        side: filled
            ? BorderSide.none
            : const BorderSide(color: KdsColors.iconCircleBorder, width: 2),
      ),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: KdsColors.textPrimary, size: size * 0.45),
        ),
      ),
    );
    if (tooltip == null) return child;
    return Tooltip(message: tooltip!, child: child);
  }
}

/// 排序下拉 — 显示当前排序项
class KdsSortButton extends StatelessWidget {
  const KdsSortButton({
    super.key,
    required this.label,
    required this.onSelected,
    required this.options,
  });

  final String label;
  final ValueChanged<String> onSelected;
  final List<(String value, String label)> options;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      offset: const Offset(0, 36),
      itemBuilder: (ctx) => options
          .map(
            (o) => PopupMenuItem(
              value: o.$1,
              child: Text(o.$2, style: KdsTypography.chipLabelInactive),
            ),
          )
          .toList(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: KdsTypography.chipLabelInactive
                    .copyWith(fontWeight: FontWeight.w500)),
            const Icon(Icons.arrow_drop_down,
                color: KdsColors.segmentInactiveText, size: 20),
          ],
        ),
      ),
    );
  }
}

/// 收起按钮
class KdsCollapseButton extends StatelessWidget {
  const KdsCollapseButton({super.key, this.onPressed, this.collapsed = false});

  final VoidCallback? onPressed;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              collapsed ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
              color: KdsColors.textPrimary,
              size: 18,
            ),
            const SizedBox(width: 2),
            Text(
              collapsed ? '展开' : '收起',
              style: KdsTypography.chipLabelInactive
                  .copyWith(fontSize: 15, letterSpacing: 1),
            ),
          ],
        ),
      ),
    );
  }
}
