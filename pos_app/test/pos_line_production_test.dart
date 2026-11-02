import 'package:flutter_test/flutter_test.dart';
import '../lib/src/features/pos/domain/pos_models.dart';
import '../lib/src/features/tables/domain/dining_table.dart';

void main() {
  test('line production uses explicit item state ahead of acceptance', () {
    expect(PosOrderLine.fromJson({'order_rece': 'rec_order'}).productionStatusLabel, '待制作');
    expect(PosOrderLine.fromJson({'order_rece': 'mis_order'}).productionStatusLabel, '未制作');
    expect(PosOrderLine.fromJson({'item_status': 2, 'order_rece': 'rec_order'}).productionStatusLabel, '已出餐');
    expect(PosOrderLine.fromJson({'item_status': 0}).productionStatusLabel, '待制作');
    expect(PosOrderLine.fromJson({'item_status': 1}).productionStatusLabel, '制作中');
    expect(PosOrderLine.fromJson({'item_status': 3}).productionStatusLabel, '已退菜');
    expect(PosOrderLine.fromJson({'item_status': 3}).isRefunded, isTrue);
    expect(PosOrderLine.fromJson({}).productionStatusLabel, '未制作');
  });

  test('kds status text and code drive production label (v1.2.224)', () {
    expect(
      PosOrderLine.fromJson({'kds_status_text': '制作中', 'item_status': 0})
          .productionStatusLabel,
      '制作中',
    );
    expect(
      PosOrderLine.fromJson({'kds_status_text': '已完成', 'item_status': 0})
          .productionStatusLabel,
      '已出餐',
    );
    expect(
      PosOrderLine.fromJson({'kds_status_text': '已退菜'}).productionStatusLabel,
      '已退菜',
    );
    expect(
      PosOrderLine.fromJson({'kds_item_status': 1}).productionStatusLabel,
      '制作中',
    );
    expect(
      PosOrderLine.fromJson({'kds_item_status': 2}).productionStatusLabel,
      '已出餐',
    );
    expect(
      PosOrderLine.fromJson({'kds_item_status': 3}).productionStatusLabel,
      '已退菜',
    );
    expect(
      PosOrderLine.fromJson({'kds_status_text': '制作中', 'item_status': 2})
          .productionStatusLabel,
      '制作中',
    );
    expect(
      PosOrderLine.fromJson({'production_status': 'cooking'}).productionStatusLabel,
      '制作中',
    );
    expect(
      PosOrderLine.fromJson({'production_status': 'preparing'}).productionStatusLabel,
      '制作中',
    );
    expect(
      PosOrderLine.fromJson({
        'kds_item_status': 2,
        'kds_served_quantity': 1,
      }).kdsServedQuantity,
      1,
    );
    expect(PosOrderLine.fromJson({}).kdsServedQuantity, isNull);
  });

  test('partial served quantity displays progress dynamically', () {
    final partialLine = PosOrderLine.fromJson({
      'name': '烤羊肉串',
      'quantity': 10,
      'total_price': 50.0,
      'kds_item_status': 1,
      'kds_served_quantity': 4,
    });
    expect(partialLine.productionStatusLabel, '已出4/10');
    expect(partialLine.isPartiallyServed, isTrue);
    expect(partialLine.isInProgress, isTrue);
    expect(partialLine.isServed, isFalse);

    final completedLine = PosOrderLine.fromJson({
      'name': '烤羊肉串',
      'quantity': 10,
      'total_price': 50.0,
      'kds_item_status': 2,
      'kds_served_quantity': 10,
    });
    expect(completedLine.productionStatusLabel, '已出餐');
    expect(completedLine.isPartiallyServed, isFalse);
    expect(completedLine.isServed, isTrue);
  });

  test('FulfillmentOrderLine parses production status correctly', () {
    final cookingFulfillment = FulfillmentOrderLine.fromJson({
      'dish_name': '麻婆豆腐',
      'quantity': 2,
      'price': 28.0,
      'kds_item_status': 1,
    });
    expect(cookingFulfillment.productionStatusLabel, '制作中');
    expect(cookingFulfillment.isInProgress, isTrue);

    final refundedFulfillment = FulfillmentOrderLine.fromJson({
      'dish_name': '水煮牛肉',
      'quantity': 1,
      'price': 48.0,
      'kds_status_text': '已退菜',
    });
    expect(refundedFulfillment.productionStatusLabel, '已退菜');
    expect(refundedFulfillment.isRefunded, isTrue);

    final partialFulfillment = FulfillmentOrderLine.fromJson({
      'dish_name': '羊肉串',
      'quantity': 5,
      'price': 25.0,
      'kds_served_quantity': 2,
    });
    expect(partialFulfillment.productionStatusLabel, '已出2/5');
    expect(partialFulfillment.isPartiallyServed, isTrue);
  });
}
