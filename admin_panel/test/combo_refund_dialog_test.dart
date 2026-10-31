import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/refund_dish_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('combo header refund is locked to the full combo quantity', (
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

    RefundDishResult? result;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'NotoSansSC'),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  result = await showDialog<RefundDishResult>(
                    context: context,
                    builder: (_) => const RefundDishDialog(
                      line: PosOrderLine(
                        id: 92,
                        name: '双人午餐套餐',
                        quantity: 2,
                        total: 136,
                        unit: '份',
                        specification: '',
                        refunded: false,
                        lineType: 'combo_header',
                        comboId: 12,
                        comboInstanceId: 'combo-12-a',
                      ),
                    ),
                  );
                },
                child: const Text('打开退套餐'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开退套餐'));
    await tester.pumpAndSettle();

    expect(find.textContaining('套餐不可拆分退菜'), findsOneWidget);
    expect(find.textContaining('退套餐 · 双人午餐套餐'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('refund-quantity-input')))
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('refund-quantity-decrement')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const Key('refund-quantity-increment')),
          )
          .onPressed,
      isNull,
    );
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(
        '../design/prototypes/UI055-pos-combo-commercialization/_shots/production-refund.png',
      ),
    );

    await tester.tap(find.byKey(const Key('refund-dish-confirm')));
    await tester.pumpAndSettle();

    expect(result?.quantity, 2);
    expect(result?.stockAction, PosRefundStockAction.restore);
  });
}
