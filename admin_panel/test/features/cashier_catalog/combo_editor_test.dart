import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/data/cashier_catalog_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/domain/cashier_dish.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/domain/combo_definition_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/presentation/combo_editor_dialog.dart';

class _FakeCatalogRepository implements CashierCatalogRepository {
  ComboSaveRequest? lastSaveRequest;

  @override
  Future<List<CashierDishCategory>> loadCategories() async => [
    const CashierDishCategory(id: 1, name: '烧烤', code: 'bbq'),
    const CashierDishCategory(id: 2, name: '酒水', code: 'drinks'),
  ];

  @override
  Future<void> addCategory({
    required String name,
    required int sorting,
  }) async {}

  @override
  Future<void> deleteCategory(int id) async {}

  @override
  Future<void> deleteDish(int id) async {}

  @override
  Future<CashierDishPage> loadDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  }) async => const CashierDishPage(items: [], total: 0);

  @override
  Future<CashierDishPage> loadHqTemplateDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  }) async => const CashierDishPage(items: [], total: 0);

  @override
  Future<Map<String, Object?>> importDishesFromHq(List<int> dishIds) async =>
      const {};

  @override
  Future<void> updateOnSale({
    required CashierDish dish,
    required bool onSale,
  }) async {}

  @override
  Future<void> updateSoldOut({
    required CashierDish dish,
    required bool soldOut,
  }) async {}

  @override
  Future<void> saveDish(CashierDishInput input) async {}

  @override
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  }) async => '/image/dish/fake_uploaded.png';

  @override
  Future<ComboDetailResponse> getComboDetail(int dishId) async {
    return ComboDetailResponse(
      definition: ComboMenuDefinitionModel(
        dishId: dishId,
        comboType: 'groups',
        status: 1,
        limitPerOrder: 2,
        limitPerUser: 2,
        limitCycle: 'daily',
        startTime: '2026-10-20 00:00:00',
        endTime: '2026-12-31 23:59:59',
        availableDays: '1,2,3,4,5',
        timeRangeStart: '11:00:00',
        timeRangeEnd: '14:00:00',
        applyDiningType: 'dine_in',
        allowCoupon: false,
        dailyStock: 30,
        fixedItems: const [
          ComboFixedItemModel(
            componentDishId: 10,
            qtyPerCombo: 2,
            dishName: '招牌羊肉串',
            dishPrice: 5.0,
          ),
        ],
        groups: const [
          ComboGroupModel(
            groupKey: 'drinks',
            title: '特色饮品 1 选 1',
            minPick: 1,
            maxPick: 1,
            items: [
              ComboGroupItemModel(
                componentDishId: 20,
                extraPrice: 0.0,
                dishName: '酸梅汤',
                dishPrice: 10.0,
              ),
              ComboGroupItemModel(
                componentDishId: 21,
                extraPrice: 3.0,
                dishName: '原浆啤酒',
                dishPrice: 15.0,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Future<void> saveCombo(ComboSaveRequest request) async {
    lastSaveRequest = request;
  }
}

void main() {
  testWidgets('ComboEditorDialog loads definition and displays savings card', (
    tester,
  ) async {
    final fontLoader = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-VF.ttf'));
    await fontLoader.load();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconLoader.load();
    tester.view.physicalSize = const Size(1425, 990);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final repo = _FakeCatalogRepository();
    const headerDish = CashierDish(
      id: 99,
      name: '超值双人烧烤套餐',
      specification: '',
      price: 18.0,
      unit: '套',
      stock: 50,
      onSale: true,
      soldOut: false,
      typeId: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'NotoSansSC'),
        home: Scaffold(
          body: ComboEditorDialog(
            headerDish: headerDish,
            repository: repo,
            categories: const [
              CashierDishCategory(id: 1, name: '烧烤', code: 'bbq'),
              CashierDishCategory(id: 2, name: '酒水', code: 'drinks'),
            ],
            allDishes: const [
              CashierDish(
                id: 10,
                name: '招牌羊肉串',
                specification: '',
                price: 5.0,
                unit: '串',
                stock: 100,
                onSale: true,
                soldOut: false,
                typeId: 1,
              ),
              CashierDish(
                id: 20,
                name: '酸梅汤',
                specification: '',
                price: 10.0,
                unit: '杯',
                stock: 100,
                onSale: true,
                soldOut: false,
                typeId: 2,
              ),
              CashierDish(
                id: 21,
                name: '原浆啤酒',
                specification: '',
                price: 15.0,
                unit: '瓶',
                stock: 100,
                onSale: true,
                soldOut: false,
                typeId: 2,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify dialog loaded title & dish info
    expect(find.text('套餐可视化配置器'), findsOneWidget);
    expect(find.textContaining('超值双人烧烤套餐'), findsOneWidget);
    expect(find.text('招牌羊肉串'), findsOneWidget);
    expect(find.text('特色饮品 1 选 1'), findsOneWidget);

    // Verify savings calculation:
    // Fixed: 2 * 5.0 = 10.0
    // Groups: min is 10.0, max is 15.0 + 3.0 = 18.0
    // Total raw max: 10 + 18 = 28.0
    // Header price: 18.0
    // Max savings: 28.0 - 18.0 = 10.0
    expect(find.text('¥10.00'), findsWidgets);
    expect(find.text('预计为顾客最高省'), findsOneWidget);

    await tester.tap(find.text('售卖规则'));
    await tester.pumpAndSettle();
    expect(
      find.text('就餐方式与优惠券').hitTestable(),
      findsOneWidget,
      reason: '用餐方式与优惠券设置应在售卖规则首屏可见',
    );
    expect(
      find.byKey(const Key('combo-allow-coupon')).hitTestable(),
      findsOneWidget,
      reason: '优惠券叠加控件不应要求用户猜测需要向下滚动',
    );
    expect(find.text('限购与配额'), findsOneWidget);
    expect(find.byKey(const Key('combo-dining-type')), findsOneWidget);
    expect(find.byKey(const Key('combo-allow-coupon')), findsOneWidget);
    expect(find.byKey(const Key('combo-limit-per-order')), findsOneWidget);
    expect(find.text('仅堂食'), findsWidgets);
    expect(find.text('不参与优惠券'), findsOneWidget);
    expect(find.byKey(const Key('combo-commercial-summary')), findsOneWidget);
    expect(find.text('规则摘要'), findsOneWidget);
    final orderLimitField = find.descendant(
      of: find.byKey(const Key('combo-limit-per-order')),
      matching: find.byType(TextFormField),
    );
    await tester.enterText(orderLimitField, '3');
    await tester.pump();
    expect(find.textContaining('每单 3 份'), findsOneWidget);
    await tester.enterText(orderLimitField, '2');
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.drag(
      find
          .descendant(
            of: find.byKey(const Key('combo-commercial-rules')),
            matching: find.byType(Scrollable),
          )
          .first,
      const Offset(0, 2000),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../../../design/prototypes/UI055-pos-combo-commercialization/_shots/production-editor.png',
      ),
    );

    // Tap save button
    final saveButton = find.text('保存套餐配置');
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(repo.lastSaveRequest, isNotNull);
    expect(repo.lastSaveRequest!.dishId, 99);
    expect(repo.lastSaveRequest!.fixedItems.length, 1);
    expect(repo.lastSaveRequest!.groups.length, 1);
    expect(repo.lastSaveRequest!.limitPerOrder, 2);
    expect(repo.lastSaveRequest!.limitPerUser, 2);
    expect(repo.lastSaveRequest!.applyDiningType, 'dine_in');
    expect(repo.lastSaveRequest!.allowCoupon, isFalse);
    expect(repo.lastSaveRequest!.dailyStock, 30);
  });
}
