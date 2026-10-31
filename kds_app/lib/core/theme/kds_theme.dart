import 'package:flutter/material.dart';

/// KDS 设计令牌 — 对齐 UI设计代码（1920×1080 参考稿）
abstract final class KdsColors {
  // 壳层
  static const shellBg = Color(0xFF292929);
  static const topBarBg = Color(0xFF444444);
  static const filterBarBg = Color(0xFF191717);

  // 分段 / 筛选
  static const segmentBg = Color(0xFF5B5B5B);
  static const segmentActive = Color(0xFFDBDBDB);
  static const segmentActiveText = Color(0xFF3B3B3B);
  static const segmentInactiveText = Color(0xFFDBDBDB);
  static const pillBorder = Color(0xFFDBDBDB);

  // 兼容旧引用
  static const barBg = topBarBg;
  static const chipBg = segmentBg;
  static const chipActive = segmentActive;
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFDBDBDB);
  static const textMuted = Color(0xFF777777);

  // 卡片顶栏分色
  static const headerDefault = Color(0xFF444444);
  static const headerDineIn = Color(0xFFCFCFCF);
  static const headerAddDish = Color(0xFF0B88CB);
  static const headerOverdue = Color(0xFFCB0B0E);
  static const headerCombo = Color(0xFFFFB300);
  static const headerHold = Color(0xFF7C3AED);
  static const headerPack = Color(0xFF006B45);
  static const headerTakeout = Color(0xFF0CB960);

  // 卡片内容
  static const cardBody = Color(0xFFFFFFFF);
  static const cardText = Color(0xFF000000);
  static const quantityRed = Color(0xFFCB0B0E);
  static const waitMuted = Color(0xFF767676);
  static const rushGold = Color(0xFFFFC107);
  static const wsOnline = Color(0xFF0CB960);
  static const wsOffline = Color(0xFFADADAD);
  static const iconCircleBorder = Color(0xFFFFFFFF);
  static const topBarMuted = Color(0x99FFFFFF); // 60% white
}

abstract final class KdsSpacing {
  static const gridGap = 10.0;

  /// 卡片外框圆角（Figma 8px）
  static const cardOuterRadius = 8.0;

  /// 顶栏圆角与外框一致，避免双层裁剪露白
  static const cardHeaderRadius = cardOuterRadius;

  /// 兼容旧引用（详情弹窗等）
  static const cardRadius = cardHeaderRadius;

  /// 筛选 Pill 圆角 = 高度一半，形成胶囊形
  static const filterChipHeight = 38.0;
  static const filterChipRadius = 19.0;
  static const filterChipHPad = 14.0;
  static const chipRadius = filterChipRadius;
  static const segmentRadius = 13.0;
  static const minTouch = 48.0;
  static const topBarHeight = 72.0;

  /// 设计稿筛选条内 chip 高约 57px@1920，平板逻辑像素约 38px + 上下留白
  static const filterBarHeight = 56.0;

  /// 设计稿：卡片 351×283（Figma Group51）
  static const cardDesignWidth = 351.0;

  /// 看板菜品卡整体缩放（相对列宽等比布局）
  static const dishCardScale = 1.2;
  static const cardHeight = 283.0;
  static const cardHeaderHeight = 66.07;
  static const cardBodyHeight = cardHeight - cardHeaderHeight;
  static const cardTagSize = 41.0;
  static const cardTagGap = 6.0;
  static const cardTagToNameGap = 8.0;
  static const cardTagRadius = 5.0;
  static const cardClockSize = 22.0;
}

/// Figma 菜品卡片绝对坐标（351×283）
abstract final class KdsCardDesign {
  static const headerLabelLeft = 14.0;
  static const headerLabelTop = 11.22;
  static const dishNameRowLeft = 20.0;
  static const dishNameRowTop = 91.0;

  static const specLeft = 18.0;
  static const specTop = 162.0;
  static const remarkLeft = 18.0;
  static const remarkTop = 198.0;

  static const footerLeft = 20.0;
  static const footerRight = 10.0;
  static const footerBottom = 10.0;

  /// 底栏固定高度（含点击热区），文字始终贴底对齐
  static const footerBarHeight = 48.0;
  static const footerLineSize = 30.0;
  static const footerClockSize = 22.0;
  static const headerDetailRight = 8.0;
}

/// 按列宽等比缩放 — 严格保持设计稿宽高比与文字比例
class KdsCardMetrics {
  KdsCardMetrics(double columnWidth)
      : scale = (columnWidth / KdsSpacing.cardDesignWidth) *
            KdsSpacing.dishCardScale,
        width = columnWidth,
        height = KdsSpacing.cardHeight *
            (columnWidth / KdsSpacing.cardDesignWidth) *
            KdsSpacing.dishCardScale,
        headerHeight = KdsSpacing.cardHeaderHeight *
            (columnWidth / KdsSpacing.cardDesignWidth) *
            KdsSpacing.dishCardScale,
        bodyHeight = KdsSpacing.cardBodyHeight *
            (columnWidth / KdsSpacing.cardDesignWidth) *
            KdsSpacing.dishCardScale;

  final double scale;
  final double width;
  final double height;
  final double headerHeight;
  final double bodyHeight;

  double px(double designPx) => designPx * scale;

  TextStyle headerLabel(Color color) => TextStyle(
        fontSize: px(40),
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle headerDetail(Color color) => TextStyle(
        fontSize: px(30),
        fontWeight: FontWeight.w600,
        color: color,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle dishName() => TextStyle(
        fontSize: px(40),
        fontWeight: FontWeight.w800,
        color: KdsColors.cardText,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle spec({bool muted = false}) => TextStyle(
        fontSize: px(30),
        fontWeight: FontWeight.w600,
        color: KdsColors.headerOverdue.withValues(alpha: muted ? 0.72 : 1.0),
        decoration: muted ? TextDecoration.lineThrough : null,
        decorationColor: KdsOrderSpacing.lineMutedColor,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle remark() => TextStyle(
        fontSize: px(30),
        fontWeight: FontWeight.w500,
        color: KdsColors.headerOverdue,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle meta() => TextStyle(
        fontSize: px(30),
        fontWeight: FontWeight.w400,
        color: KdsColors.waitMuted,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle quantity() => TextStyle(
        fontSize: px(34),
        fontWeight: FontWeight.w600,
        color: KdsColors.quantityRed,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle quantityUnit() => quantity();

  /// 底栏时间与数量共用字号，保证同一基线
  TextStyle footerLine({required FontWeight weight, required Color color}) =>
      TextStyle(
        fontSize: px(KdsCardDesign.footerLineSize),
        fontWeight: weight,
        color: color,
        height: 1.0,
        fontFamily: 'Inter',
      );

  StrutStyle footerStrut() => StrutStyle(
        fontSize: px(KdsCardDesign.footerLineSize),
        height: 1,
        leading: 0,
        forceStrutHeight: true,
        fontFamily: 'Inter',
      );

  TextStyle tagLabel() => TextStyle(
        fontSize: px(32),
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.0,
      );
}

/// Figma 订单卡片 Group54 — 338×385
abstract final class KdsOrderSpacing {
  static const designWidth = 300.0;
  static const designHeight = 385.0;
  static const outerRadius = 16.0;
  static const headerHeight = 64.0;
  static const bodyHPadding = 21.0;
  static const orderTagSize = 31.0;
  static const lineTagSize = 22.0;
  static const tagRadius = 5.0;
  static const actionButtonWidth = 95.0;
  static const actionButtonHeight = 36.0;
  static const actionButtonRadius = 7.0;
  static const lineClockSize = 14.27;
  static const dividerColor = Color(0xFFCBCBCB);
  static const lineMutedColor = Color(0xFF9A9A9A);
  static const doneLineOpacity = 0.72;
  static const progressMuted = Color(0xFF717171);
  static const lineQtyColor = Color(0xFF4C4C4C);
  static const waitOverdue = Color(0xFFE47438);
  static const footerHintColor = Color(0xFFCBCBCB);
  static const strikeColor = Color(0xFF5F5F5F);
}

/// 订单卡片按列宽等比缩放
class KdsOrderCardMetrics {
  KdsOrderCardMetrics(this.width)
      : scale = width / KdsOrderSpacing.designWidth,
        headerHeight = KdsOrderSpacing.headerHeight *
            (width / KdsOrderSpacing.designWidth);

  final double scale;
  final double width;
  final double headerHeight;

  double px(double designPx) => designPx * scale;

  TextStyle tableNumber(Color color) => TextStyle(
        fontSize: px(32),
        fontWeight: FontWeight.w500,
        color: color,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle actionLabel(Color color) => TextStyle(
        fontSize: px(20),
        fontWeight: FontWeight.w400,
        color: color,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle progress() => TextStyle(
        fontSize: px(18),
        fontWeight: FontWeight.w500,
        color: KdsOrderSpacing.progressMuted,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle orderTagLabel() => TextStyle(
        fontSize: px(24),
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle lineTagLabel() => TextStyle(
        fontSize: px(16),
        fontWeight: FontWeight.w600,
        color: Colors.white,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle roundLabel({double opacity = 1}) => TextStyle(
        fontSize: px(18),
        fontWeight: FontWeight.w500,
        color: KdsOrderSpacing.progressMuted.withValues(alpha: opacity),
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle lineName({required bool done}) => TextStyle(
        fontSize: px(24),
        fontWeight: FontWeight.w600,
        color: done ? KdsOrderSpacing.lineMutedColor : KdsColors.cardText,
        decoration: done ? TextDecoration.lineThrough : null,
        decorationColor: KdsOrderSpacing.strikeColor,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle lineQty({required bool done}) => TextStyle(
        fontSize: px(16),
        fontWeight: FontWeight.w400,
        color: done
            ? KdsOrderSpacing.lineMutedColor
            : KdsOrderSpacing.lineQtyColor,
        decoration: done ? TextDecoration.lineThrough : null,
        decorationColor: KdsOrderSpacing.strikeColor,
        height: 1.0,
        fontFamily: 'Inter',
      );

  /// 订单行规格/做法 — 红色强调（已划行删除线 + 略淡）
  TextStyle lineSpec({required bool done}) => TextStyle(
        fontSize: px(16),
        fontWeight: FontWeight.w600,
        color: KdsColors.headerOverdue.withValues(alpha: done ? 0.72 : 1.0),
        decoration: done ? TextDecoration.lineThrough : null,
        decorationColor: KdsOrderSpacing.strikeColor,
        height: 1.15,
        fontFamily: 'Inter',
      );

  TextStyle waitTime({required bool done, required bool overdue}) => TextStyle(
        fontSize: px(16),
        fontWeight: FontWeight.w400,
        color: overdue ? KdsOrderSpacing.waitOverdue : KdsColors.waitMuted,
        height: 1.0,
        fontFamily: 'Inter',
      );

  TextStyle remark() => TextStyle(
        fontSize: px(18),
        fontWeight: FontWeight.w500,
        color: KdsColors.headerOverdue,
        height: 1.2,
        fontFamily: 'Inter',
      );

  TextStyle footerHint() => TextStyle(
        fontSize: px(12),
        fontWeight: FontWeight.w400,
        color: KdsOrderSpacing.footerHintColor,
        height: 1.0,
        fontFamily: 'Inter',
      );
}

abstract final class KdsTypography {
  static const mainTabSelected = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    color: KdsColors.textPrimary,
  );
  static const mainTabNormal = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w400,
    color: KdsColors.topBarMuted,
  );
  static const brandTitle = TextStyle(
    fontSize: 26,
    fontWeight: FontWeight.w600,
    color: KdsColors.textPrimary,
    letterSpacing: 3,
  );
  static const chipLabel = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
  );
  static const chipLabelActive = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    color: KdsColors.segmentActiveText,
    height: 1.1,
  );
  static const chipLabelInactive = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: KdsColors.segmentInactiveText,
    height: 1.1,
  );
  static const cardHeaderLabel = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w500,
    height: 1.0,
  );
  static const cardDetailLink = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w500,
    height: 1.0,
  );
  static const cardDishName = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w800,
    color: KdsColors.cardText,
    height: 1.0,
  );
  static const cardRemark = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: KdsColors.cardText,
    height: 1.2,
  );

  /// 规格/做法 — 红色强调（与备注区分：备注用 cardRemark + headerOverdue 在组件内）
  static TextStyle cardSpec({double? fontSize}) => TextStyle(
        fontSize: fontSize ?? 24,
        fontWeight: FontWeight.w600,
        color: KdsColors.headerOverdue,
        height: 1.15,
        fontFamily: 'Inter',
      );
  static const cardMeta = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w400,
    color: KdsColors.waitMuted,
    height: 1.0,
  );
  static const cardQuantity = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: KdsColors.quantityRed,
    height: 1.0,
  );
}

ThemeData buildKdsTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: KdsColors.shellBg,
    colorScheme: const ColorScheme.dark(
      surface: KdsColors.shellBg,
      primary: KdsColors.headerAddDish,
      onSurface: KdsColors.textPrimary,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: KdsColors.topBarBg,
      foregroundColor: KdsColors.textPrimary,
      elevation: 0,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: KdsColors.filterBarBg,
      textStyle: KdsTypography.chipLabelInactive,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: KdsColors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        color: KdsColors.textSecondary,
      ),
    ),
  );
}
