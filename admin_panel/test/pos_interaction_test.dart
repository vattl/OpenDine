import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('POS category and inventory rules', () {
    test('dish parses the category id returned as cid', () {
      final dish = PosDish.fromJson({
        'id': 7,
        'name': '油边王',
        'cid': '3',
        'unitprice': 15,
        'stock': 12,
        'onsale': 1,
      });

      expect(dish.categoryId, 3);
    });

    test('dish preserves a non-numeric category cid for filtering', () {
      final dish = PosDish.fromJson({
        'id': 7,
        'name': '油边王',
        'cid': 'signature',
        'unitprice': 15,
      });

      expect(dish.categoryCode, 'signature');
      expect(dish.requestCategoryCode, 'signature');
    });

    test('dish reads category fields from the nested type object', () {
      final dish = PosDish.fromJson({
        'id': 7,
        'name': '油边王',
        'type': {'id': 3, 'label': '招牌菜品', 'cid': 'signature'},
        'unitprice': 15,
      });

      expect(dish.categoryId, 3);
      expect(dish.categoryCode, 'signature');
    });

    test('zero, null and negative stock mean unlimited inventory', () {
      PosDish dishWithStock(int? stock) => PosDish(
        id: 7,
        name: '油边王',
        categoryId: 3,
        price: 15,
        unit: '份',
        stock: stock,
        onSale: true,
        soldOut: false,
        specGroups: const [],
      );

      expect(dishWithStock(0).available, isTrue);
      expect(dishWithStock(0).stockLabel, '不限量');
      expect(const PosCart().remainingStock(dishWithStock(0)), isNull);
      expect(dishWithStock(null).available, isTrue);
      expect(dishWithStock(null).stockLabel, '不限量');
      expect(dishWithStock(-1).available, isTrue);
      expect(dishWithStock(-1).stockLabel, '不限量');

      const soldOut = PosDish(
        id: 8,
        name: '售罄菜品',
        categoryId: 3,
        price: 15,
        unit: '份',
        stock: 6,
        onSale: true,
        soldOut: true,
        specGroups: const [],
      );
      expect(soldOut.available, isFalse);
      expect(soldOut.stockLabel, '已售罄');
    });

    test('different specifications share one finite dish stock limit', () {
      const dish = PosDish(
        id: 7,
        name: '油边王',
        categoryId: 3,
        price: 15,
        unit: '份',
        stock: 2,
        onSale: true,
        soldOut: false,
        specGroups: [
          PosSpecGroup(label: '辣度', options: ['微辣', '不辣']),
        ],
      );

      final cart = const PosCart()
          .add(dish, selections: const {'辣度': '微辣'}, quantity: 2)
          .add(dish, selections: const {'辣度': '不辣'}, quantity: 1);

      expect(cart.quantityForDish(dish.id), 2);
      expect(cart.remainingStock(dish), 0);
      expect(cart.lines, hasLength(1));
    });

    test('combo definition and selections survive order serialization', () {
      final dish = PosDish.fromJson({
        'id': 20,
        'name': '双人套餐',
        'typeId': 3,
        'unitprice': 58,
        'unit': '套',
        'specification': '{"辣度":["微辣","不辣"]}',
        'comboDefinition': {
          'comboId': 9,
          'dishId': 20,
          'comboType': 'groups',
          'status': 1,
          'fixedItems': [
            {'componentDishId': 7, 'qtyPerCombo': 2, 'sortOrder': 1},
          ],
          'groups': [
            {
              'groupKey': 'drink',
              'title': '饮品',
              'minPick': 1,
              'maxPick': 1,
              'sortOrder': 1,
              'items': [
                {'componentDishId': 8, 'extraPrice': 2, 'sortOrder': 1},
                {'componentDishId': 9, 'extraPrice': 0, 'sortOrder': 2},
              ],
            },
          ],
        },
      });

      expect(dish.comboDefinition?.comboId, 9);
      expect(dish.comboDefinition?.fixedItems.single.dishId, 7);
      expect(dish.comboDefinition?.groups.single.options.first.dishId, 8);

      final cart = const PosCart().add(
        dish,
        comboSelections: const {
          'drink': [8],
        },
        selections: const {'辣度': '微辣'},
        quantity: 2,
      );
      final body = cart.lines.single.requestBody();

      expect(cart.lines.single.total, 120);
      expect(body['line_type'], 'combo');
      expect(body['combo_id'], 9);
      expect(body['combo_selections'], {
        'drink': [8],
      });
      expect(body['quantity'], '2');
      expect(body['total_price'], 120);
      expect(body['selectedSpicy'], '{"辣度":"微辣"}');
    });

    test('different combo choices remain separate cart lines', () {
      final dish = PosDish.fromJson({
        'id': 20,
        'name': '双人套餐',
        'typeId': 3,
        'unitprice': 58,
        'comboDefinition': {
          'comboId': 9,
          'dishId': 20,
          'comboType': 'groups',
          'status': 1,
          'groups': [
            {
              'groupKey': 'drink',
              'title': '饮品',
              'minPick': 1,
              'maxPick': 1,
              'items': [
                {'componentDishId': 8, 'extraPrice': 0},
                {'componentDishId': 9, 'extraPrice': 0},
              ],
            },
          ],
        },
      });

      final cart = const PosCart()
          .add(
            dish,
            comboSelections: const {
              'drink': [8],
            },
          )
          .add(
            dish,
            comboSelections: const {
              'drink': [9],
            },
          );

      expect(cart.lines, hasLength(2));
    });
  });
}
