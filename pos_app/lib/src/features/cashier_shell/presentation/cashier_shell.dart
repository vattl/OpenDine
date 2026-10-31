import 'package:flutter/material.dart';

import '../../mobile/responsive/breakpoints.dart';
import 'cashier_tokens.dart';

enum CashierSection {
  table('桌台', Icons.grid_view_rounded),
  ordering('点餐', Icons.restaurant_menu_rounded),
  bills('账单', Icons.receipt_long_rounded),
  members('会员', Icons.people_alt_outlined),
  dishStatus('菜品', Icons.room_service_outlined),
  shift('当班', Icons.schedule_rounded),
  manage('管理', Icons.dashboard_customize_outlined),
  settings('设置', Icons.settings_outlined);

  const CashierSection(this.label, this.icon);

  final String label;
  final IconData icon;

  static const valuesSet = <CashierSection>{
    table,
    ordering,
    bills,
    members,
    dishStatus,
    shift,
    manage,
    settings,
  };
}

class CashierShell extends StatelessWidget {
  const CashierShell({
    super.key,
    required this.currentSection,
    required this.onSectionChanged,
    required this.body,
    required this.storeText,
    this.storeTitle,
    this.connectionText = '云端在线 (12ms)',
    this.connected = true,
    this.kdsAvailable = true,
    this.kdsText,
    this.visibleSections = CashierSection.valuesSet,
    this.brandText = '',
    this.timeText,
    this.dateText,
    this.cashierName,
    this.cashierWorkNo,
    this.hangOrderCount = 0,
    this.fulfillmentCount = 0,
    this.onToggleTheme,
    this.isDarkMode,
    this.onOpenHangPool,
    this.onOpenFulfillment,
    this.onSwitchAccount,
    this.onOpenProfile,
    this.onLogout,
    this.leadingActions = const [],
    this.topActions = const [],
    this.bottomBar,
    this.collapsed = false,
    this.onToggleCollapse,
    this.showSidebar = true,
    this.bodyPadding,
  });

  static const sidebarWidth = 92.0;
  static const collapsedSidebarWidth = 68.0;
  static const barHeight = 68.0;

  static String formatClock(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  static String formatDate(DateTime value) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${weekdays[value.weekday - 1]}';
  }

  final CashierSection currentSection;
  final ValueChanged<CashierSection> onSectionChanged;
  final Widget body;
  final List<Widget> leadingActions;
  final List<Widget> topActions;
  final Widget? bottomBar;
  final Set<CashierSection> visibleSections;
  final String connectionText;
  final String storeText;

  /// 自定义或一体化门店标题/切换器组件（例如 [_ShopPicker]）。
  /// 传入时将替代静态文本 [storeText]，彻底避免左上角门店名称与下拉切换重复显示。
  final Widget? storeTitle;
  final String brandText;
  final bool connected;
  final bool kdsAvailable;
  final String? kdsText;
  final String? timeText;
  final String? dateText;
  final String? cashierName;
  final String? cashierWorkNo;
  final int hangOrderCount;
  final int fulfillmentCount;
  final VoidCallback? onToggleTheme;
  final bool? isDarkMode;
  final VoidCallback? onOpenHangPool;
  final VoidCallback? onOpenFulfillment;
  final VoidCallback? onSwitchAccount;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onLogout;

  /// 侧边栏是否收起（仅图标）
  final bool collapsed;

  /// 收起/展开切换入口；为 null 时不显示切换按钮
  final VoidCallback? onToggleCollapse;

  /// 是否展示侧边栏导航（二级子页面或特定全宽视图下可设为 false 仅保留置顶状态栏）
  final bool showSidebar;

  /// 工作区外部边距；为空时默认在手机横屏取 6dp、桌面/平板取 16dp
  final EdgeInsetsGeometry? bodyPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = context.cashier;
    final effectiveBrandText = brandText.trim().isEmpty ? storeText : brandText;

    final regularSections = CashierSection.values.where(
      (s) => s != CashierSection.settings && visibleSections.contains(s),
    );
    final hasSettings = visibleSections.contains(CashierSection.settings);

    final isPhoneLandscape = context.isPhoneLandscape;
    final isCompact = context.isCompact && !isPhoneLandscape;
    final isMedium = context.isMedium;
    final effectiveCollapsed = collapsed || isMedium || isPhoneLandscape;

    if (isCompact) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        bottomNavigationBar: showSidebar
            ? _MobileBottomNav(
                currentSection: currentSection,
                visibleSections: visibleSections,
                onSectionChanged: onSectionChanged,
              )
            : null,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _MobileTopBar(
                storeText: effectiveBrandText,
                storeTitle: storeTitle,
                connectionText: connectionText,
                connected: connected,
                timeText: timeText,
                dateText: dateText,
                cashierName: cashierName ?? '张晓峰',
                cashierWorkNo: cashierWorkNo ?? '0801',
                hangOrderCount: hangOrderCount,
                fulfillmentCount: fulfillmentCount,
                onToggleTheme: onToggleTheme,
                isDarkMode: isDarkMode ?? (theme.brightness == Brightness.dark),
                onOpenHangPool: onOpenHangPool,
                onOpenFulfillment: onOpenFulfillment,
                onSwitchAccount: onSwitchAccount,
                onOpenProfile: onOpenProfile,
                onLogout: onLogout,
                leadingActions: leadingActions,
                actions: topActions,
              ),
              Expanded(
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: Padding(
                    padding: bodyPadding ?? const EdgeInsets.all(8),
                    child: body,
                  ),
                ),
              ),
              if (bottomBar != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: tokens.surface,
                    border: Border(top: BorderSide(color: tokens.border)),
                  ),
                  child: bottomBar,
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // 顶部状态栏常驻置顶 (全宽 100%)
          _TopBar(
            storeText: effectiveBrandText,
            storeTitle: storeTitle,
            connectionText: connectionText,
            connected: connected,
            kdsAvailable: kdsAvailable,
            kdsText: kdsText,
            timeText: timeText,
            dateText: dateText,
            cashierName: cashierName ?? '张晓峰',
            cashierWorkNo: cashierWorkNo ?? '0801',
            hangOrderCount: hangOrderCount,
            fulfillmentCount: fulfillmentCount,
            onToggleTheme: onToggleTheme,
            isDarkMode: isDarkMode ?? (theme.brightness == Brightness.dark),
            onOpenHangPool: onOpenHangPool,
            onOpenFulfillment: onOpenFulfillment,
            onSwitchAccount: onSwitchAccount,
            onOpenProfile: onOpenProfile,
            onLogout: onLogout,
            leadingActions: leadingActions,
            actions: topActions,
          ),

          // 主体区域：左侧一级导航栏 + 右侧工作区
          Expanded(
            child: Row(
              children: [
                // 左侧一级导航栏 (平板 56dp / 电脑 72dp)
                if (showSidebar)
                  Container(
                    width: effectiveCollapsed
                        ? collapsedSidebarWidth
                        : sidebarWidth,
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      border: Border(right: BorderSide(color: tokens.border)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(height: isPhoneLandscape ? 4 : 10),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const ClampingScrollPhysics(),
                            child: SizedBox(
                              width: double.infinity,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  for (final section in regularSections)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: isPhoneLandscape ? 4 : 6,
                                      ),
                                      child: _NavigationItem(
                                        section: section,
                                        selected: currentSection == section,
                                        collapsed: effectiveCollapsed,
                                        compactHeight: isPhoneLandscape,
                                        onTap: () => onSectionChanged(section),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (hasSettings)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: isPhoneLandscape ? 4 : 6,
                            ),
                            child: _NavigationItem(
                              section: CashierSection.settings,
                              selected: currentSection == CashierSection.settings,
                              collapsed: effectiveCollapsed,
                              compactHeight: isPhoneLandscape,
                              onTap: () =>
                                  onSectionChanged(CashierSection.settings),
                            ),
                          ),
                        if (onToggleCollapse != null && !isPhoneLandscape)
                          _CollapseToggle(
                            collapsed: effectiveCollapsed,
                            onTap: onToggleCollapse!,
                          ),
                        if (!isPhoneLandscape) const SizedBox(height: 8),
                      ],
                    ),
                  ),

                // 右侧工作区
                Expanded(
                  child: ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: Padding(
                      padding: bodyPadding ?? EdgeInsets.all(isPhoneLandscape ? 6 : 16),
                      child: body,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (bottomBar != null)
            Container(
              height: barHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: bottomBar,
            ),
        ],
      ),
    );
  }
}

class _NavigationItem extends StatelessWidget {
  const _NavigationItem({
    required this.section,
    required this.selected,
    required this.collapsed,
    this.compactHeight = false,
    required this.onTap,
  });

  final CashierSection section;
  final bool selected;
  final bool collapsed;
  final bool compactHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final selectedBackground = tokens.ink;
    final selectedForeground = tokens.btnPrimaryInk;
    final unselectedForeground = tokens.inkSecondary;

    final width = collapsed
        ? (compactHeight ? 48.0 : 56.0)
        : (compactHeight ? 56.0 : 78.0);
    final height = compactHeight
        ? 40.0
        : (collapsed ? 58.0 : 68.0);

    final item = SizedBox(
      width: width,
      height: height,
      child: Material(
        color: selected ? selectedBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          hoverColor: tokens.subtle,
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 0 : 4,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? selectedBackground : Colors.transparent,
                width: 1,
              ),
            ),
            child: collapsed
                ? Icon(
                    section.icon,
                    size: compactHeight ? 22 : 28,
                    color: selected ? selectedForeground : unselectedForeground,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        section.icon,
                        size: compactHeight ? 20 : 28,
                        color: selected ? selectedForeground : unselectedForeground,
                      ),
                      SizedBox(height: compactHeight ? 2 : 4),
                      Text(
                        section.label,
                        style: TextStyle(
                          color: selected ? selectedForeground : unselectedForeground,
                          fontSize: compactHeight ? 10 : 13.5,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );

    final child = collapsed
        ? Tooltip(message: section.label, child: item)
        : item;

    return Semantics(
      key: Key('cashier-nav-${section.name}'),
      button: true,
      selected: selected,
      label: section.label,
      child: child,
    );
  }
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({required this.collapsed, required this.onTap});

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Tooltip(
      message: collapsed ? '展开侧边栏' : '收起侧边栏',
      child: InkWell(
        key: const Key('cashier-sidebar-toggle'),
        onTap: onTap,
        child: SizedBox(
          height: 38,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                collapsed
                    ? Icons.keyboard_double_arrow_right
                    : Icons.keyboard_double_arrow_left,
                size: 16,
                color: tokens.inkMuted,
              ),
              if (!collapsed) ...[
                const SizedBox(width: 4),
                Text(
                  '收起',
                  style: TextStyle(
                    color: tokens.inkMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.storeText,
    this.storeTitle,
    required this.connectionText,
    required this.connected,
    required this.kdsAvailable,
    this.kdsText,
    this.timeText,
    this.dateText,
    required this.cashierName,
    required this.cashierWorkNo,
    required this.hangOrderCount,
    required this.fulfillmentCount,
    this.onToggleTheme,
    required this.isDarkMode,
    this.onOpenHangPool,
    this.onOpenFulfillment,
    this.onSwitchAccount,
    this.onOpenProfile,
    this.onLogout,
    this.leadingActions = const [],
    required this.actions,
  });

  final String storeText;
  final Widget? storeTitle;
  final String connectionText;
  final bool connected;
  final bool kdsAvailable;
  final String? kdsText;
  final String? timeText;
  final String? dateText;
  final String cashierName;
  final String cashierWorkNo;
  final int hangOrderCount;
  final int fulfillmentCount;
  final VoidCallback? onToggleTheme;
  final bool isDarkMode;
  final VoidCallback? onOpenHangPool;
  final VoidCallback? onOpenFulfillment;
  final VoidCallback? onSwitchAccount;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onLogout;
  final List<Widget> leadingActions;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final isPhoneLandscape = context.isPhoneLandscape;
    final barHeight = isPhoneLandscape ? 48.0 : CashierShell.barHeight;
    final btnGap = isPhoneLandscape ? 8.0 : 12.0;

    return Container(
      height: barHeight,
      padding: EdgeInsets.symmetric(horizontal: isPhoneLandscape ? 10 : 20),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          // 左侧：门店名称 + 门店切换/营业开关 + 状态芯片 (topbar-left)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/icons/pos/laofei_brand_avatar.png',
                  key: const Key('cashier-brand-avatar'),
                  width: isPhoneLandscape ? 26 : 34,
                  height: isPhoneLandscape ? 26 : 34,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.storefront_rounded,
                    size: isPhoneLandscape ? 24 : 30,
                    color: tokens.ink,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (storeTitle != null)
                storeTitle!
              else
                Text(
                  storeText,
                  key: const Key('cashier-brand-store-name'),
                  style: TextStyle(
                    color: tokens.ink,
                    fontSize: isPhoneLandscape ? 15 : 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              if (leadingActions.isNotEmpty) ...[
                SizedBox(width: isPhoneLandscape ? 8 : 12),
                ...leadingActions,
              ],
              SizedBox(width: isPhoneLandscape ? 10 : 16),
              // 云端在线胶囊
              Tooltip(
                message: connectionText.isNotEmpty
                    ? connectionText
                    : (connected ? '云端在线 (12ms)' : '云端离线'),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isPhoneLandscape ? 8 : 10,
                    vertical: isPhoneLandscape ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.subtle,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: isPhoneLandscape ? 8 : 9,
                        height: isPhoneLandscape ? 8 : 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: connected ? const Color(0xff10b981) : const Color(0xffef4444),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        connected ? Icons.cloud_done_rounded : Icons.cloud_off_rounded,
                        size: isPhoneLandscape ? 14 : 16,
                        color: connected ? const Color(0xff10b981) : const Color(0xffef4444),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        connectionText.isNotEmpty
                            ? connectionText
                            : (isPhoneLandscape
                                ? (connected ? '在线' : '离线')
                                : (connected ? '云端在线 (12ms)' : '云端离线')),
                        style: TextStyle(
                          color: tokens.inkSecondary,
                          fontSize: isPhoneLandscape ? 11 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 后厨 KDS 胶囊
              Tooltip(
                message: kdsText ??
                    (isPhoneLandscape
                        ? (kdsAvailable ? 'KDS正常' : 'KDS未接')
                        : (kdsAvailable ? '后厨 KDS: 正常已连' : '后厨 KDS: 未接入')),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: isPhoneLandscape ? 8 : 10,
                    vertical: isPhoneLandscape ? 4 : 6,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.subtle,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: isPhoneLandscape ? 8 : 9,
                        height: isPhoneLandscape ? 8 : 9,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: kdsAvailable ? const Color(0xff10b981) : const Color(0xffef4444),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.kitchen_rounded,
                        size: isPhoneLandscape ? 14 : 16,
                        color: kdsAvailable ? tokens.inkSecondary : const Color(0xffef4444),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        kdsText ??
                            (isPhoneLandscape
                                ? (kdsAvailable ? 'KDS正常' : 'KDS未接')
                                : (kdsAvailable ? '后厨 KDS: 正常已连' : '后厨 KDS: 未接入')),
                        style: TextStyle(
                          color: tokens.inkSecondary,
                          fontSize: isPhoneLandscape ? 11 : 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 右侧：主题切换 + 挂单池 + 履约外卖 + 收银员身份 + 换班 + 退出 (topbar-right)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 主题切换（图标化）
                    _TopBarIconButton(
                      key: const Key('topbar-theme-toggle-btn'),
                      icon: isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                      tooltip: isDarkMode ? '切换日间模式' : '切换夜间模式',
                      isThemeToggle: true,
                      compact: isPhoneLandscape,
                      onTap: onToggleTheme,
                    ),
                    SizedBox(width: btnGap),
                    // 挂单池（图标化 + 角标）
                    _TopBarIconButton(
                      key: const Key('topbar-hang-pool-btn'),
                      icon: Icons.receipt_long_rounded,
                      badgeCount: hangOrderCount,
                      tooltip: '挂单池 ($hangOrderCount)',
                      compact: isPhoneLandscape,
                      onTap: onOpenHangPool,
                    ),
                    SizedBox(width: btnGap),
                    // 履约外卖（图标化 + 角标）
                    _TopBarIconButton(
                      key: const Key('topbar-fulfillment-btn'),
                      icon: Icons.two_wheeler_rounded,
                      badgeCount: fulfillmentCount,
                      tooltip: '履约外卖 ($fulfillmentCount)',
                      compact: isPhoneLandscape,
                      onTap: onOpenFulfillment,
                    ),
                    SizedBox(width: btnGap),
                    // 收银员信息 / 档案胶囊（精简图标化胶囊）
                    Tooltip(
                      message: '收银员: $cashierName ($cashierWorkNo)',
                      child: InkWell(
                        key: const Key('cashier-identity-capsule'),
                        onTap: onOpenProfile,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          height: isPhoneLandscape ? 36 : 44,
                          padding: EdgeInsets.symmetric(
                            horizontal: isPhoneLandscape ? 8 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: tokens.subtle,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: tokens.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person_outline_rounded,
                                size: isPhoneLandscape ? 16 : 20,
                                color: tokens.ink,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                cashierName,
                                style: TextStyle(
                                  color: tokens.ink,
                                  fontSize: isPhoneLandscape ? 12 : 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: btnGap),
                    // 换班（图标化）
                    _TopBarIconButton(
                      key: const Key('topbar-shift-switch-btn'),
                      icon: Icons.switch_account_outlined,
                      tooltip: '换班 / 切换账号',
                      compact: isPhoneLandscape,
                      onTap: onSwitchAccount,
                    ),
                    if (onLogout != null) ...[
                      SizedBox(width: btnGap),
                      // 退出（图标化）
                      _TopBarIconButton(
                        key: const Key('topbar-logout-btn'),
                        icon: Icons.logout_rounded,
                        tooltip: '退出登录',
                        compact: isPhoneLandscape,
                        onTap: onLogout,
                      ),
                    ],
                    if (actions.isNotEmpty) ...[
                      SizedBox(width: btnGap),
                      ...actions,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.badgeCount = 0,
    this.isThemeToggle = false,
    this.compact = false,
    this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final int badgeCount;
  final bool isThemeToggle;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final size = compact ? 36.0 : 44.0;
    final iconSize = compact ? 18.0 : 22.0;

    Widget iconWidget = Icon(
      icon,
      size: iconSize,
      color: tokens.ink,
    );

    if (badgeCount > 0) {
      iconWidget = Badge(
        label: Text(
          badgeCount > 99 ? '99+' : '$badgeCount',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xffef4444),
        child: iconWidget,
      );
    }

    return Tooltip(
      message: tooltip,
      child: Material(
        color: isThemeToggle ? tokens.subtle : tokens.surface,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          hoverColor: tokens.subtle,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border),
            ),
            alignment: Alignment.center,
            child: iconWidget,
          ),
        ),
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.storeText,
    this.storeTitle,
    required this.connectionText,
    required this.connected,
    this.timeText,
    this.dateText,
    required this.cashierName,
    required this.cashierWorkNo,
    required this.hangOrderCount,
    required this.fulfillmentCount,
    this.onToggleTheme,
    required this.isDarkMode,
    this.onOpenHangPool,
    this.onOpenFulfillment,
    this.onSwitchAccount,
    this.onOpenProfile,
    this.onLogout,
    this.leadingActions = const [],
    required this.actions,
  });

  final String storeText;
  final Widget? storeTitle;
  final String connectionText;
  final bool connected;
  final String? timeText;
  final String? dateText;
  final String cashierName;
  final String cashierWorkNo;
  final int hangOrderCount;
  final int fulfillmentCount;
  final VoidCallback? onToggleTheme;
  final bool isDarkMode;
  final VoidCallback? onOpenHangPool;
  final VoidCallback? onOpenFulfillment;
  final VoidCallback? onSwitchAccount;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onLogout;
  final List<Widget> leadingActions;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              'assets/icons/pos/laofei_brand_avatar.png',
              key: const Key('cashier-brand-avatar'),
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.storefront_rounded,
                size: 24,
                color: tokens.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: storeTitle ??
                Text(
                  storeText,
                  key: const Key('cashier-brand-store-name'),
                  style: TextStyle(
                    color: tokens.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
          if (leadingActions.isNotEmpty) ...[
            const SizedBox(width: 6),
            ...leadingActions,
          ],
          const SizedBox(width: 8),
          Tooltip(
            message: connected ? (connectionText.isNotEmpty ? connectionText : '云端在线') : '云端离线',
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: connected ? const Color(0xff10b981) : const Color(0xffef4444),
              ),
            ),
          ),
          const Spacer(),
          if (actions.isNotEmpty) ...[
            ...actions,
            const SizedBox(width: 6),
          ],
          // 挂单池
          IconButton(
            key: const Key('topbar-hang-pool-btn'),
            icon: Badge(
              isLabelVisible: hangOrderCount > 0,
              label: Text('$hangOrderCount'),
              child: const Icon(Icons.receipt_outlined, size: 24),
            ),
            tooltip: '挂单池 ($hangOrderCount)',
            onPressed: onOpenHangPool,
            visualDensity: VisualDensity.standard,
          ),
          // 主题切换
          IconButton(
            key: const Key('topbar-theme-toggle-btn'),
            icon: Icon(
              isDarkMode ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              size: 24,
            ),
            tooltip: isDarkMode ? '日间模式' : '夜间模式',
            onPressed: onToggleTheme,
            visualDensity: VisualDensity.standard,
          ),
          // 更多操作下拉菜单
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 24),
            tooltip: '更多操作',
            onSelected: (value) {
              if (value == 'fulfillment' && onOpenFulfillment != null) {
                onOpenFulfillment!();
              } else if (value == 'profile' && onOpenProfile != null) {
                onOpenProfile!();
              } else if (value == 'switch' && onSwitchAccount != null) {
                onSwitchAccount!();
              } else if (value == 'logout' && onLogout != null) {
                onLogout!();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: KeyedSubtree(
                  key: const Key('cashier-identity-capsule'),
                  child: Text(
                    '收银员: $cashierName ($cashierWorkNo)',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (onOpenFulfillment != null)
                PopupMenuItem(
                  value: 'fulfillment',
                  child: KeyedSubtree(
                    key: const Key('topbar-fulfillment-btn'),
                    child: Text(
                      '履约外卖 ($fulfillmentCount)',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              if (onSwitchAccount != null)
                const PopupMenuItem(
                  value: 'switch',
                  child: KeyedSubtree(
                    key: Key('topbar-shift-switch-btn'),
                    child: Text(
                      '换班交接',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              if (onLogout != null)
                const PopupMenuItem(
                  value: 'logout',
                  child: KeyedSubtree(
                    key: Key('topbar-logout-btn'),
                    child: Text(
                      '退出登录',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileBottomNav extends StatelessWidget {
  const _MobileBottomNav({
    required this.currentSection,
    required this.visibleSections,
    required this.onSectionChanged,
  });

  final CashierSection currentSection;
  final Set<CashierSection> visibleSections;
  final ValueChanged<CashierSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.cashier;
    final sections = CashierSection.values.where((s) => visibleSections.contains(s)).toList();

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            offset: const Offset(0, -2),
            blurRadius: 6,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final section in sections)
                Expanded(
                  child: InkWell(
                    key: Key('cashier-nav-${section.name}'),
                    onTap: () => onSectionChanged(section),
                    child: Semantics(
                      selected: currentSection == section,
                      button: true,
                      label: section.label,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            section.icon,
                            size: 26,
                            color: currentSection == section
                                ? tokens.ink
                                : tokens.inkSecondary,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            section.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: currentSection == section
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: currentSection == section
                                  ? tokens.ink
                                  : tokens.inkSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
