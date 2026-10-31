import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/domain/cashier_dish.dart';
import 'package:admin_panel_flutter/src/features/cashier_catalog/domain/combo_definition_models.dart';

void main() {
  group('Combo Definition Models Test Suite', () {
    test('ComboFixedItemModel parses camelCase and snake_case correctly', () {
      final jsonCamel = {
        'componentDishId': 101,
        'qtyPerCombo': 3,
        'sortOrder': 1,
        'dishName': '羊肉串',
        'dishPrice': 3.5,
      };
      final item1 = ComboFixedItemModel.fromJson(jsonCamel);
      expect(item1.componentDishId, 101);
      expect(item1.qtyPerCombo, 3);
      expect(item1.sortOrder, 1);
      expect(item1.dishName, '羊肉串');
      expect(item1.dishPrice, 3.5);

      final jsonSnake = {
        'component_dish_id': 102,
        'qty_per_combo': 2,
        'sort_order': 0,
        'unitprice': 28.0,
      };
      final item2 = ComboFixedItemModel.fromJson(jsonSnake);
      expect(item2.componentDishId, 102);
      expect(item2.qtyPerCombo, 2);
      expect(item2.sortOrder, 0);
      expect(item2.dishPrice, 28.0);
    });

    test('ComboFixedItemModel attachDishInfo updates details', () {
      const item = ComboFixedItemModel(componentDishId: 101);
      const dish = CashierDish(
        id: 101,
        name: '生蚝',
        specification: '',
        price: 48.0,
        unit: '份',
        stock: 20,
        soldOut: false,
        image: '/image/dish/oyster.png',
        typeId: 2,
        onSale: true,
      );
      final attached = item.attachDishInfo(dish);
      expect(attached.dishName, '生蚝');
      expect(attached.dishPrice, 48.0);
      expect(attached.dishImage, '/image/dish/oyster.png');
    });

    test('ComboGroupModel and ComboGroupItemModel work together', () {
      final groupJson = {
        'groupKey': 'drinks',
        'title': '饮品 2 选 1',
        'minPick': 1,
        'maxPick': 1,
        'sortOrder': 0,
        'items': [
          {
            'componentDishId': 201,
            'extraPrice': 0.0,
            'sortOrder': 0,
            'dishName': '可乐',
            'dishPrice': 6.0,
          },
          {
            'component_dish_id': 202,
            'extra_price': 4.0,
            'sort_order': 1,
            'dishName': '精酿啤酒',
            'dishPrice': 18.0,
          },
        ],
      };

      final group = ComboGroupModel.fromJson(groupJson);
      expect(group.groupKey, 'drinks');
      expect(group.title, '饮品 2 选 1');
      expect(group.minPick, 1);
      expect(group.maxPick, 1);
      expect(group.items.length, 2);
      expect(group.items[0].componentDishId, 201);
      expect(group.items[0].extraPrice, 0.0);
      expect(group.items[1].componentDishId, 202);
      expect(group.items[1].extraPrice, 4.0);

      final serialized = group.toJson();
      expect(serialized['groupKey'], 'drinks');
      expect(serialized['title'], '饮品 2 选 1');
      expect((serialized['items'] as List).length, 2);
    });

    test('ComboSaveRequest serializes correctly for fixed vs groups', () {
      const reqGroups = ComboSaveRequest(
        dishId: 50,
        comboType: 'groups',
        status: 1,
        fixedItems: [ComboFixedItemModel(componentDishId: 101, qtyPerCombo: 2)],
        groups: [
          ComboGroupModel(
            groupKey: 'g1',
            title: '主食',
            minPick: 1,
            maxPick: 1,
            items: [ComboGroupItemModel(componentDishId: 301)],
          ),
        ],
      );

      final jsonGroups = reqGroups.toJson();
      expect(jsonGroups['dishId'], 50);
      expect(jsonGroups['comboType'], 'groups');
      expect((jsonGroups['fixedItems'] as List).length, 1);
      expect((jsonGroups['groups'] as List).length, 1);

      const reqFixed = ComboSaveRequest(
        dishId: 50,
        comboType: 'fixed',
        status: 1,
        fixedItems: [ComboFixedItemModel(componentDishId: 101, qtyPerCombo: 2)],
        groups: [
          ComboGroupModel(
            groupKey: 'g1',
            title: '主食',
            items: [ComboGroupItemModel(componentDishId: 301)],
          ),
        ],
      );

      final jsonFixed = reqFixed.toJson();
      expect(jsonFixed['comboType'], 'fixed');
      // For fixed combo, groups are cleared
      expect((jsonFixed['groups'] as List).length, 0);
    });

    test('ComboDetailResponse parses nested definition properly', () {
      final responseMap = {
        'combo': {'id': 1, 'dish_id': 99, 'combo_type': 'groups', 'status': 1},
        'definition': {
          'comboId': 1,
          'dishId': 99,
          'comboType': 'groups',
          'status': 1,
          'fixedItems': [
            {'componentDishId': 10, 'qtyPerCombo': 1, 'sortOrder': 0},
          ],
          'groups': [
            {
              'groupKey': 'dessert',
              'title': '甜品',
              'minPick': 1,
              'maxPick': 1,
              'sortOrder': 0,
              'items': [
                {'componentDishId': 20, 'extraPrice': 0.0, 'sortOrder': 0},
              ],
            },
          ],
        },
        'forAdmin': true,
      };

      final detail = ComboDetailResponse.fromJson(
        responseMap,
        fallbackDishId: 99,
      );
      expect(detail.forAdmin, true);
      expect(detail.definition, isNotNull);
      expect(detail.definition!.dishId, 99);
      expect(detail.definition!.fixedItems.length, 1);
      expect(detail.definition!.fixedItems.first.componentDishId, 10);
      expect(detail.definition!.groups.length, 1);
      expect(detail.definition!.groups.first.groupKey, 'dessert');
    });

    test(
      'commercial fields parse snake case and serialize through save request',
      () {
        final definition = ComboMenuDefinitionModel.fromJson({
          'combo_id': 9,
          'dish_id': 50,
          'limit_per_order': 2,
          'limit_per_user': 3,
          'limit_cycle': 'daily',
          'start_time': '2026-10-20 00:00:00',
          'end_time': '2026-12-31 23:59:59',
          'available_days': '1,2,3,4,5',
          'time_range_start': '11:00:00',
          'time_range_end': '14:00:00',
          'apply_dining_type': 'dine_in',
          'allow_coupon': 0,
          'daily_stock': 30,
        });

        expect(definition.limitPerOrder, 2);
        expect(definition.limitPerUser, 3);
        expect(definition.limitCycle, 'daily');
        expect(definition.availableDays, '1,2,3,4,5');
        expect(definition.applyDiningType, 'dine_in');
        expect(definition.allowCoupon, isFalse);
        expect(definition.dailyStock, 30);

        final payload = ComboSaveRequest(
          dishId: definition.dishId,
          limitPerOrder: definition.limitPerOrder,
          limitPerUser: definition.limitPerUser,
          limitCycle: definition.limitCycle,
          startTime: definition.startTime,
          endTime: definition.endTime,
          availableDays: definition.availableDays,
          timeRangeStart: definition.timeRangeStart,
          timeRangeEnd: definition.timeRangeEnd,
          applyDiningType: definition.applyDiningType,
          allowCoupon: definition.allowCoupon,
          dailyStock: definition.dailyStock,
        ).toJson();

        expect(payload['limitPerOrder'], 2);
        expect(payload['limitPerUser'], 3);
        expect(payload['limitCycle'], 'daily');
        expect(payload['applyDiningType'], 'dine_in');
        expect(payload['allowCoupon'], 0);
        expect(payload['dailyStock'], 30);
      },
    );
  });
}
