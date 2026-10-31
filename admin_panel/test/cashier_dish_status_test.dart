import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/data/cashier_catalog_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/data/real_cashier_catalog_repository.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/domain/cashier_dish.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/domain/combo_definition_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/presentation/cashier_dish_status_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('CashierDish', () {
    test('parses sale flags independently from stock', () {
      final dish = CashierDish.fromJson({
        'id': '7',
        'name': '油边王',
        'specification': '大份',
        'unitprice': '28.50',
        'unit': '份',
        'stock': 0,
        'onsale': 0,
        'sold_out': 1,
        'typeId': '3',
      });

      expect(dish.id, 7);
      expect(dish.price, 28.5);
      expect(dish.onSale, isFalse);
      expect(dish.soldOut, isTrue);
      expect(dish.stockLabel, '已下架');
      expect(dish.availability, CashierDishAvailability.soldOut);
    });

    test('null, zero and negative stock are unlimited when available', () {
      expect(_dish(stock: null).stockLabel, '不限量');
      expect(_dish(stock: 0).stockLabel, '不限量');
      expect(_dish(stock: -1).stockLabel, '不限量');
    });

    test('parses the same category variants used by the ordering page', () {
      final dish = CashierDish.fromJson({
        'id': 7,
        'name': '油边王',
        'unitprice': 28,
        'cid': 'signature',
        'type': {'id': 3, 'value': 'signature'},
      });
      final category = CashierDishCategory.fromJson({
        'id': 3,
        'label': '招牌菜',
        'cid': 'signature',
      });

      expect(dish.typeId, 3);
      expect(dish.categoryCode, 'signature');
      expect(dish.categoryName, 'signature');
      expect(category.matches(dish), isTrue);
    });

    test('parses categoryName and matches category by name even if ids differ', () {
      final dish = CashierDish.fromJson({
        'id': 18,
        'name': '烤鸡翅',
        'typeId': 99,
        'category_name': '特色烧烤',
      });
      final category = CashierDishCategory.fromJson({
        'id': 2,
        'name': '特色烧烤',
        'cid': 'bbq',
      });

      expect(dish.categoryName, '特色烧烤');
      expect(category.matches(dish), isTrue);
    });

    test('mergeCashierCategoriesWithDishes auto-discovers missing categories from dishes', () {
      final categories = [
        const CashierDishCategory(id: 1, name: '主食', code: 'main', sorting: 1),
      ];
      final dishes = [
        CashierDish.fromJson({
          'id': 101,
          'name': '米饭',
          'typeId': 1,
          'category_name': '主食',
        }),
        CashierDish.fromJson({
          'id': 102,
          'name': '烤羊肉串',
          'typeId': 2,
          'category_name': '特色烧烤',
        }),
      ];

      final merged = mergeCashierCategoriesWithDishes(
        categories: categories,
        dishes: dishes,
      );

      expect(merged.length, 2);
      expect(merged.any((c) => c.id == 1 && c.name == '主食'), isTrue);
      expect(merged.any((c) => c.id == 2 && c.name == '特色烧烤'), isTrue);
    });

    test('maps finite inventory to sufficient and low-stock states', () {
      expect(_dish(stock: 12).availability, CashierDishAvailability.sufficient);
      expect(_dish(stock: 5).availability, CashierDishAvailability.lowStock);
      expect(_dish(stock: 5).availabilityLabel, '快售罄');
    });

    test('changing sold-out state never changes on-sale state', () {
      final dish = _dish(stock: 5, onSale: false, soldOut: false);

      final changed = dish.copyWith(soldOut: true);

      expect(changed.onSale, isFalse);
      expect(changed.soldOut, isTrue);
    });

    test('parses and encodes specifications without exposing JSON editing', () {
      final groups = parseCashierDishSpecifications(
        '{"辣度":["不辣","微辣"],"份量":["小份","大份"]}',
      );

      expect(groups, hasLength(2));
      expect(groups.first.label, '辣度');
      expect(groups.first.options, ['不辣', '微辣']);
      expect(groups.last.label, '份量');
      expect(groups.last.options, ['小份', '大份']);
      expect(
        encodeCashierDishSpecifications(groups),
        '{"辣度":["不辣","微辣"],"份量":["小份","大份"]}',
      );
    });
  });

  test('real repository uses cashier catalog endpoint contracts', () async {
    final transport = FakeHttpTransport({
      'GET /admin/category/listAll': jsonEncode({
        'code': 200,
        'data': {
          'categoryList': [
            {'id': 3, 'name': '招牌菜', 'sorting': 2},
          ],
        },
      }),
      'POST /admin/dish/list': jsonEncode({
        'code': 200,
        'data': {
          'records': [
            {
              'id': 7,
              'name': '油边王',
              'unitprice': 28.5,
              'onsale': 1,
              'sold_out': 1,
              'typeId': 3,
            },
          ],
          'total': 21,
        },
      }),
      'POST /admin/dish/updateSaleStatus': jsonEncode({'code': 200}),
      'POST /admin/dish/updateOnSale': jsonEncode({'code': 200}),
      'POST /admin/dish/save': jsonEncode({'code': 200}),
      'POST /admin/category/add': jsonEncode({'code': 200}),
      'GET /admin/category/delete': jsonEncode({'code': 200}),
      'POST /admin/category/sort': jsonEncode({'code': 200}),
      'POST /admin/dish/sort': jsonEncode({'code': 200}),
    });
    final repository = RealCashierCatalogRepository(
      AdminApiClient(
        baseUrl: 'http://api.test',
        transport: transport,
        token: 'token',
        shopId: 9,
      ),
    );

    final categories = await repository.loadCategories();
    final page = await repository.loadDishes(
      pageNum: 2,
      pageSize: 20,
      query: ' 油边 ',
    );
    await repository.updateSoldOut(dish: page.items.single, soldOut: true);
    await repository.updateOnSale(dish: page.items.single, onSale: false);
    await repository.saveDish(page.items.single.toInput(nextStock: 8));
    await repository.addCategory(name: '烧烤', sorting: 3);
    await repository.deleteCategory(3);
    await repository.reorderCategory(id: 3, targetIndex: 8);
    await repository.reorderDish(id: 7, targetIndex: 12);

    expect(categories.single.name, '招牌菜');
    expect(page.total, 21);
    expect(jsonDecode(transport.requests[1].body!), {
      'pageNum': 2,
      'pageSize': 20,
      'query': '油边',
    });
    expect(jsonDecode(transport.requests[2].body!), {'id': 7, 'sold_out': 1});
    expect(transport.requests[2].headers['X-Shop-Id'], '9');
    expect(jsonDecode(transport.requests[3].body!), {'id': 7, 'onsale': false});
    final saveBody =
        jsonDecode(transport.requests[4].body!) as Map<String, Object?>;
    expect(saveBody['id'], 7);
    expect(saveBody['name'], '油边王');
    expect(saveBody['stock'], 8);
    expect(saveBody['sold_out'], 0);
    expect(saveBody['typeId'], 3);
    expect(transport.requests[4].headers['X-Shop-Id'], '9');
    expect(jsonDecode(transport.requests[5].body!), {
      'label': '烧烤',
      'sorting': 3,
    });
    expect(transport.requests[6].method, 'GET');
    expect(transport.requests[6].uri.path, '/admin/category/delete');
    expect(transport.requests[6].uri.queryParameters, {'id': '3'});
    expect(jsonDecode(transport.requests[7].body!), {
      'id': 3,
      'targetIndex': 8,
    });
    expect(jsonDecode(transport.requests[8].body!), {
      'id': 7,
      'targetIndex': 12,
    });
  });

  test(
    'loads every catalog page instead of stopping at the first 100',
    () async {
      final repository = _PagingCatalogRepository();

      final dishes = await repository.loadAllDishes(query: ' noodles ');

      expect(repository.requestedPages, [1, 2]);
      expect(repository.queries, ['noodles', 'noodles']);
      expect(dishes, hasLength(101));
      expect(dishes.last.id, 101);
    },
  );

  testWidgets('reloads server state after a sold-out update succeeds', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _RefreshingCatalogRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashier-dish-toggle-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 1);
    expect(repository.loadCalls, 2);
    // The server kept the dish available, so refreshed state wins over intent.
    expect(find.text('设为售罄'), findsOneWidget);
  });

  testWidgets('category cid filtering and inventory colors match POS rules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      _materialColor(tester, const Key('cashier-dish-card-1')),
      Colors.white,
    );
    expect(
      _materialColor(tester, const Key('cashier-dish-card-2')),
      Colors.white,
    );
    expect(
      _materialColor(tester, const Key('cashier-dish-card-3')),
      const Color(0xfff3f1f0),
    );

    await tester.tap(find.byKey(const Key('cashier-dish-category-id:3')));
    await tester.pump();

    expect(find.byKey(const Key('cashier-dish-card-1')), findsOneWidget);
    expect(find.byKey(const Key('cashier-dish-card-2')), findsNothing);
    expect(find.byKey(const Key('cashier-dish-card-3')), findsNothing);
  });

  testWidgets('inventory and add dish dialogs save validated values', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('cashier-dish-stock-1')), findsNothing);
    expect(find.byKey(const Key('cashier-dish-edit-1')), findsNothing);
    expect(find.text('辣度：不辣、微辣'), findsNothing);

    await tester.tap(find.byKey(const Key('cashier-dish-card-1')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(
        find.byKey(const Key('cashier-dish-serving-duration-input')),
      ).controller!.text,
      '10',
    );
    expect(find.byKey(const Key('cashier-dish-spec-input')), findsNothing);
    expect(
      find.byKey(const Key('cashier-dish-spec-group-label-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cashier-dish-spec-option-0-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('cashier-dish-spec-option-0-1')),
      findsOneWidget,
    );
    expect(find.text('{"辣度":["不辣","微辣"]}'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('cashier-dish-spec-option-0-1')),
      '中辣',
    );
    await tester.enterText(
      find.byKey(const Key('cashier-dish-editor-stock-input')),
      '9',
    );
    await tester.tap(find.byKey(const Key('cashier-dish-save-confirm')));
    await tester.pumpAndSettle();
    expect(repository.savedInputs.last.id, 1);
    expect(repository.savedInputs.last.stock, 9);
    expect(repository.savedInputs.last.servingDurationMinutes, 10);
    expect(repository.savedInputs.last.specification, '{"辣度":["不辣","中辣"]}');
    expect(find.byKey(const Key('pos-notice-dialog')), findsNothing);

    await tester.tap(find.text('增加菜品'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashier-dish-name-input')),
      '炭烤牛肉',
    );
    await tester.enterText(
      find.byKey(const Key('cashier-dish-price-input')),
      '26',
    );
    await tester.tap(find.byKey(const Key('cashier-dish-category-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('招牌菜').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashier-dish-serving-duration-input')),
      '15',
    );
    await tester.tap(find.byKey(const Key('cashier-dish-save-confirm')));
    await tester.pumpAndSettle();

    expect(repository.savedInputs.last.id, isNull);
    expect(repository.savedInputs.last.name, '炭烤牛肉');
    expect(repository.savedInputs.last.typeId, 3);
    expect(repository.savedInputs.last.price, 26);
    expect(repository.savedInputs.last.servingDurationMinutes, 15);
    expect(find.byKey(const Key('pos-notice-dialog')), findsNothing);

    await tester.tap(find.byKey(const Key('cashier-dish-card-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashier-dish-price-input')),
      '18',
    );
    await tester.tap(find.byKey(const Key('cashier-dish-save-confirm')));
    await tester.pumpAndSettle();

    expect(repository.savedInputs.last.id, 1);
    expect(repository.savedInputs.last.name, '油边王');
    expect(repository.savedInputs.last.price, 18);
  });

  testWidgets('dish editor deletes a dish after confirmation', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashier-dish-card-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cashier-dish-delete')));
    await tester.pumpAndSettle();

    // 删除前必须出现二次确认，且文案说明不可恢复
    expect(find.byKey(const Key('pos-notice-dialog')), findsOneWidget);
    expect(find.textContaining('无法恢复'), findsOneWidget);
    expect(repository.deletedDishIds, isEmpty);

    await tester.tap(find.text('确认删除'));
    await tester.pumpAndSettle();
    expect(repository.deletedDishIds, [1]);
  });

  testWidgets('dish delete can be cancelled at the confirmation step', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashier-dish-card-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cashier-dish-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(repository.deletedDishIds, isEmpty);
    expect(find.byKey(const Key('cashier-dish-card-1')), findsOneWidget);
  });

  testWidgets('category rail creates a category and reloads the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('cashier-dish-category-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashier-category-name-input')),
      '烧烤',
    );
    await tester.tap(find.byKey(const Key('cashier-category-save-confirm')));
    await tester.pumpAndSettle();

    expect(repository.addedCategories, ['烧烤']);
    // 初始加载已不请求分类接口（从菜品聚合），仅新建弹窗按需加载一次。
    expect(repository.categoryLoadCalls, 1);
  });

  testWidgets('long-press drag reorders categories and dishes', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    // 全部菜品视图：菜品拖拽被禁用（跨分类排序不合法），长按拖动不触发排序。
    final disabledGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cashier-dish-card-1'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await disabledGesture.moveTo(
      tester.getCenter(find.byKey(const Key('cashier-dish-card-2'))),
    );
    await tester.pump();
    await disabledGesture.up();
    await tester.pumpAndSettle();
    expect(repository.dishReorders, isEmpty);
    // 全部菜品视图不显示菜品拖拽手柄。
    expect(
      find.descendant(
        of: find.byKey(const Key('cashier-dish-card-1')),
        matching: find.byIcon(Icons.drag_indicator_rounded),
      ),
      findsNothing,
    );

    // 分类拖拽：拖「招牌菜」到「饮料」→ targetIndex = 饮料显示位置(2)。
    final categoryGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cashier-dish-category-id:3'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await categoryGesture.moveTo(
      tester.getCenter(find.byKey(const Key('cashier-dish-category-id:4'))),
    );
    await tester.pump();
    await categoryGesture.up();
    await tester.pumpAndSettle();

    expect(repository.categoryReorders, [(3, 2)]);
    // 分类排序后仅重拉菜品接口聚合，不读取分类接口。
    expect(repository.categoryLoadCalls, 0);
    expect(find.text('已保存分类排序'), findsOneWidget);

    // 选中「招牌菜」分类后：拖「油边王」到「烤生蚝」→ targetIndex = 分类内位置(2)。
    await tester.tap(find.byKey(const Key('cashier-dish-category-id:3')));
    await tester.pumpAndSettle();
    final dishGesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('cashier-dish-card-1'))),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await dishGesture.moveTo(
      tester.getCenter(find.byKey(const Key('cashier-dish-card-9'))),
    );
    await tester.pump();
    await dishGesture.up();
    await tester.pumpAndSettle();

    expect(repository.dishReorders, [(1, 2)]);
    expect(find.text('已保存菜品排序'), findsOneWidget);
  });

  testWidgets('category rail deletes an empty category after confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    // 初始加载不请求分类接口（从菜品聚合），空分类仅在新建设置时经分类接口出现。
    expect(repository.categoryLoadCalls, 0);
    await tester.tap(find.byKey(const Key('cashier-dish-category-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('cashier-category-name-input')),
      '烧烤',
    );
    await tester.tap(find.byKey(const Key('cashier-category-save-confirm')));
    await tester.pumpAndSettle();
    // 新建分类保存后按需加载完整分类列表，空分类随之出现。
    expect(repository.categoryLoadCalls, 1);
    expect(find.text('空分类'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cashier-dish-category-delete-5')));
    await tester.pumpAndSettle();
    expect(find.text('删除分类'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-notice-primary')));
    await tester.pumpAndSettle();

    expect(repository.deletedCategoryIds, [5]);
    expect(repository.categoryLoadCalls, 2);
    expect(find.text('空分类'), findsNothing);
  });

  testWidgets('initial load derives categories from dish type without category API', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    // 初始加载不请求分类接口：分类由菜品接口内嵌 type 聚合得出。
    expect(repository.categoryLoadCalls, 0);
    expect(find.byKey(const Key('cashier-dish-category-id:3')), findsOneWidget);
    expect(find.byKey(const Key('cashier-dish-category-id:4')), findsOneWidget);
    expect(find.text('招牌菜'), findsWidgets);
    expect(find.text('饮料'), findsWidgets);
  });

  testWidgets('restore sold-out dish asks for stock before saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    // dish3 初始售罄：点击恢复可售 -> 弹出数量设置（不直接保存）
    await tester.tap(find.byKey(const Key('cashier-dish-toggle-3')));
    await tester.pumpAndSettle();
    expect(find.textContaining('恢复为可售前'), findsOneWidget);
    expect(repository.savedInputs, isEmpty);

    await tester.enterText(
      find.byKey(const Key('cashier-dish-restock-input')),
      '30',
    );
    await tester.tap(find.byKey(const Key('cashier-dish-restock-confirm')));
    await tester.pumpAndSettle();

    expect(repository.savedInputs, hasLength(1));
    expect(repository.savedInputs.last.stock, 30);
    expect(repository.savedInputs.last.soldOut, isFalse);
  });

  testWidgets('HQ import button visibility depends on canManage permission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    // 1. canManage: false -> HQ import button is hidden
    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashier-dish-import-hq-button')), findsNothing);

    // 2. canManage: true -> HQ import button is visible
    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashier-dish-import-hq-button')), findsOneWidget);
  });

  testWidgets('HQ import dialog allows selecting template dishes and imports them', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    // Click import button
    await tester.tap(find.byKey(const Key('cashier-dish-import-hq-button')));
    await tester.pumpAndSettle();

    // Dialog should be displayed with HQ dishes
    expect(find.text('从总部导入菜品'), findsOneWidget);
    expect(find.byKey(const Key('cashier-hq-dish-item-101')), findsOneWidget);
    expect(find.byKey(const Key('cashier-hq-dish-item-102')), findsOneWidget);

    // Select dish 101
    await tester.tap(find.byKey(const Key('cashier-hq-dish-item-101')));
    await tester.pumpAndSettle();

    // Confirm button should show count (1)
    expect(find.text('确认导入 (1)'), findsOneWidget);

    // Click confirm
    await tester.tap(find.byKey(const Key('cashier-hq-import-confirm-button')));
    await tester.pumpAndSettle();

    // Dialog should close, and repository.importedDishIds contains 101
    expect(find.text('从总部导入菜品'), findsNothing);
    expect(repository.importedDishIds, contains(101));
  });

  testWidgets('Add combo button visibility depends on canManage permission', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    // 1. canManage: false -> add combo button is hidden
    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashier-dish-add-combo-button')), findsNothing);

    // 2. canManage: true -> add combo button is visible
    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cashier-dish-add-combo-button')), findsOneWidget);
  });

  testWidgets('Add combo button opens dialog with combo title and default unit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _CatalogUiRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: CashierDishStatusPage(repository: repository, canManage: true),
      ),
    );
    await tester.pumpAndSettle();

    // Tap add combo button
    await tester.tap(find.byKey(const Key('cashier-dish-add-combo-button')));
    await tester.pumpAndSettle();

    // Verify dialog title is '新增套餐'
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('新增套餐'),
      ),
      findsOneWidget,
    );

    // Verify default unit input contains '套'
    final unitInput = tester.widget<TextFormField>(
      find.byKey(const Key('cashier-dish-unit-input')),
    );
    expect(unitInput.controller?.text, '套');

    // Enter dish name and price
    await tester.enterText(
      find.byKey(const Key('cashier-dish-name-input')),
      '豪华双人烤肉套餐',
    );
    await tester.enterText(
      find.byKey(const Key('cashier-dish-price-input')),
      '128',
    );

    // Select category (id: 3 - 招牌菜)
    await tester.tap(find.byKey(const Key('cashier-dish-category-input')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('招牌菜').last);
    await tester.pumpAndSettle();

    // Tap confirm save
    await tester.tap(find.byKey(const Key('cashier-dish-save-confirm')));
    await tester.pumpAndSettle();

    // Verify dish was saved with unit '套' and name '豪华双人烤肉套餐'
    expect(repository.savedInputs, hasLength(1));
    final saved = repository.savedInputs.first;
    expect(saved.name, '豪华双人烤肉套餐');
    expect(saved.price, 128.0);
    expect(saved.unit, '套');
    expect(saved.typeId, 3);
  });
}

CashierDish _dish({
  required int? stock,
  bool onSale = true,
  bool soldOut = false,
}) => CashierDish(
  id: 1,
  name: '测试菜品',
  specification: '',
  price: 10,
  unit: '份',
  stock: stock,
  onSale: onSale,
  soldOut: soldOut,
  typeId: 1,
);

class _PagingCatalogRepository implements CashierCatalogRepository {
  final List<int> requestedPages = [];
  final List<String> queries = [];

  @override
  Future<List<CashierDishCategory>> loadCategories() async => const [];

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
  }) async {
    requestedPages.add(pageNum);
    queries.add(query);
    final firstId = (pageNum - 1) * pageSize + 1;
    final count = pageNum == 1 ? pageSize : 1;
    return CashierDishPage(
      items: [
        for (var offset = 0; offset < count; offset++)
          _dishWithId(firstId + offset),
      ],
      total: 101,
    );
  }

  @override
  Future<void> updateSoldOut({
    required CashierDish dish,
    required bool soldOut,
  }) async {}

  @override
  Future<void> saveDish(CashierDishInput input) async {}

  @override
  Future<void> updateOnSale({
    required CashierDish dish,
    required bool onSale,
  }) async {}

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
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  }) async => '/image/dish/fake.png';

  @override
  Future<ComboDetailResponse> getComboDetail(int dishId) async =>
      const ComboDetailResponse();

  @override
  Future<void> saveCombo(ComboSaveRequest request) async {}
}

class _RefreshingCatalogRepository implements CashierCatalogRepository {
  int loadCalls = 0;
  int updateCalls = 0;

  @override
  Future<List<CashierDishCategory>> loadCategories() async => const [];

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
  }) async {
    loadCalls++;
    return CashierDishPage(items: [_dishWithId(1)], total: 1);
  }

  @override
  Future<void> updateSoldOut({
    required CashierDish dish,
    required bool soldOut,
  }) async {
    updateCalls++;
  }

  @override
  Future<void> saveDish(CashierDishInput input) async {}

  @override
  Future<void> updateOnSale({
    required CashierDish dish,
    required bool onSale,
  }) async {}

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
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  }) async => '/image/dish/fake.png';

  @override
  Future<ComboDetailResponse> getComboDetail(int dishId) async =>
      const ComboDetailResponse();

  @override
  Future<void> saveCombo(ComboSaveRequest request) async {}
}

CashierDish _dishWithId(int id) => CashierDish(
  id: id,
  name: 'Dish $id',
  specification: '',
  price: 10,
  unit: 'item',
  stock: 5,
  onSale: true,
  soldOut: false,
  typeId: 1,
);

class _CatalogUiRepository
    implements CashierCatalogRepository, CashierCatalogSortingRepository {
  final List<CashierDishInput> savedInputs = [];
  final List<String> addedCategories = [];
  final List<int> deletedCategoryIds = [];
  final List<int> deletedDishIds = [];
  int categoryLoadCalls = 0;
  final List<(int, int)> categoryReorders = [];
  final List<(int, int)> dishReorders = [];
  final List<int> importedDishIds = [];

  @override
  Future<List<CashierDishCategory>> loadCategories() async {
    categoryLoadCalls++;
    return [
      const CashierDishCategory(
        id: 3,
        name: '招牌菜',
        code: 'signature',
        sorting: 10,
      ),
      const CashierDishCategory(id: 4, name: '饮料', code: 'drinks', sorting: 20),
      if (!deletedCategoryIds.contains(5))
        const CashierDishCategory(id: 5, name: '空分类', code: 'empty'),
    ];
  }

  @override
  Future<void> addCategory({required String name, required int sorting}) async {
    addedCategories.add(name);
  }

  @override
  Future<void> deleteCategory(int id) async {
    deletedCategoryIds.add(id);
  }

  @override
  Future<void> deleteDish(int id) async {
    deletedDishIds.add(id);
  }

  @override
  Future<CashierDishPage> loadDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  }) async {
    final items = [
      const CashierDish(
        id: 1,
        name: '油边王',
        specification: '{"辣度":["不辣","微辣"]}',
        price: 15,
        unit: '份',
        stock: 12,
        onSale: true,
        soldOut: false,
        typeId: 3,
        categoryCode: 'signature',
        categoryName: '招牌菜',
        sorting: 10,
      ),
      const CashierDish(
        id: 2,
        name: '可乐',
        specification: '',
        price: 5,
        unit: '瓶',
        stock: 3,
        onSale: true,
        soldOut: false,
        typeId: 4,
        categoryCode: 'drinks',
        categoryName: '饮料',
        sorting: 20,
      ),
      const CashierDish(
        id: 3,
        name: '雪花啤酒',
        specification: '',
        price: 8,
        unit: '瓶',
        stock: 0,
        onSale: true,
        soldOut: true,
        typeId: 4,
        categoryCode: 'drinks',
        categoryName: '饮料',
        sorting: 30,
      ),
      const CashierDish(
        id: 9,
        name: '烤生蚝',
        specification: '',
        price: 12,
        unit: '份',
        stock: 6,
        onSale: true,
        soldOut: false,
        typeId: 3,
        categoryCode: 'signature',
        categoryName: '招牌菜',
        sorting: 15,
      ),
    ];
    return CashierDishPage(items: items, total: items.length);
  }

  @override
  Future<void> saveDish(CashierDishInput input) async {
    savedInputs.add(input);
  }

  @override
  Future<void> updateSoldOut({
    required CashierDish dish,
    required bool soldOut,
  }) async {}

  @override
  Future<void> updateOnSale({
    required CashierDish dish,
    required bool onSale,
  }) async {}

  @override
  Future<void> reorderCategory({
    required int id,
    required int targetIndex,
  }) async {
    categoryReorders.add((id, targetIndex));
  }

  @override
  Future<void> reorderDish({
    required int id,
    required int targetIndex,
  }) async {
    dishReorders.add((id, targetIndex));
  }

  @override
  Future<CashierDishPage> loadHqTemplateDishes({
    required int pageNum,
    required int pageSize,
    required String query,
  }) async {
    final list = <CashierDish>[
      const CashierDish(
        id: 101,
        name: '总部招牌烤鸡',
        price: 38,
        specification: '',
        typeId: 0,
        unit: '份',
        stock: 99,
        onSale: true,
        soldOut: false,
      ),
      const CashierDish(
        id: 102,
        name: '总部柠檬红茶',
        price: 12,
        specification: '',
        typeId: 0,
        unit: '杯',
        stock: 99,
        onSale: true,
        soldOut: false,
      ),
    ];
    final filtered = query.isEmpty
        ? list
        : list.where((d) => d.name.contains(query)).toList();
    return CashierDishPage(items: filtered, total: filtered.length);
  }

  @override
  Future<Map<String, Object?>> importDishesFromHq(List<int> dishIds) async {
    importedDishIds.addAll(dishIds);
    return {'imported_count': dishIds.length, 'skipped_count': 0};
  }

  @override
  Future<String> uploadDishImage({
    required List<int> bytes,
    required String filename,
  }) async => '/image/dish/fake.png';

  @override
  Future<ComboDetailResponse> getComboDetail(int dishId) async =>
      const ComboDetailResponse();

  @override
  Future<void> saveCombo(ComboSaveRequest request) async {}
}

Color? _materialColor(WidgetTester tester, Key key) =>
    tester.widget<Material>(find.byKey(key)).color;
