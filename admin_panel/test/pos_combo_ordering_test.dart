import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_ordering_view.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'combo commercial availability explains time, day, dining and order limits',
    () {
      final definition = PosComboDefinition.fromJsonOrNull({
        'comboId': 9,
        'dishId': 20,
        'status': 1,
        'limitPerOrder': 2,
        'availableDays': '1,2,3,4,5',
        'timeRangeStart': '11:00:00',
        'timeRangeEnd': '14:00:00',
        'applyDiningType': 'dine_in',
        'allowCoupon': 0,
      })!;

      expect(
        definition.unavailableReason(
          now: DateTime(2026, 10, 20, 10, 30),
          packingOrder: false,
        ),
        '11:00 开始售卖',
      );
      expect(
        definition.unavailableReason(
          now: DateTime(2026, 10, 20, 12),
          packingOrder: true,
        ),
        '仅限堂食',
      );
      expect(definition.orderLimitReached(2), isTrue);
      expect(definition.orderLimitReached(1), isFalse);
      expect(definition.allowCoupon, isFalse);
    },
  );

  test(
    'order lines retain combo instance relationships for grouped refund UI',
    () {
      final header = PosOrderLine.fromJson({
        'id': 100,
        'name': '午市双人餐',
        'quantity': '1',
        'total_price': 88,
        'line_type': 'combo_header',
        'combo_id': 11,
        'combo_instance_id': 'combo-a',
      });
      final component = PosOrderLine.fromJson({
        'id': 101,
        'name': '香辣鸡煲',
        'quantity': '1',
        'total_price': 0,
        'line_type': 'combo_component',
        'combo_id': 11,
        'combo_instance_id': 'combo-a',
        'parent_detail_id': 100,
      });

      expect(header.isComboHeader, isTrue);
      expect(component.isComboComponent, isTrue);
      expect(component.comboInstanceId, 'combo-a');
      expect(component.parentDetailId, 100);
    },
  );

  testWidgets('cashier selects combo components before submitting the order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    List<PosCartLine> submittedLines = const [];
    final combo = PosDish.fromJson({
      'id': 20,
      'name': '双人套餐',
      'typeId': 3,
      'unitprice': 58,
      'unit': '套',
      'comboDefinition': {
        'comboId': 9,
        'dishId': 20,
        'comboType': 'groups',
        'status': 1,
        'fixedItems': [
          {'componentDishId': 7, 'qtyPerCombo': 2},
        ],
        'groups': [
          {
            'groupKey': 'drink',
            'title': '选择饮品',
            'minPick': 1,
            'maxPick': 1,
            'items': [
              {'componentDishId': 8, 'extraPrice': 2},
              {'componentDishId': 9, 'extraPrice': 0},
            ],
          },
        ],
      },
    });
    final table = DiningTable.fromJson({'number': '40', 'status': 0});

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'NotoSansSC'),
        home: Scaffold(
          body: PosOrderingView(
            workspace: PosWorkspace(
              table: table,
              categories: const [
                PosCategory(id: 3, name: '套餐', code: 'combo', sorting: 1),
              ],
              dishes: [
                combo,
                PosDish.fromJson({
                  'id': 7,
                  'name': '油边王',
                  'typeId': 4,
                  'unitprice': 15,
                }),
                PosDish.fromJson({
                  'id': 8,
                  'name': '可乐',
                  'typeId': 4,
                  'unitprice': 5,
                }),
                PosDish.fromJson({
                  'id': 9,
                  'name': '雪碧',
                  'typeId': 4,
                  'unitprice': 5,
                }),
              ],
              currentOrder: null,
            ),
            tableNumber: '40',
            submitting: false,
            addingDishes: false,
            onBack: () {},
            onSubmit:
                ({required diners, required remark, required lines}) async {
                  submittedLines = lines;
                },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pos-dish-card-20')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('combo-dialog')), findsOneWidget);
    expect(find.text('套餐包含：油边王×2'), findsOneWidget);
    expect(find.text('可乐 +¥2.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('combo-option-drink-8')));
    await tester.tap(find.byKey(const Key('combo-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认下单'));
    await tester.pumpAndSettle();

    expect(submittedLines, hasLength(1));
    expect(submittedLines.single.comboSelections, {
      'drink': [8],
    });
    expect(submittedLines.single.total, 60);
    expect(submittedLines.single.requestBody()['combo_id'], 9);
  });

  testWidgets(
    'packing order disables dine-in-only combo with a visible reason',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final combo = PosDish.fromJson({
        'id': 21,
        'name': '堂食招牌餐',
        'typeId': 3,
        'unitprice': 58,
        'comboDefinition': {
          'comboId': 10,
          'dishId': 21,
          'status': 1,
          'applyDiningType': 'dine_in',
        },
      });

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'NotoSansSC'),
          home: Scaffold(
            body: PosOrderingView(
              workspace: PosWorkspace(
                table: DiningTable.fromJson({'number': '40', 'status': 0}),
                categories: const [],
                dishes: [combo],
                currentOrder: null,
              ),
              tableNumber: '40',
              submitting: false,
              addingDishes: false,
              packingOrder: true,
              onBack: () {},
              onSubmit:
                  ({required diners, required remark, required lines}) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('仅限堂食'), findsOneWidget);
      await tester.tap(find.byKey(const Key('pos-dish-card-21')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('combo-dialog')), findsNothing);
      expect(find.text('当前为打包订单，堂食招牌餐仅限堂食。'), findsOneWidget);
    },
  );

  testWidgets('combo order limit blocks opening a third selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final combo = PosDish.fromJson({
      'id': 22,
      'name': '午市双人餐',
      'typeId': 3,
      'unitprice': 88,
      'comboDefinition': {
        'comboId': 11,
        'dishId': 22,
        'status': 1,
        'limitPerOrder': 2,
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'NotoSansSC'),
        home: Scaffold(
          body: PosOrderingView(
            workspace: PosWorkspace(
              table: DiningTable.fromJson({'number': '40', 'status': 0}),
              categories: const [],
              dishes: [combo],
              currentOrder: null,
            ),
            tableNumber: '40',
            submitting: false,
            addingDishes: false,
            onBack: () {},
            onSubmit:
                ({required diners, required remark, required lines}) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('pos-dish-card-22')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('combo-confirm')));
      await tester.pumpAndSettle();
    }
    expect(find.text('已达本单限购上限 2 份'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pos-dish-card-22')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('combo-dialog')), findsNothing);
    expect(find.text('午市双人餐单单限购 2 份。'), findsOneWidget);
  });

  testWidgets('add-dish limit includes combo quantity already in the order', (
    tester,
  ) async {
    final fontLoader = FontLoader('NotoSansSC')
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-VF.ttf'));
    await fontLoader.load();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await iconLoader.load();
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final combo = PosDish.fromJson({
      'id': 23,
      'name': '晚市双人餐',
      'typeId': 3,
      'unitprice': 98,
      'comboDefinition': {
        'comboId': 12,
        'dishId': 23,
        'status': 1,
        'limitPerOrder': 2,
        'timeRangeStart': '00:00:00',
        'timeRangeEnd': '23:59:59',
        'allowCoupon': 0,
      },
    });
    final unavailableCombo = PosDish.fromJson({
      'id': 24,
      'name': '外带工作餐',
      'typeId': 3,
      'unitprice': 38,
      'comboDefinition': {
        'comboId': 13,
        'dishId': 24,
        'status': 1,
        'applyDiningType': 'take_out',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'NotoSansSC'),
        home: Scaffold(
          body: PosOrderingView(
            workspace: PosWorkspace(
              table: DiningTable.fromJson({'number': '40', 'status': 1}),
              categories: const [],
              dishes: [combo, unavailableCombo],
              currentOrder: const PosOrder(
                id: 1,
                orderNo: 'ORD-40',
                tableNumber: '40',
                diners: 2,
                total: 98,
                createdAt: null,
                lines: [
                  PosOrderLine(
                    id: 100,
                    name: '晚市双人餐',
                    quantity: 1,
                    total: 98,
                    specification: '',
                    refunded: false,
                    lineType: 'combo_header',
                    comboId: 12,
                    comboInstanceId: 'combo-12-existing',
                  ),
                ],
              ),
            ),
            tableNumber: '40',
            submitting: false,
            addingDishes: true,
            onBack: () {},
            onSubmit:
                ({required diners, required remark, required lines}) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('单单限2份'), findsOneWidget);
    expect(find.text('仅限打包'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pos-dish-card-23')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('combo-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('已达本单限购上限 2 份'), findsOneWidget);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../design/prototypes/UI055-pos-combo-commercialization/_shots/production-ordering.png',
      ),
    );

    await tester.tap(find.byKey(const Key('pos-dish-card-23')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('combo-dialog')), findsNothing);
    expect(find.text('晚市双人餐单单限购 2 份。'), findsOneWidget);
  });
}
