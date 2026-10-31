import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FulfillmentOrderLine 规格解析（外卖 selectedSpicy JSON）', () {
    test('JSON 对象 {"辣度":"微辣"} 提取值，无标点残留', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'unitprice': 28.5,
        'total_price': 28.5,
        'selectedSpicy': '{"辣度":"微辣"}',
      });
      expect(line.specification, '微辣');
    });

    test('JSON 多键 {"辣度":"微辣","温度":"热"} 提取全部值', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'selectedSpicy': '{"辣度":"微辣","温度":"热"}',
      });
      expect(line.specification, '微辣 / 热');
    });

    test('JSON 数组值 {"辣度":["微辣","不辣"]}', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'selectedSpicy': '{"辣度":["微辣","不辣"]}',
      });
      expect(line.specification, '微辣 / 不辣');
    });

    test('JSON 嵌套对象取 name 字段，跳过价格数字', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'selectedSpicy': '{"option":{"name":"中辣","price":2.0}}',
      });
      expect(line.specification, '中辣');
    });

    test('旧格式 辣度：微辣 保持兼容', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'selectedSpicy': '辣度：微辣',
      });
      expect(line.specification, '微辣');
    });

    test('普通文本规格保持原样', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'selectedSpicy': '大份,微辣',
      });
      expect(line.specification, '大份 / 微辣');
    });
  });

  group('FulfillmentOrderLine 出品状态（外卖无 KDS 字段时）', () {
    test('line_status=normal 不遮蔽 order_rece=rec_order', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'normal',
        'order_rece': 'rec_order',
      });
      expect(line.productionStatusLabel, '待制作');
    });

    test('order_rece=off_order 映射已出餐（修复状态为空）', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'normal',
        'order_rece': 'off_order',
      });
      expect(line.productionStatusLabel, '已出餐');
    });

    test('order_rece=mis_order 映射未制作', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'normal',
        'order_rece': 'mis_order',
      });
      expect(line.productionStatusLabel, '未制作');
    });

    test('line_status=refunded 识别为已退菜', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'refunded',
      });
      expect(line.isRefunded, isTrue);
      expect(line.productionStatusLabel, '已退菜');
    });

    test('order_rece=cancelled 识别为已退菜', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'normal',
        'order_rece': 'cancelled',
      });
      expect(line.isRefunded, isTrue);
      expect(line.productionStatusLabel, '已退菜');
    });

    test('order_receiving 兼容命名', () {
      final line = FulfillmentOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'normal',
        'order_receiving': 'off_order',
      });
      expect(line.productionStatusLabel, '已出餐');
    });
  });

  group('PosOrderLine 同步修复', () {
    test('JSON 规格无标点且过滤价格', () {
      final line = PosOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'total_price': 28.5,
        'selectedSpicy': '{"辣度":"微辣","价格":2}',
      });
      expect(line.specification, '微辣');
    });

    test('line_status=normal 不遮蔽 order_rece', () {
      final line = PosOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'normal',
        'order_rece': 'off_order',
      });
      expect(line.productionStatusLabel, '已出餐');
    });

    test('line_status=refunded 识别退菜', () {
      final line = PosOrderLine.fromJson({
        'name': '油边王',
        'quantity': 1,
        'line_status': 'refunded',
      });
      expect(line.refunded, isTrue);
    });
  });
}
