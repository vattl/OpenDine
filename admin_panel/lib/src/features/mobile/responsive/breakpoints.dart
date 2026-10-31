import 'package:flutter/widgets.dart';

enum AppBreakpoint { compact, medium, large }

extension AppBreakpointValues on AppBreakpoint {
  bool get isCompact => this == AppBreakpoint.compact;
  bool get isMedium => this == AppBreakpoint.medium;
  bool get isLarge => this == AppBreakpoint.large;
}

AppBreakpoint breakpointOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width < 600) return AppBreakpoint.compact;
  if (width < 1024) return AppBreakpoint.medium;
  return AppBreakpoint.large;
}

extension ResponsiveContext on BuildContext {
  AppBreakpoint get breakpoint => breakpointOf(this);
  bool get isCompact => breakpoint == AppBreakpoint.compact;
  bool get isMedium => breakpoint == AppBreakpoint.medium;
  bool get isLarge => breakpoint == AppBreakpoint.large;
  bool get isTabletOrLarger => !isCompact;

  /// 手机横屏模式：高度紧凑 (< 500dp) 且宽度在常见手机横屏范围内 (< 1024dp)
  bool get isPhoneLandscape {
    final size = MediaQuery.sizeOf(this);
    return size.height < 500 && size.width < 1024;
  }

  /// 矮屏/紧凑高度判定 (< 500dp)
  bool get isCompactHeight => MediaQuery.sizeOf(this).height < 500;
}
