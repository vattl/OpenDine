import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_components.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_shell.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashierShell', () {
    testWidgets('marks the current navigation section as selected', (
      tester,
    ) async {
      await _pumpShell(tester, currentSection: CashierSection.bills);

      final selected = tester.widget<Semantics>(
        find.byKey(const Key('cashier-nav-bills')),
      );
      final ordering = tester.widget<Semantics>(
        find.byKey(const Key('cashier-nav-ordering')),
      );

      expect(selected.properties.selected, isTrue);
      expect(ordering.properties.selected, isFalse);
    });

    testWidgets('sidebar navigation items are centered horizontally', (
      tester,
    ) async {
      await _pumpShell(tester, currentSection: CashierSection.ordering);

      final navItemFinder = find.byKey(const Key('cashier-nav-ordering'));
      expect(navItemFinder, findsOneWidget);

      final itemRect = tester.getRect(navItemFinder);
      // Sidebar width is 92.0; centered item with width 78.0 should have center.dx == 46.0
      expect(itemRect.center.dx, closeTo(46.0, 0.5));
      expect(itemRect.left, closeTo(7.0, 0.5));
    });

    testWidgets('notifies when a visible section is tapped', (tester) async {
      CashierSection? changedTo;
      await _pumpShell(
        tester,
        currentSection: CashierSection.ordering,
        onSectionChanged: (section) => changedTo = section,
      );

      await tester.tap(find.text('会员'));

      expect(changedTo, CashierSection.members);
    });

    testWidgets('does not build hidden navigation sections', (tester) async {
      await _pumpShell(
        tester,
        currentSection: CashierSection.ordering,
        visibleSections: const {
          CashierSection.ordering,
          CashierSection.bills,
          CashierSection.settings,
        },
      );

      expect(find.byKey(const Key('cashier-nav-ordering')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-bills')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-settings')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-members')), findsNothing);
      expect(find.byKey(const Key('cashier-nav-dishStatus')), findsNothing);
      expect(find.byKey(const Key('cashier-nav-shift')), findsNothing);
    });

    testWidgets('uses the provided logo asset and current shop as brand name', (
      tester,
    ) async {
      await _pumpShell(tester, currentSection: CashierSection.ordering);

      final avatarFinder = find.byKey(const Key('cashier-brand-avatar'));
      expect(avatarFinder, findsOneWidget);
      final avatar = tester.widget<Image>(avatarFinder);
      expect(
        (avatar.image as AssetImage).assetName,
        'assets/icons/pos/laofei_brand_avatar.png',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('cashier-brand-store-name')))
            .data,
        '松源海鲜街',
      );
    });

    testWidgets('collapse toggle narrows sidebar to icon rail and back', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var collapsed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) => CashierShell(
              currentSection: CashierSection.ordering,
              onSectionChanged: (_) {},
              connectionText: '已联网',
              storeText: '松源海鲜街',
              collapsed: collapsed,
              onToggleCollapse: () => setState(() => collapsed = !collapsed),
              body: const Center(child: Text('页面内容')),
            ),
          ),
        ),
      );

      // 展开：显示文字标签与收起入口
      expect(find.text('点餐'), findsOneWidget);
      expect(find.text('收起'), findsOneWidget);

      // 收起：仅图标窄栏，标签隐藏但导航项仍可点
      await tester.tap(find.byKey(const Key('cashier-sidebar-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('点餐'), findsNothing);
      expect(find.text('收起'), findsNothing);
      expect(find.byKey(const Key('cashier-nav-ordering')), findsOneWidget);

      // 再次切换恢复展开
      await tester.tap(find.byKey(const Key('cashier-sidebar-toggle')));
      await tester.pumpAndSettle();
      expect(find.text('点餐'), findsOneWidget);
    });

    testWidgets('renders table and manage navigation sections', (tester) async {
      CashierSection? tappedSection;
      await _pumpShell(
        tester,
        currentSection: CashierSection.table,
        onSectionChanged: (s) => tappedSection = s,
      );

      expect(find.byKey(const Key('cashier-nav-table')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-manage')), findsOneWidget);

      await tester.tap(find.byKey(const Key('cashier-nav-manage')));
      expect(tappedSection, CashierSection.manage);
    });

    test('CashierTokens monochrome palette matches UI061 specification', () {
      final dark = CashierTokens.dark;
      expect(dark.canvas, const Color(0xff09090b));
      expect(dark.surface, const Color(0xff121214));
      expect(dark.ink, const Color(0xffffffff));
      expect(dark.tableStateIdleBar, const Color(0xff27272a));
      expect(dark.tableStateDiningBar, const Color(0xff1e3a8a));
      expect(dark.tableStateSettlingBar, const Color(0xffb45309));
      expect(dark.tableStateCleaningBar, const Color(0xff166534));
      expect(dark.tableStateReservedBar, const Color(0xff581c87));

      final light = CashierTokens.light;
      expect(light.canvas, const Color(0xfff1f3f5));
      expect(light.surface, const Color(0xffffffff));
      expect(light.ink, const Color(0xff111827));
      expect(light.tableStateDiningBar, const Color(0xff2563eb));
    });

    testWidgets('renders 100% prototype replica topbar and sidebar elements', (
      tester,
    ) async {
      var toggledTheme = false;
      var openedHang = false;
      var openedFulfillment = false;
      var switchedAccount = false;

      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierShell(
            currentSection: CashierSection.table,
            onSectionChanged: (_) {},
            storeText: '老肥油边王 · 收银台 01',
            connectionText: '云端在线 (12ms)',
            connected: true,
            kdsAvailable: true,
            cashierName: '张晓峰',
            cashierWorkNo: '0801',
            hangOrderCount: 2,
            fulfillmentCount: 3,
            isDarkMode: true,
            onToggleTheme: () => toggledTheme = true,
            onOpenHangPool: () => openedHang = true,
            onOpenFulfillment: () => openedFulfillment = true,
            onSwitchAccount: () => switchedAccount = true,
            body: const Center(child: Text('主工作区')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证顶栏元素 (100% 对齐原型)
      expect(find.byKey(const Key('cashier-brand-avatar')), findsOneWidget);
      expect(find.text('老肥油边王 · 收银台 01'), findsOneWidget);
      expect(find.text('云端在线 (12ms)'), findsOneWidget);
      expect(find.text('后厨 KDS: 正常已连'), findsOneWidget);
      expect(find.byKey(const Key('topbar-theme-toggle-btn')), findsOneWidget);
      expect(find.byKey(const Key('topbar-hang-pool-btn')), findsOneWidget);
      expect(find.byKey(const Key('topbar-fulfillment-btn')), findsOneWidget);
      expect(find.byKey(const Key('cashier-identity-capsule')), findsOneWidget);
      expect(find.text('张晓峰'), findsOneWidget);
      expect(find.byKey(const Key('topbar-shift-switch-btn')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      // 验证顶栏交互
      await tester.tap(find.byKey(const Key('topbar-theme-toggle-btn')));
      expect(toggledTheme, isTrue);

      await tester.tap(find.byKey(const Key('topbar-hang-pool-btn')));
      expect(openedHang, isTrue);

      await tester.tap(find.byKey(const Key('topbar-fulfillment-btn')));
      expect(openedFulfillment, isTrue);

      await tester.tap(find.byKey(const Key('topbar-shift-switch-btn')));
      expect(switchedAccount, isTrue);

      // 验证左侧栏元素：72dp，头像移除，直接展示各一级模块
      expect(find.byKey(const Key('cashier-nav-table')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-ordering')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-bills')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-members')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-dishStatus')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-shift')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-manage')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-settings')), findsOneWidget);
    });

    testWidgets('adapts to compact mobile layout with bottom navigation', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      CashierSection? changedTo;
      await tester.pumpWidget(
        MaterialApp(
          home: CashierShell(
            currentSection: CashierSection.table,
            onSectionChanged: (section) => changedTo = section,
            visibleSections: const {
              CashierSection.table,
              CashierSection.ordering,
              CashierSection.bills,
              CashierSection.shift,
              CashierSection.settings,
            },
            storeText: '老肥家烧烤',
            body: const Text('手机端内容'),
          ),
        ),
      );

      // 验证底部导航栏渲染了指定入口
      expect(find.byKey(const Key('cashier-nav-table')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-ordering')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-bills')), findsOneWidget);

      // 点击切换
      await tester.tap(find.byKey(const Key('cashier-nav-ordering')));
      expect(changedTo, CashierSection.ordering);
    });
  });

  group('cashier shared components', () {
    testWidgets('renders distinct empty and error states', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: CashierStateView(
                    state: CashierViewState.empty,
                    title: '暂无账单',
                    message: '当前筛选条件下没有账单',
                  ),
                ),
                Expanded(
                  child: CashierStateView(
                    state: CashierViewState.error,
                    title: '加载失败',
                    message: '网络连接已断开',
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('暂无账单'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      expect(find.text('加载失败'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('formats amounts with grouping and two decimal places', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                CashierAmountText(amount: 1234.5),
                CashierAmountText(amount: -88, refund: true),
              ],
            ),
          ),
        ),
      );

      expect(find.text('¥ 1,234.50'), findsOneWidget);
      expect(find.text('−¥ 88.00'), findsOneWidget);
      expect(find.text('退款'), findsOneWidget);
    });

    testWidgets('topbar is pinned across full width at top above sidebar and body', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierShell(
            currentSection: CashierSection.table,
            onSectionChanged: (_) {},
            storeText: '老肥油边王 · 收银台 01',
            cashierName: '张晓峰',
            cashierWorkNo: '0801',
            body: const SizedBox(key: Key('shell-test-body')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final brandAvatarRect = tester.getRect(find.byKey(const Key('cashier-brand-avatar')));
      expect(brandAvatarRect.top, closeTo(17.0, 1.0));

      final navTableRect = tester.getRect(find.byKey(const Key('cashier-nav-table')));
      expect(navTableRect.top, greaterThanOrEqualTo(68.0));

      final bodyRect = tester.getRect(find.byKey(const Key('shell-test-body')));
      expect(bodyRect.top, greaterThanOrEqualTo(68.0));
    });

    testWidgets('supports showSidebar: false while permanently retaining pinned topbar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierShell(
            currentSection: CashierSection.table,
            showSidebar: false,
            bodyPadding: EdgeInsets.zero,
            onSectionChanged: (_) {},
            storeText: '老肥油边王 · 收银台 01',
            cashierName: '张晓峰',
            cashierWorkNo: '0801',
            body: const SizedBox.expand(key: Key('fullscreen-body')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cashier-brand-store-name')), findsOneWidget);
      expect(find.byKey(const Key('topbar-theme-toggle-btn')), findsOneWidget);
      expect(find.byKey(const Key('cashier-identity-capsule')), findsOneWidget);

      expect(find.byKey(const Key('cashier-nav-table')), findsNothing);

      final bodyRect = tester.getRect(find.byKey(const Key('fullscreen-body')));
      expect(bodyRect.left, 0.0);
      expect(bodyRect.right, 1920.0);
      expect(bodyRect.top, 68.0);
    });

    testWidgets('topbar functions use compact icon buttons with badges and tooltips to avoid overflowing status bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: CashierShell(
            currentSection: CashierSection.table,
            onSectionChanged: (_) {},
            storeText: '老肥油边王 · 收银台 01',
            connectionText: '云端在线 (12ms)',
            connected: true,
            kdsAvailable: true,
            cashierName: '张晓峰',
            cashierWorkNo: '0801',
            hangOrderCount: 5,
            fulfillmentCount: 8,
            isDarkMode: true,
            onToggleTheme: () {},
            onOpenHangPool: () {},
            onOpenFulfillment: () {},
            onSwitchAccount: () {},
            onLogout: () {},
            body: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证各功能均为紧凑图标按钮 (尺寸为 44x44)
      final themeBtnRect = tester.getRect(find.byKey(const Key('topbar-theme-toggle-btn')));
      expect(themeBtnRect.width, 44.0);
      expect(themeBtnRect.height, 44.0);

      final hangBtnRect = tester.getRect(find.byKey(const Key('topbar-hang-pool-btn')));
      expect(hangBtnRect.width, 44.0);
      expect(hangBtnRect.height, 44.0);

      final fulfillBtnRect = tester.getRect(find.byKey(const Key('topbar-fulfillment-btn')));
      expect(fulfillBtnRect.width, 44.0);
      expect(fulfillBtnRect.height, 44.0);

      final switchBtnRect = tester.getRect(find.byKey(const Key('topbar-shift-switch-btn')));
      expect(switchBtnRect.width, 44.0);
      expect(switchBtnRect.height, 44.0);

      final logoutBtnRect = tester.getRect(find.byKey(const Key('topbar-logout-btn')));
      expect(logoutBtnRect.width, 44.0);
      expect(logoutBtnRect.height, 44.0);

      // 验证未出现冗长的文字填充状态栏
      expect(find.text('☀️ 切换日间模式'), findsNothing);
      expect(find.text('📑 挂单池 (5)'), findsNothing);
      expect(find.text('🛵 履约外卖 (8)'), findsNothing);
      expect(find.text('换班'), findsNothing);

      // 验证角标显示数字
      expect(find.text('5'), findsOneWidget);
      expect(find.text('8'), findsOneWidget);
    });

    testWidgets('storeTitle replaces default storeText to avoid duplicate store header', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: CashierShell(
            currentSection: CashierSection.table,
            onSectionChanged: (_) {},
            storeText: '松源海鲜街',
            storeTitle: const Text('集成门店选择器', key: Key('custom-store-picker')),
            body: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('custom-store-picker')), findsOneWidget);
      expect(find.text('松源海鲜街'), findsNothing);
    });
  });
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required CashierSection currentSection,
  ValueChanged<CashierSection>? onSectionChanged,
  Set<CashierSection> visibleSections = CashierSection.valuesSet,
}) async {
  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: CashierShell(
        currentSection: currentSection,
        onSectionChanged: onSectionChanged ?? (_) {},
        visibleSections: visibleSections,
        connectionText: '已联网',
        storeText: '松源海鲜街',
        body: const Center(child: Text('页面内容')),
      ),
    ),
  );
}
