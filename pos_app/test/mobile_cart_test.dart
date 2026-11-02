import 'package:admin_panel_flutter/src/features/mobile/data/cart_state.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PosDish dish(int id, {double price = 10, bool available = true}) => PosDish(
        id: id,
        name: '菜$id',
        categoryId: 1,
        price: price,
        unit: '份',
        stock: null,
        onSale: available,
        soldOut: !available,
        specGroups: const [],
      );

  group('CartState', () {
    test('add accumulates quantity for same dish', () {
      var cart = const CartState();
      cart = cart.add(dish(1));
      cart = cart.add(dish(1));
      cart = cart.add(dish(2, price: 20));
      expect(cart.lines, hasLength(2));
      expect(cart.lines.first.quantity, 2);
      expect(cart.total, 40);
      expect(cart.totalQuantity, 3);
    });

    test('decrement removes line at zero', () {
      var cart = const CartState().add(dish(1));
      cart = cart.decrement(cart.lines.first);
      expect(cart.lines, isEmpty);
    });

    test('clear empties cart', () {
      var cart = const CartState().add(dish(1));
      expect(cart.clear().lines, isEmpty);
    });

    test('unavailable dish can still be modelled but UI gates add', () {
      final d = dish(1, available: false);
      expect(d.available, isFalse);
      expect(d.stockLabel, '已售罄');
    });
  });
}
