import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/order_discount_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'preset discount supports wipe zero, common reason and custom note',
    (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      OrderDiscountResult? result;
      const order = PosOrder(
        id: 9,
        orderNo: 'ORD-DISCOUNT',
        tableNumber: '20',
        diners: 2,
        total: 185.7,
        grossAmount: 185.7,
        createdAt: null,
        lines: [],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                result = await showDialog<OrderDiscountResult>(
                  context: context,
                  builder: (_) => const OrderDiscountDialog(order: order),
                );
              },
              child: const Text('打开折扣'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开折扣'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('discount-dialog')), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsNothing);
      expect(find.text('95折'), findsOneWidget);
      expect(find.text('9折'), findsOneWidget);
      expect(find.text('88折'), findsOneWidget);
      expect(find.text('8折'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discount-preset-88')));
      await tester.tap(find.byKey(const Key('discount-wipe-zero')));
      await tester.tap(find.byKey(const Key('discount-reason-熟客')));
      await tester.enterText(
        find.byKey(const Key('discount-note-input')),
        '生日关怀',
      );
      await tester.pump();

      expect(find.text('¥163.00'), findsOneWidget);
      await tester.tap(find.byKey(const Key('discount-confirm')));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.discountAmount, 22.7);
      expect(result!.reason, contains('88折'));
      expect(result!.reason, contains('抹零'));
      expect(result!.reason, contains('熟客'));
      expect(result!.reason, contains('生日关怀'));
    },
  );

  testWidgets('fixed discount validates and submits an absolute amount', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    OrderDiscountResult? result;
    const order = PosOrder(
      id: 9,
      orderNo: 'ORD-FIXED',
      tableNumber: '20',
      diners: 2,
      total: 100,
      grossAmount: 100,
      createdAt: null,
      lines: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<OrderDiscountResult>(
                context: context,
                builder: (_) => const OrderDiscountDialog(order: order),
              );
            },
            child: const Text('打开折扣'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开折扣'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('discount-fixed-mode')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('discount-fixed-input')), '20');
    await tester.tap(find.byKey(const Key('discount-reason-活动')));
    await tester.pump();

    expect(find.text('¥80.00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('discount-confirm')));
    await tester.pumpAndSettle();

    expect(result?.discountAmount, 20);
    expect(result?.reason, contains('固定优惠'));
    expect(result?.reason, contains('活动'));
  });
}
