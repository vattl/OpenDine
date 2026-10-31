import 'package:flutter/material.dart';

/// 间距/圆角/触控/限宽令牌（app_ui_standard.md §3.3/§3.4/§9）。
abstract final class MobileMetrics {
  // 4dp 网格间距
  static const spaceXs = 4.0;
  static const spaceSm = 8.0;
  static const spaceMd = 12.0;
  static const spaceLg = 16.0;
  static const spaceXl = 20.0;
  static const space2xl = 24.0;
  static const spaceSection = 32.0;

  // 页面边距
  static const pagePadding = EdgeInsets.symmetric(horizontal: spaceLg);
  static const cardPadding = EdgeInsets.all(spaceLg);
  static const cardPaddingCompact = EdgeInsets.all(spaceMd);
  static const cardGap = spaceMd;

  // 圆角
  static const radiusControl = 10.0;
  static const radiusCard = 12.0;
  static const radiusSheet = 16.0;
  static const radiusDialog = 16.0;
  static const radiusPill = 999.0;

  static BorderRadius get cardRadius => BorderRadius.circular(radiusCard);
  static BorderRadius get controlRadius => BorderRadius.circular(radiusControl);

  // 触控/高度
  static const touchTarget = 48.0;
  static const buttonHeight = 48.0;
  static const buttonHeightCta = 52.0;
  static const inputHeight = 52.0;
  static const listTileHeight = 56.0;
  static const appBarHeight = 56.0;
  static const bottomNavHeight = 64.0;
  static const tableCardHeight = 88.0;

  // 内容限宽（≥600dp 时）
  static const contentMaxWidth = 600.0;

  // 图标
  static const iconSize = 22.0;
  static const iconSizeSmall = 18.0;
}
