import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../pos/domain/pos_models.dart';
import '../../tables/domain/dining_table.dart';
import 'api_providers.dart';

final posWorkspaceProvider = FutureProvider.autoDispose
    .family<PosWorkspace, DiningTable>(
  (ref, table) => ref.watch(posRepositoryProvider).loadWorkspace(table),
);

class CartState {
  const CartState({this.lines = const []});

  final List<PosCartLine> lines;

  double get total => lines.fold(0, (sum, line) => sum + line.total);

  int get totalQuantity => lines.fold(0, (sum, line) => sum + line.quantity);

  CartState add(
    PosDish dish, {
    Map<String, String> selections = const {},
    int quantity = 1,
  }) {
    final key = '${dish.id}|${jsonEncode(selections)}';
    final index = lines.indexWhere((l) => _lineKey(l) == key);
    final requested = quantity.clamp(1, 99);
    if (index >= 0) {
      final updated = [...lines];
      updated[index] = updated[index].copyWith(
        quantity: (updated[index].quantity + requested).clamp(1, 99),
      );
      return CartState(lines: updated);
    }
    return CartState(
      lines: [
        ...lines,
        PosCartLine(
          dish: dish,
          selections: selections,
          quantity: requested,
        ),
      ],
    );
  }

  CartState decrement(PosCartLine line) {
    final index = lines.indexWhere((l) => _lineKey(l) == _lineKey(line));
    if (index < 0) return this;
    final updated = [...lines];
    if (updated[index].quantity <= 1) {
      updated.removeAt(index);
    } else {
      updated[index] = updated[index].copyWith(quantity: updated[index].quantity - 1);
    }
    return CartState(lines: updated);
  }

  CartState clear() => const CartState();

  String _lineKey(PosCartLine line) =>
      '${line.dish.id}|${jsonEncode(line.selections)}';
}

final cartProvider = NotifierProvider<CartNotifier, CartState>(
  CartNotifier.new,
);

class CartNotifier extends Notifier<CartState> {
  @override
  CartState build() => const CartState();

  void add(
    PosDish dish, {
    Map<String, String> selections = const {},
    int quantity = 1,
  }) {
    state = state.add(dish, selections: selections, quantity: quantity);
  }

  void decrement(PosCartLine line) {
    state = state.decrement(line);
  }

  void clear() {
    state = state.clear();
  }
}
