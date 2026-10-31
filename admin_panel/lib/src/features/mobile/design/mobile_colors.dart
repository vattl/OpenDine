import 'package:flutter/material.dart';

/// 语义色令牌·亮色基准（app_ui_standard.md §3.1）。业务页面禁止直接写 Color(0xFF...)。
///
/// 暗色模式：业务页面统一改用 `context.palette.xxx`（见 [MobilePalette]），
/// 本类的静态常量仅保留给亮色主题构建与状态徽标（SemanticTone）使用。
abstract final class MobileColors {
  // 品牌（暖橙 #FF7A00，见 design-system/laofei-mobile/prototype-prompts.md §五）
  static const brand = Color(0xFFFF7A00);
  static const brandPressed = Color(0xFFE56E00);
  static const brandSoft = Color(0xFFFFE4CC);

  // 浅底上的品牌色文字/图标/描边：橙 #FF7A00 在白底仅 2.6:1 不达标，
  // 交互文字与图标统一用加深橙（白底 4.6:1，满足 AA 正文与非文本 3:1）。
  static const brandInk = Color(0xFFB85C00);

  // 表面
  static const canvas = Color(0xFFF8F5F0);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSubtle = Color(0xFFF9FAFB);

  // 文本
  static const textPrimary = Color(0xFF222222);
  static const textSecondary = Color(0xFF4B5563);
  static const textMuted = Color(0xFF6B7280);
  static const textDisabled = Color(0xFF9CA3AF);

  // 边框/遮罩
  static const border = Color(0xFFE5E7EB);
  static const overlayScrim = Color(0x99000000);

  // 语义色（前景 / 浅背景成对）。前景用加深色保证浅底 4.5:1，
  // 浅背景取品牌辅助色 #28C76F / #EA5455 的 12% 白底混合。
  static const success = Color(0xFF15803D);
  static const successBg = Color(0xFFE5F8EE);
  static const warning = Color(0xFFB45309);
  static const warningBg = Color(0xFFFEF3C7);
  static const danger = Color(0xFFC73637);
  static const dangerBg = Color(0xFFFCEAEB);
  static const info = Color(0xFF1E6FEB);
  static const infoBg = Color(0xFFDBEAFE);
  static const neutral = Color(0xFF6B7280);
  static const neutralBg = Color(0xFFF3F4F6);

  // 底部购物车/操作栏深底（白字经对比验证）
  static const cartBar = Color(0xFF222222);
}

/// 语义色对（浅背景+深前景，用于状态标签）。
///
/// 状态徽标在暗色模式下保持浅底深字：自包含的小标签在深色卡片上
/// 依然清晰可辨（原型文档 §2.2），因此不做暗色变体。
class SemanticTone {
  const SemanticTone(this.foreground, this.background);

  final Color foreground;
  final Color background;

  static const success = SemanticTone(MobileColors.success, MobileColors.successBg);
  static const warning = SemanticTone(MobileColors.warning, MobileColors.warningBg);
  static const danger = SemanticTone(MobileColors.danger, MobileColors.dangerBg);
  static const info = SemanticTone(MobileColors.info, MobileColors.infoBg);
  static const neutral = SemanticTone(MobileColors.neutral, MobileColors.neutralBg);
}

/// 主题感知的完整调色板（ThemeExtension）。亮色与暗色各一份，
/// 通过 `ThemeData(extensions: ...)` 注入，业务代码用 `context.palette` 访问。
class MobilePalette extends ThemeExtension<MobilePalette> {
  const MobilePalette({
    required this.brand,
    required this.brandPressed,
    required this.brandSoft,
    required this.brandInk,
    required this.canvas,
    required this.surface,
    required this.surfaceSubtle,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textDisabled,
    required this.border,
    required this.overlayScrim,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.neutral,
    required this.successBg,
    required this.warningBg,
    required this.dangerBg,
    required this.infoBg,
    required this.neutralBg,
    required this.cartBar,
  });

  final Color brand;
  final Color brandPressed;
  final Color brandSoft;
  final Color brandInk;
  final Color canvas;
  final Color surface;
  final Color surfaceSubtle;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textDisabled;
  final Color border;
  final Color overlayScrim;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color neutral;
  final Color successBg;
  final Color warningBg;
  final Color dangerBg;
  final Color infoBg;
  final Color neutralBg;
  final Color cartBar;

  /// 亮色：与 [MobileColors] 静态常量一致。
  static const light = MobilePalette(
    brand: MobileColors.brand,
    brandPressed: MobileColors.brandPressed,
    brandSoft: MobileColors.brandSoft,
    brandInk: MobileColors.brandInk,
    canvas: MobileColors.canvas,
    surface: MobileColors.surface,
    surfaceSubtle: MobileColors.surfaceSubtle,
    textPrimary: MobileColors.textPrimary,
    textSecondary: MobileColors.textSecondary,
    textMuted: MobileColors.textMuted,
    textDisabled: MobileColors.textDisabled,
    border: MobileColors.border,
    overlayScrim: MobileColors.overlayScrim,
    success: MobileColors.success,
    warning: MobileColors.warning,
    danger: MobileColors.danger,
    info: MobileColors.info,
    neutral: MobileColors.neutral,
    successBg: MobileColors.successBg,
    warningBg: MobileColors.warningBg,
    dangerBg: MobileColors.dangerBg,
    infoBg: MobileColors.infoBg,
    neutralBg: MobileColors.neutralBg,
    cartBar: MobileColors.cartBar,
  );

  /// 暗色（原型文档 §2.2 夜间深色版）：深炭底、米白字、提亮暖橙。
  static const dark = MobilePalette(
    brand: Color(0xFFFF9330),
    brandPressed: Color(0xFFFF7A00),
    brandSoft: Color(0xFF4A2E12),
    brandInk: Color(0xFFFFB066),
    canvas: Color(0xFF1E1E1E),
    surface: Color(0xFF2B2B2B),
    surfaceSubtle: Color(0xFF262626),
    textPrimary: Color(0xFFF8F5F0),
    textSecondary: Color(0xFFB8B8B8),
    textMuted: Color(0xFF9CA3AF),
    textDisabled: Color(0xFF6B7280),
    border: Color(0xFF3D3D3D),
    overlayScrim: Color(0xB3000000),
    success: Color(0xFF2ED57F),
    warning: Color(0xFFFFB020),
    danger: Color(0xFFFF6B6C),
    info: Color(0xFF5B9DFF),
    neutral: Color(0xFF9CA3AF),
    successBg: Color(0xFF173A28),
    warningBg: Color(0xFF3A2C12),
    dangerBg: Color(0xFF3A1F20),
    infoBg: Color(0xFF1E2A3D),
    neutralBg: Color(0xFF333333),
    cartBar: Color(0xFF101010),
  );

  @override
  MobilePalette copyWith({
    Color? brand,
    Color? brandPressed,
    Color? brandSoft,
    Color? brandInk,
    Color? canvas,
    Color? surface,
    Color? surfaceSubtle,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textDisabled,
    Color? border,
    Color? overlayScrim,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? neutral,
    Color? successBg,
    Color? warningBg,
    Color? dangerBg,
    Color? infoBg,
    Color? neutralBg,
    Color? cartBar,
  }) {
    return MobilePalette(
      brand: brand ?? this.brand,
      brandPressed: brandPressed ?? this.brandPressed,
      brandSoft: brandSoft ?? this.brandSoft,
      brandInk: brandInk ?? this.brandInk,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      neutral: neutral ?? this.neutral,
      successBg: successBg ?? this.successBg,
      warningBg: warningBg ?? this.warningBg,
      dangerBg: dangerBg ?? this.dangerBg,
      infoBg: infoBg ?? this.infoBg,
      neutralBg: neutralBg ?? this.neutralBg,
      cartBar: cartBar ?? this.cartBar,
    );
  }

  @override
  MobilePalette lerp(MobilePalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MobilePalette(
      brand: l(brand, other.brand),
      brandPressed: l(brandPressed, other.brandPressed),
      brandSoft: l(brandSoft, other.brandSoft),
      brandInk: l(brandInk, other.brandInk),
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceSubtle: l(surfaceSubtle, other.surfaceSubtle),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      textDisabled: l(textDisabled, other.textDisabled),
      border: l(border, other.border),
      overlayScrim: l(overlayScrim, other.overlayScrim),
      success: l(success, other.success),
      warning: l(warning, other.warning),
      danger: l(danger, other.danger),
      info: l(info, other.info),
      neutral: l(neutral, other.neutral),
      successBg: l(successBg, other.successBg),
      warningBg: l(warningBg, other.warningBg),
      dangerBg: l(dangerBg, other.dangerBg),
      infoBg: l(infoBg, other.infoBg),
      neutralBg: l(neutralBg, other.neutralBg),
      cartBar: l(cartBar, other.cartBar),
    );
  }
}

/// `context.palette` 快捷访问当前亮/暗调色板。
extension MobilePaletteX on BuildContext {
  MobilePalette get palette =>
      Theme.of(this).extension<MobilePalette>() ?? MobilePalette.light;

  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
