import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kds_app/core/theme/kds_theme.dart';

enum KdsFormFactor { compact, tablet, large, kdsWall }

/// 以 1920×1080 设计稿为基准，按启动时屏幕逻辑分辨率自适应缩放
class KdsDisplayMetrics {
  const KdsDisplayMetrics({
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.uiScale,
    required this.formFactor,
  });

  static const designWidth = 1920.0;
  static const designHeight = 1080.0;

  final double logicalWidth;
  final double logicalHeight;
  final double devicePixelRatio;
  final double uiScale;
  final KdsFormFactor formFactor;

  factory KdsDisplayMetrics.fromLogicalSize(
      Size size, double devicePixelRatio) {
    final scaleW = size.width / designWidth;
    final scaleH = size.height / designHeight;
    final uiScale = (scaleW * 0.65 + scaleH * 0.35).clamp(0.72, 1.45);
    return KdsDisplayMetrics(
      logicalWidth: size.width,
      logicalHeight: size.height,
      devicePixelRatio: devicePixelRatio,
      uiScale: uiScale,
      formFactor: _formFactor(size),
    );
  }

  factory KdsDisplayMetrics.fallback(Size size) =>
      KdsDisplayMetrics.fromLogicalSize(size, 1.0);

  static KdsFormFactor _formFactor(Size size) {
    final shortest = math.min(size.width, size.height);
    final longest = math.max(size.width, size.height);
    if (longest >= 1600 && shortest >= 900) return KdsFormFactor.kdsWall;
    if (longest >= 1280) return KdsFormFactor.large;
    if (longest >= 960) return KdsFormFactor.tablet;
    return KdsFormFactor.compact;
  }

  /// 设计稿像素 → 当前屏逻辑像素
  double dp(double designPx) => designPx * uiScale;

  double get topBarHeight => dp(KdsSpacing.topBarHeight);
  double get filterBarHeight => dp(KdsSpacing.filterBarHeight);
  double get minTouchTarget => dp(KdsSpacing.minTouch);
  double get gridGap => dp(KdsSpacing.gridGap);

  /// 菜品卡网格行距（随卡片缩放）
  double get dishGridGap => gridGap * KdsSpacing.dishCardScale;
  double get textScale => uiScale.clamp(0.85, 1.25);

  String get resolutionLabel {
    final w = logicalWidth.round();
    final h = logicalHeight.round();
    final dpr = devicePixelRatio.toStringAsFixed(1);
    return '$w×$h · ${dpr}x';
  }

  String get formFactorLabel => switch (formFactor) {
        KdsFormFactor.kdsWall => '厨显大屏',
        KdsFormFactor.large => '大平板',
        KdsFormFactor.tablet => '平板',
        KdsFormFactor.compact => '紧凑屏',
      };

  /// 看板菜品列数（按内容区宽度；列宽放大时减少列数）
  int gridColumns(double contentWidth) {
    final w = contentWidth / uiScale / KdsSpacing.dishCardScale;
    if (w >= 1680) return 7;
    if (w >= 1480) return 6;
    if (w >= 1200) return 5;
    if (w >= 900) return 4;
    if (w >= 640) return 3;
    return 2;
  }

  /// 订单视图列数 — 保证单卡宽度 ≥ 300px（设计稿逻辑宽）
  int orderGridColumns(double contentWidth) {
    const designCardWidth = 300.0;
    final minCard = dp(designCardWidth);
    final gap = gridGap;
    const horizontalPadding = 24.0;
    final available =
        (contentWidth - horizontalPadding).clamp(0.0, double.infinity);
    final cols = ((available + gap) / (minCard + gap)).floor();
    return cols.clamp(1, 4);
  }

  double orderColumnWidth(double contentWidth) {
    final cols = orderGridColumns(contentWidth);
    final gap = gridGap;
    const horizontalPadding = 24.0;
    final available = contentWidth - horizontalPadding - (cols - 1) * gap;
    return available / cols;
  }

  /// 登录表单最大宽度
  double get loginFormMaxWidth => dp(520).clamp(320, 640);

  bool get isLandscape => logicalWidth > logicalHeight;

  /// 弹窗专用缩放：横屏高度紧张时略缩小，保证一屏展示
  double get dialogUiScale =>
      isLandscape ? (uiScale * 0.88).clamp(0.68, 1.15) : uiScale;

  double dialogDp(double designPx) => designPx * dialogUiScale;

  EdgeInsets get dialogInset {
    if (isLandscape) {
      return EdgeInsets.symmetric(
        horizontal: dp(20).clamp(12, 48),
        vertical: dp(10).clamp(6, 20),
      );
    }
    return EdgeInsets.symmetric(
      horizontal: dp(48).clamp(16, 64),
      vertical: dp(24).clamp(12, 40),
    );
  }

  /// 弹窗可用宽高（扣除 inset）
  Size get dialogViewportSize {
    final inset = dialogInset;
    return Size(
      (logicalWidth - inset.horizontal).clamp(240, logicalWidth),
      (logicalHeight - inset.vertical).clamp(180, logicalHeight),
    );
  }

  double dialogMaxWidthFor(double designMax) {
    final viewport = dialogViewportSize.width;
    if (isLandscape) {
      return math.min(dp(designMax), viewport * 0.92);
    }
    return math.min(dp(designMax), viewport).clamp(280, 720);
  }

  double dialogMaxHeightFor(double designMax) {
    final viewport = dialogViewportSize.height;
    return math.min(dp(designMax), viewport * 0.98);
  }

  double get dialogMaxWidth => dialogMaxWidthFor(560);

  double get dialogContentWidth =>
      dialogMaxWidthFor(440).clamp(260, dialogMaxWidth);

  /// 数量键盘弹窗尺寸（逻辑像素，横屏宽>高，竖屏适中高度）
  ({double width, double height}) quantityModalSize() {
    final inset = dialogInset;
    final availW = (logicalWidth - inset.horizontal).clamp(280.0, logicalWidth);
    final availH = (logicalHeight - inset.vertical).clamp(320.0, logicalHeight);
    if (isLandscape) {
      return (
        width: (availW * 0.72).clamp(520.0, availW),
        height: (availH * 0.86).clamp(360.0, availH),
      );
    }
    return (
      width: (availW * 0.88).clamp(300.0, availW),
      height: (availH * 0.72).clamp(480.0, availH),
    );
  }
}
