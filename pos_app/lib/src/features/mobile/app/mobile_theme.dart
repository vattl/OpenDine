import 'package:flutter/material.dart';

import '../design/mobile_colors.dart';
import '../design/mobile_metrics.dart';
import '../design/mobile_typography.dart';

/// 移动端主题（app_ui_standard.md §10.2 集中构建 Material 3 ThemeData）。
///
/// 亮/暗双主题共用同一套结构，仅注入不同的 [MobilePalette]。
/// 文字颜色通过 `textTheme` 的 bodyColor/displayColor 提供，字阶令牌保持无色。
abstract final class MobileTheme {
  static ThemeData light() => _build(MobilePalette.light, Brightness.light);

  static ThemeData dark() => _build(MobilePalette.dark, Brightness.dark);

  static ThemeData _build(MobilePalette palette, Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: palette.brand,
      brightness: brightness,
      surface: palette.surface,
      onSurface: palette.textPrimary,
      primary: palette.brand,
      // 橙底白字仅 2.6:1 不达标；品牌橙实底统一用深炭灰文字（≈6.1:1）。
      // 暗色模式下提亮橙 #FF9330 同样配深炭灰文字。
      onPrimary: MobileColors.textPrimary,
      error: palette.danger,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      brightness: brightness,
      scaffoldBackgroundColor: palette.canvas,
      fontFamily: 'NotoSansSC',
      // 注入调色板 + 设定默认文字颜色（字阶令牌无色，统一由此供色）。
      extensions: [palette],
      textTheme: (brightness == Brightness.dark
              ? Typography.material2021().white
              : Typography.material2021().black)
          .apply(
            bodyColor: palette.textPrimary,
            displayColor: palette.textPrimary,
            fontFamily: 'NotoSansSC',
          ),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: MobileTypography.sectionTitle.copyWith(
          color: palette.textPrimary,
        ),
        toolbarHeight: MobileMetrics.appBarHeight,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: MobileMetrics.cardRadius,
          side: BorderSide(color: palette.border),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.brand,
          foregroundColor: MobileColors.textPrimary,
          minimumSize: const Size.fromHeight(MobileMetrics.buttonHeight),
          shape: RoundedRectangleBorder(
            borderRadius: MobileMetrics.controlRadius,
          ),
          textStyle: MobileTypography.label,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.brandInk,
          minimumSize: const Size.fromHeight(MobileMetrics.buttonHeight),
          side: BorderSide(color: palette.brandInk),
          shape: RoundedRectangleBorder(
            borderRadius: MobileMetrics.controlRadius,
          ),
          textStyle: MobileTypography.label,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: palette.brandInk,
          minimumSize: const Size(64, MobileMetrics.touchTarget),
          textStyle: MobileTypography.label,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: MobileMetrics.spaceLg,
          vertical: MobileMetrics.spaceMd,
        ),
        constraints: const BoxConstraints(
          minHeight: MobileMetrics.inputHeight,
        ),
        border: OutlineInputBorder(
          borderRadius: MobileMetrics.controlRadius,
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: MobileMetrics.controlRadius,
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: MobileMetrics.controlRadius,
          borderSide: BorderSide(color: palette.brandInk, width: 1.5),
        ),
        labelStyle: MobileTypography.bodySecondaryBase.copyWith(
          color: palette.textSecondary,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceSubtle,
        selectedColor: palette.brandSoft,
        labelStyle: MobileTypography.label,
        secondaryLabelStyle: MobileTypography.label.copyWith(
          color: palette.textPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: MobileMetrics.spaceMd,
          vertical: MobileMetrics.spaceSm,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: palette.surface,
        selectedItemColor: palette.brandInk,
        unselectedItemColor: palette.textMuted,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: MobileTypography.captionBase,
        unselectedLabelStyle: MobileTypography.captionBase,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: MobileMetrics.controlRadius,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStatePropertyAll(palette.border),
      ),
    );
  }
}
