import 'package:flutter/material.dart';

import 'mobile_colors.dart';

/// 字阶令牌（app_ui_standard.md §3.2）。金额/订单号/统计数字用等宽数字。
///
/// 所有样式**不含颜色**（colorless），文字颜色由主题 `textTheme` 的
/// `bodyColor/displayColor` 提供（亮=炭灰、暗=米白），从而自动适配暗色。
/// 弱化文字（次要/辅助）请用 `context.bodySecondaryStyle` / `context.captionStyle`，
/// 它们带语义化的次级/弱色，亮暗均达对比标准。
abstract final class MobileTypography {
  static const _family = 'NotoSansSC';

  static const displayAmount = TextStyle(
    fontFamily: _family,
    fontSize: 28,
    height: 36 / 28,
    fontWeight: FontWeight.w700,
  );

  static const pageTitle = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w700,
  );

  static const sectionTitle = TextStyle(
    fontFamily: _family,
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );

  static const itemTitle = TextStyle(
    fontFamily: _family,
    fontSize: 17,
    height: 24 / 17,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  /// 次要正文（灰）。仅含字阶，颜色由 `context.bodySecondaryStyle` 提供。
  static const bodySecondaryBase = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    height: 24 / 16,
    fontWeight: FontWeight.w400,
  );

  static const label = TextStyle(
    fontFamily: _family,
    fontSize: 14,
    height: 20 / 14,
    fontWeight: FontWeight.w600,
  );

  /// 辅助说明（弱灰）。仅含字阶，颜色由 `context.captionStyle` 提供。
  static const captionBase = TextStyle(
    fontFamily: _family,
    fontSize: 12,
    height: 18 / 12,
    fontWeight: FontWeight.w400,
  );
}

/// 主题感知的弱化文字样式。
extension MobileTypographyX on BuildContext {
  /// 次要正文（亮=#4B5563 / 暗=#B8B8B8）。
  TextStyle get bodySecondaryStyle => MobileTypography.bodySecondaryBase
      .copyWith(color: palette.textSecondary);

  /// 辅助说明（亮=#6B7280 / 暗=#9CA3AF）。
  TextStyle get captionStyle =>
      MobileTypography.captionBase.copyWith(color: palette.textMuted);
}

/// 金额文本（统一 ¥ 前缀 + 等宽数字，app_ui_standard.md §6.5）。
class AmountText extends StatelessWidget {
  const AmountText(
    this.amount, {
    super.key,
    this.style = MobileTypography.displayAmount,
    this.negative = false,
  });

  final double amount;
  final TextStyle style;

  /// 退款/负额：同时显示负号与退款语义色（不只靠红色）。
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final formatted = _format(amount.abs());
    final text = negative ? '-¥ $formatted' : '¥ $formatted';
    final effectiveStyle = negative
        ? style.copyWith(color: context.palette.danger)
        : style;
    return Text(
      text,
      style: effectiveStyle.copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      semanticsLabel: negative ? '退款 $formatted 元' : '$formatted 元',
    );
  }

  static String _format(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '$buffer.${parts[1]}';
  }
}
