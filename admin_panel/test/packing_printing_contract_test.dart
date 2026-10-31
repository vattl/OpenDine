import 'package:admin_panel_flutter/src/features/cashier_settings/domain/cashier_settings.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/printing_template_models.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('printing template metadata parses backend packing scenario', () {
    final meta = PrintingTemplateMeta.fromJson({
      'scenarios': [
        {
          'code': 'PACKING',
          'name': '打包单',
          'description': '打包/到店自提订单的独立核餐凭条',
          'paperSizes': ['58mm', '80mm'],
          'allowedBlocks': ['HEADER', 'ORDER_INFO', 'DISH_ITEMS', 'REMARK'],
        },
      ],
      'parametersByScenario': {
        'PACKING': [
          {'name': 'pickupCode', 'tag': '{取餐码}', 'description': '取餐码'},
        ],
      },
    });

    final packing = meta.scenarios.single;
    expect(packing.code, 'PACKING');
    expect(packing.ruleCode, 'packing');
    expect(packing.paperSizes, ['58mm', '80mm']);
    expect(meta.parametersFor('packing').single.tag, '{取餐码}');
  });

  test('packing is a first-class configurable printing scenario', () {
    final packingType = CashierPrinterTicketType.all.singleWhere(
      (item) => item.code == 'PACKING',
    );

    expect(packingType.label, '打包单');
    expect(
      ReceiptTemplateScenario.fromCode('PACKING'),
      ReceiptTemplateScenario.packing,
    );
  });

  test(
    'packing fallback template emphasizes pickup without payment summary',
    () {
      final text = PrintTemplateDsl.defaultTextTemplateForScenario('PACKING');
      final dsl = PrintTemplateDsl.defaultForScenario('PACKING');

      expect(text, contains('{取餐码}'));
      expect(dsl.blocks.any((block) => block.type == 'DISH_ITEMS'), isTrue);
      expect(
        dsl.blocks.any((block) => block.type == 'PAYMENT_SUMMARY'),
        isFalse,
      );
    },
  );
}
