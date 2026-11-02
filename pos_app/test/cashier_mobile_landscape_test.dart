import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_components.dart';
import 'package:admin_panel_flutter/src/features/cashier_shell/presentation/cashier_shell.dart';
import 'package:admin_panel_flutter/src/features/mobile/responsive/breakpoints.dart';
import 'package:admin_panel_flutter/src/features/tables/data/table_repository.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:admin_panel_flutter/src/features/tables/presentation/table_overview_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTableRepository extends Fake implements TableRepository {
  _FakeTableRepository(this.overview);
  final TableOverview overview;

  @override
  Future<TableOverview> loadTableOverview() async => overview;

  Future<List<Map<String, dynamic>>> getAreas() async => [
        {'code': 'hall', 'name': '大厅'},
        {'code': 'box', 'name': '包厢'},
      ];
}

void main() {
  group('Cashier Mobile Landscape Adaptation Tests', () {
    testWidgets('responsive context identifies phone landscape correctly',
        (tester) async {
      // 常见手机横屏分辨率 (840 x 384 dp)
      tester.view.physicalSize = const Size(840, 384);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      late bool phoneLandscape;
      late bool compactHeight;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              phoneLandscape = context.isPhoneLandscape;
              compactHeight = context.isCompactHeight;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(phoneLandscape, isTrue);
      expect(compactHeight, isTrue);
    });

    testWidgets('CashierShell adapts to phone landscape (full screen sidebar & topbar)',
        (tester) async {
      tester.view.physicalSize = const Size(840, 384);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var themeToggled = false;
      var hangOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CashierShell(
              brandText: '老肥油边王',
              storeText: '松源店',
              currentSection: CashierSection.table,
              connected: true,
              kdsAvailable: true,
              hangOrderCount: 3,
              fulfillmentCount: 1,
              onToggleTheme: () => themeToggled = true,
              onOpenHangPool: () => hangOpened = true,
              onSectionChanged: (_) {},
              body: const Text('工作区内容'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证侧边栏存在且垂直满高展示，不触发 overflow
      expect(find.byKey(const Key('cashier-nav-table')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-ordering')), findsOneWidget);
      expect(find.byKey(const Key('cashier-nav-bills')), findsOneWidget);

      // 验证顶栏各功能键完整存在且点击顺畅
      expect(find.byKey(const Key('cashier-brand-store-name')), findsOneWidget);
      expect(find.byKey(const Key('topbar-theme-toggle-btn')), findsOneWidget);
      expect(find.byKey(const Key('topbar-hang-pool-btn')), findsOneWidget);

      await tester.tap(find.byKey(const Key('topbar-theme-toggle-btn')));
      expect(themeToggled, isTrue);

      await tester.tap(find.byKey(const Key('topbar-hang-pool-btn')));
      expect(hangOpened, isTrue);

      // 验证工作区
      expect(find.text('工作区内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TableOverviewPage fits full screen on phone landscape without 1280 scrollbar',
        (tester) async {
      tester.view.physicalSize = const Size(840, 384);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final tables = List.generate(
        12,
        (i) => DiningTable.fromJson({
          'number': '${i + 1}',
          'status': i % 3,
          'amount': i % 3 == 1 ? 99.0 : 0.0,
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TableOverviewPage(
              repository: _FakeTableRepository(
                TableOverview(tables: tables),
              ),
              showSidebar: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证桌台卡片满屏展现，零布局溢出
      expect(find.byKey(const Key('table-card-1')), findsOneWidget);
      expect(find.byKey(const Key('table-card-2')), findsOneWidget);

      // 验证底部状态栏存在
      expect(find.byKey(const Key('status-bar-create-table')), findsOneWidget);

      expect(tester.takeException(), isNull);
    });

    testWidgets('CashierDialogFrame fits inside compact phone landscape view without clipping',
        (tester) async {
      tester.view.physicalSize = const Size(840, 384);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: ctx,
                    builder: (_) => const CashierDialogFrame(
                      width: 600,
                      height: 500, // 设定大于 384 的高度
                      title: '测试弹窗',
                      body: Text('弹窗内容'),
                      actions: [
                        Text('取消'),
                        Text('确定'),
                      ],
                    ),
                  );
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();

      expect(find.text('测试弹窗'), findsOneWidget);
      expect(find.text('确定'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
