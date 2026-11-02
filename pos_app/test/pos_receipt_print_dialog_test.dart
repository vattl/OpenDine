import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_receipt_print_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const order = PosOrder(
    id: 9,
    orderNo: 'ORD40',
    tableNumber: '40',
    diners: 2,
    total: 60,
    createdAt: null,
    lines: [],
  );

  testWidgets('settled order disables pre-checkout and returns checkout type', (
    tester,
  ) async {
    PosReceiptPrintType? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              selected = await showPosReceiptPrintDialog(
                context,
                order: order,
                settled: true,
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    final preCheckout = tester.widget<InkWell>(
      find.byKey(const Key('receipt-print-option-preCheckout')),
    );
    final checkout = tester.widget<InkWell>(
      find.byKey(const Key('receipt-print-option-checkout')),
    );
    expect(preCheckout.onTap, isNull);
    expect(checkout.onTap, isNotNull);
    expect(find.text('订单已结账，无需再打印预结单'), findsOneWidget);

    await tester.tap(find.byKey(const Key('receipt-print-option-checkout')));
    await tester.tap(find.byKey(const Key('receipt-print-confirm')));
    await tester.pumpAndSettle();

    expect(selected, PosReceiptPrintType.checkout);
  });
}
