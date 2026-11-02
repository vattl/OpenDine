import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/receivable_charge_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testOrder = PosOrder(
    id: 1,
    orderNo: 'ORD202610180001',
    tableNumber: 'A08',
    diners: 4,
    total: 350.00,
    grossAmount: 350.00,
    createdAt: DateTime(2026, 10, 18, 12, 30),
    lines: const [],
  );

  final testAccounts = [
    const PosReceivableEligibleAccount(
      id: 101,
      scopeType: 'SHOP',
      customerType: 'COMPANY',
      customerName: '阿里巴巴本地生活',
      contactName: '王总',
      contactPhone: '13811112222',
      creditLimitFen: 100000,
      availableLimitFen: 80000, // 剩余800元，足以覆盖350元
      status: 'ACTIVE',
    ),
    const PosReceivableEligibleAccount(
      id: 102,
      scopeType: 'SHOP',
      customerType: 'PERSON',
      customerName: '小微商贸公司',
      contactName: '李经理',
      contactPhone: '13933334444',
      creditLimitFen: 50000,
      availableLimitFen: 10000, // 剩余100元，不足以覆盖350元
      status: 'ACTIVE',
    ),
  ];

  Widget buildDialog({
    required Future<PosReceivableClaim> Function({
      required int accountId,
      required String requestId,
      String? note,
    }) chargeReceivable,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReceivableChargeDialog(
          order: testOrder,
          tableNumber: 'A08',
          loadAccounts: () async => testAccounts,
          chargeReceivable: chargeReceivable,
        ),
      ),
    );
  }

  testWidgets('renders account list with credit status and handles selection', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      buildDialog(
        chargeReceivable: ({required accountId, required requestId, note}) async {
          return PosReceivableClaim(
            id: 888,
            claimNo: 'REC888',
            orderNo: testOrder.orderNo,
            shopId: 1,
            accountId: accountId,
            originalAmountFen: 35000,
            collectedAmountFen: 0,
            outstandingFen: 35000,
            status: 'OPEN',
            customerName: '阿里巴巴本地生活',
          );
        },
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify title and order details rendered
    expect(find.text('客户挂账结算'), findsOneWidget);
    expect(find.text('¥ 350.00'), findsOneWidget);
    expect(find.text('阿里巴巴本地生活'), findsOneWidget);
    expect(find.text('小微商贸公司'), findsOneWidget);

    // Verify insufficient credit tag for account 102
    expect(find.text('额度不足'), findsOneWidget);

    // Click account 101 (eligible)
    await tester.tap(find.text('阿里巴巴本地生活'));
    await tester.pump();

    // Verify submit button is enabled
    final submitButtonFinder = find.widgetWithText(ElevatedButton, '确认挂账结账 (清台出票)');
    expect(submitButtonFinder, findsOneWidget);
    final elevatedBtn = tester.widget<ElevatedButton>(submitButtonFinder);
    expect(elevatedBtn.onPressed, isNotNull);

    // Click submit
    await tester.tap(submitButtonFinder);
    await tester.pump();
  });
}
