import 'package:flutter/material.dart';

/// 主题感知的收银端设计令牌（亮/暗两套）。
///
/// 组件通过 `context.cashier.xxx` 读取当前主题下的颜色，
/// 替换原先静态的 `CashierPalette` / `CashierColors` 常量，
/// 使黑夜模式下业务组件样式统一。
@immutable
class CashierTokens extends ThemeExtension<CashierTokens> {
  const CashierTokens({
    required this.canvas,
    required this.surface,
    required this.subtle,
    required this.row,
    required this.ink,
    required this.inkSecondary,
    required this.inkMuted,
    required this.border,
    required this.selected,
    required this.selectedBackground,
    required this.focus,
    required this.success,
    required this.successBackground,
    required this.warning,
    required this.warningBackground,
    required this.danger,
    required this.dangerBackground,
    required this.disabledBackground,
    required this.disabledForeground,
    required this.overlayScrim,
    required this.dishSufficient,
    required this.dishLowStock,
    required this.dishSoldOut,
    required this.btnPrimaryBg,
    required this.btnPrimaryInk,
    required this.btnSecondaryBg,
    required this.btnSecondaryInk,
    required this.tableStateIdleBar,
    required this.tableStateIdleText,
    required this.tableStateDiningBar,
    required this.tableStateDiningText,
    required this.tableStateSettlingBar,
    required this.tableStateSettlingText,
    required this.tableStateCleaningBar,
    required this.tableStateCleaningText,
    required this.tableStateReservedBar,
    required this.tableStateReservedText,
  });

  /// 页面底色。
  final Color canvas;

  /// 卡片 / 面板表面色。
  final Color surface;

  /// 轻微底色（输入框底、分隔区块）。
  final Color subtle;

  /// 行底色（列表行、内嵌面板）。
  final Color row;

  /// 主文字色。
  final Color ink;

  /// 次级文字色。
  final Color inkSecondary;

  /// 弱化文字色。
  final Color inkMuted;

  /// 分隔线 / 边框。
  final Color border;

  /// 选中强调色。
  final Color selected;

  /// 选中态背景。
  final Color selectedBackground;

  /// 焦点色。
  final Color focus;

  /// 成功前景（文字/图标）。
  final Color success;

  /// 成功背景。
  final Color successBackground;

  /// 警告前景。
  final Color warning;

  /// 警告背景。
  final Color warningBackground;

  /// 危险前景。
  final Color danger;

  /// 危险背景。
  final Color dangerBackground;

  /// 禁用态背景。
  final Color disabledBackground;

  /// 禁用态前景。
  final Color disabledForeground;

  /// 遮罩层（弹窗底、抽屉底）。
  final Color overlayScrim;

  /// 菜品状态：充足。
  final Color dishSufficient;

  /// 菜品状态：低库存。
  final Color dishLowStock;

  /// 菜品状态：售罄。
  final Color dishSoldOut;

  /// 黑白极简工业风主按键背景与文字。
  final Color btnPrimaryBg;
  final Color btnPrimaryInk;
  final Color btnSecondaryBg;
  final Color btnSecondaryInk;

  /// 桌台色块状态横幅与文字色。
  final Color tableStateIdleBar;
  final Color tableStateIdleText;
  final Color tableStateDiningBar;
  final Color tableStateDiningText;
  final Color tableStateSettlingBar;
  final Color tableStateSettlingText;
  final Color tableStateCleaningBar;
  final Color tableStateCleaningText;
  final Color tableStateReservedBar;
  final Color tableStateReservedText;

  /// 亮色令牌（高对比日空白底黑字风格）。
  static const light = CashierTokens(
    canvas: Color(0xfff1f3f5),
    surface: Color(0xffffffff),
    subtle: Color(0xfff1f3f5),
    row: Color(0xffe9ecef),
    ink: Color(0xff111827),
    inkSecondary: Color(0xff4b5563),
    inkMuted: Color(0xff9ca3af),
    border: Color(0xffdee2e6),
    selected: Color(0xff111827),
    selectedBackground: Color(0xffe5e7eb),
    focus: Color(0xff2563eb),
    success: Color(0xff16a34a),
    successBackground: Color(0xffdcfce7),
    warning: Color(0xffd97706),
    warningBackground: Color(0xfffef3c7),
    danger: Color(0xffdc2626),
    dangerBackground: Color(0xfffee2e2),
    disabledBackground: Color(0xfff3f4f6),
    disabledForeground: Color(0xff9ca3af),
    overlayScrim: Color(0x73000000),
    dishSufficient: Color(0xff16a34a),
    dishLowStock: Color(0xff2563eb),
    dishSoldOut: Color(0xffdc2626),
    btnPrimaryBg: Color(0xff111827),
    btnPrimaryInk: Color(0xffffffff),
    btnSecondaryBg: Color(0xffe5e7eb),
    btnSecondaryInk: Color(0xff111827),
    tableStateIdleBar: Color(0xffe5e7eb),
    tableStateIdleText: Color(0xff374151),
    tableStateDiningBar: Color(0xff2563eb),
    tableStateDiningText: Color(0xffffffff),
    tableStateSettlingBar: Color(0xffd97706),
    tableStateSettlingText: Color(0xffffffff),
    tableStateCleaningBar: Color(0xff16a34a),
    tableStateCleaningText: Color(0xffffffff),
    tableStateReservedBar: Color(0xff7e22ce),
    tableStateReservedText: Color(0xffffffff),
  );

  /// 暗色令牌（高对比黑曜石纯黑夜间风格）。
  static const dark = CashierTokens(
    canvas: Color(0xff09090b),
    surface: Color(0xff121214),
    subtle: Color(0xff202024),
    row: Color(0xff27272a),
    ink: Color(0xffffffff),
    inkSecondary: Color(0xffa1a1aa),
    inkMuted: Color(0xff71717a),
    border: Color(0xff27272a),
    selected: Color(0xffffffff),
    selectedBackground: Color(0xff27272a),
    focus: Color(0xff6ea8ff),
    success: Color(0xff22c55e),
    successBackground: Color(0xff1f3a2a),
    warning: Color(0xfff59e0b),
    warningBackground: Color(0xff3a3018),
    danger: Color(0xffef4444),
    dangerBackground: Color(0xff3d2323),
    disabledBackground: Color(0xff27272a),
    disabledForeground: Color(0xff71717a),
    overlayScrim: Color(0xaa000000),
    dishSufficient: Color(0xff22c55e),
    dishLowStock: Color(0xff3b82f6),
    dishSoldOut: Color(0xffef4444),
    btnPrimaryBg: Color(0xffffffff),
    btnPrimaryInk: Color(0xff09090b),
    btnSecondaryBg: Color(0xff27272a),
    btnSecondaryInk: Color(0xffffffff),
    tableStateIdleBar: Color(0xff27272a),
    tableStateIdleText: Color(0xffa1a1aa),
    tableStateDiningBar: Color(0xff1e3a8a),
    tableStateDiningText: Color(0xffbfdbfe),
    tableStateSettlingBar: Color(0xffb45309),
    tableStateSettlingText: Color(0xfffef3c7),
    tableStateCleaningBar: Color(0xff166534),
    tableStateCleaningText: Color(0xffbbf7d0),
    tableStateReservedBar: Color(0xff581c87),
    tableStateReservedText: Color(0xfff3e8ff),
  );

  @override
  CashierTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? subtle,
    Color? row,
    Color? ink,
    Color? inkSecondary,
    Color? inkMuted,
    Color? border,
    Color? selected,
    Color? selectedBackground,
    Color? focus,
    Color? success,
    Color? successBackground,
    Color? warning,
    Color? warningBackground,
    Color? danger,
    Color? dangerBackground,
    Color? disabledBackground,
    Color? disabledForeground,
    Color? overlayScrim,
    Color? dishSufficient,
    Color? dishLowStock,
    Color? dishSoldOut,
    Color? btnPrimaryBg,
    Color? btnPrimaryInk,
    Color? btnSecondaryBg,
    Color? btnSecondaryInk,
    Color? tableStateIdleBar,
    Color? tableStateIdleText,
    Color? tableStateDiningBar,
    Color? tableStateDiningText,
    Color? tableStateSettlingBar,
    Color? tableStateSettlingText,
    Color? tableStateCleaningBar,
    Color? tableStateCleaningText,
    Color? tableStateReservedBar,
    Color? tableStateReservedText,
  }) {
    return CashierTokens(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      subtle: subtle ?? this.subtle,
      row: row ?? this.row,
      ink: ink ?? this.ink,
      inkSecondary: inkSecondary ?? this.inkSecondary,
      inkMuted: inkMuted ?? this.inkMuted,
      border: border ?? this.border,
      selected: selected ?? this.selected,
      selectedBackground: selectedBackground ?? this.selectedBackground,
      focus: focus ?? this.focus,
      success: success ?? this.success,
      successBackground: successBackground ?? this.successBackground,
      warning: warning ?? this.warning,
      warningBackground: warningBackground ?? this.warningBackground,
      danger: danger ?? this.danger,
      dangerBackground: dangerBackground ?? this.dangerBackground,
      disabledBackground: disabledBackground ?? this.disabledBackground,
      disabledForeground: disabledForeground ?? this.disabledForeground,
      overlayScrim: overlayScrim ?? this.overlayScrim,
      dishSufficient: dishSufficient ?? this.dishSufficient,
      dishLowStock: dishLowStock ?? this.dishLowStock,
      dishSoldOut: dishSoldOut ?? this.dishSoldOut,
      btnPrimaryBg: btnPrimaryBg ?? this.btnPrimaryBg,
      btnPrimaryInk: btnPrimaryInk ?? this.btnPrimaryInk,
      btnSecondaryBg: btnSecondaryBg ?? this.btnSecondaryBg,
      btnSecondaryInk: btnSecondaryInk ?? this.btnSecondaryInk,
      tableStateIdleBar: tableStateIdleBar ?? this.tableStateIdleBar,
      tableStateIdleText: tableStateIdleText ?? this.tableStateIdleText,
      tableStateDiningBar: tableStateDiningBar ?? this.tableStateDiningBar,
      tableStateDiningText: tableStateDiningText ?? this.tableStateDiningText,
      tableStateSettlingBar: tableStateSettlingBar ?? this.tableStateSettlingBar,
      tableStateSettlingText: tableStateSettlingText ?? this.tableStateSettlingText,
      tableStateCleaningBar: tableStateCleaningBar ?? this.tableStateCleaningBar,
      tableStateCleaningText: tableStateCleaningText ?? this.tableStateCleaningText,
      tableStateReservedBar: tableStateReservedBar ?? this.tableStateReservedBar,
      tableStateReservedText: tableStateReservedText ?? this.tableStateReservedText,
    );
  }

  @override
  CashierTokens lerp(ThemeExtension<CashierTokens>? other, double t) {
    if (other is! CashierTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return CashierTokens(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      subtle: l(subtle, other.subtle),
      row: l(row, other.row),
      ink: l(ink, other.ink),
      inkSecondary: l(inkSecondary, other.inkSecondary),
      inkMuted: l(inkMuted, other.inkMuted),
      border: l(border, other.border),
      selected: l(selected, other.selected),
      selectedBackground: l(selectedBackground, other.selectedBackground),
      focus: l(focus, other.focus),
      success: l(success, other.success),
      successBackground: l(successBackground, other.successBackground),
      warning: l(warning, other.warning),
      warningBackground: l(warningBackground, other.warningBackground),
      danger: l(danger, other.danger),
      dangerBackground: l(dangerBackground, other.dangerBackground),
      disabledBackground: l(disabledBackground, other.disabledBackground),
      disabledForeground: l(disabledForeground, other.disabledForeground),
      overlayScrim: l(overlayScrim, other.overlayScrim),
      dishSufficient: l(dishSufficient, other.dishSufficient),
      dishLowStock: l(dishLowStock, other.dishLowStock),
      dishSoldOut: l(dishSoldOut, other.dishSoldOut),
      btnPrimaryBg: l(btnPrimaryBg, other.btnPrimaryBg),
      btnPrimaryInk: l(btnPrimaryInk, other.btnPrimaryInk),
      btnSecondaryBg: l(btnSecondaryBg, other.btnSecondaryBg),
      btnSecondaryInk: l(btnSecondaryInk, other.btnSecondaryInk),
      tableStateIdleBar: l(tableStateIdleBar, other.tableStateIdleBar),
      tableStateIdleText: l(tableStateIdleText, other.tableStateIdleText),
      tableStateDiningBar: l(tableStateDiningBar, other.tableStateDiningBar),
      tableStateDiningText: l(tableStateDiningText, other.tableStateDiningText),
      tableStateSettlingBar: l(tableStateSettlingBar, other.tableStateSettlingBar),
      tableStateSettlingText: l(tableStateSettlingText, other.tableStateSettlingText),
      tableStateCleaningBar: l(tableStateCleaningBar, other.tableStateCleaningBar),
      tableStateCleaningText: l(tableStateCleaningText, other.tableStateCleaningText),
      tableStateReservedBar: l(tableStateReservedBar, other.tableStateReservedBar),
      tableStateReservedText: l(tableStateReservedText, other.tableStateReservedText),
    );
  }
}

extension CashierTokensX on BuildContext {
  /// 当前主题下的收银端设计令牌。
  CashierTokens get cashier =>
      Theme.of(this).extension<CashierTokens>() ?? CashierTokens.light;
}
