import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/occupied_table_view.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';

void main() {
  group('OccupiedTableView 3-Column Layout Tests (WI-044)', () {
    const defaultOrder = PosOrder(
      id: 101,
      orderNo: 'ORD-20261016-001',
      tableNumber: '08',
      diners: 4,
      total: 188.0,
      grossAmount: 200.0,
      discountAmount: 12.0,
      wipeZeroAmount: 0.0,
      createdAt: null,
      lines: [
        PosOrderLine(
          id: 1,
          name: '招牌烤牛肉串',
          quantity: 20,
          total: 100.0,
          specification: '微辣',
          refunded: false,
        ),
        PosOrderLine(
          id: 2,
          name: '精酿啤酒',
          quantity: 4,
          total: 100.0,
          specification: '大杯',
          refunded: false,
        ),
      ],
    );

    const defaultWorkspace = PosWorkspace(
      table: DiningTable(number: '08', status: TableStatus.pending, people: 4),
      currentOrder: defaultOrder,
      categories: [],
      dishes: [],
      paymentMethods: [
        PosPaymentMethod(id: 1, code: 'cash', name: '现金支付', sortOrder: 1, enabled: true),
        PosPaymentMethod(id: 2, code: 'wechat', name: '微信支付', sortOrder: 2, enabled: true),
        PosPaymentMethod(id: 3, code: 'alipay', name: '支付宝', sortOrder: 3, enabled: true),
      ],
    );

    testWidgets('Renders 3-column layout with left, middle, and right columns', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OccupiedTableView(
              workspace: defaultWorkspace,
              busy: false,
              isDrawerOpen: true,
              paymentMethods: defaultWorkspace.paymentMethods,
              onBack: () {},
              onAddDishes: ([_]) {},
              onMerge: () {},
              onTransfer: ([_]) {},
              onClear: () {},
              onRefund: (_) {},
              onGift: (_) {},
              onDiscount: ([_]) {},
              onPrintReceipt: (_, [_]) {},
              onCheckout: (_) {},
              onBalanceCheckout: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify left column exists and has width 420
      final leftColumnFinder = find.byKey(const Key('occupied-left-column'));
      expect(leftColumnFinder, findsOneWidget);
      expect(tester.getSize(leftColumnFinder).width, equals(420.0));

      // Verify middle column (order lines) exists
      final orderLinesFinder = find.byKey(const Key('occupied-order-lines'));
      expect(orderLinesFinder, findsOneWidget);

      // Verify right column exists and has width 360
      final rightColumnFinder = find.byKey(const Key('occupied-right-column'));
      expect(rightColumnFinder, findsOneWidget);
      expect(tester.getSize(rightColumnFinder).width, equals(360.0));

      // Verify right column contains both amount bar and payment bar
      expect(find.descendant(of: rightColumnFinder, matching: find.byKey(const Key('occupied-amount-bar'))), findsOneWidget);
      expect(find.descendant(of: rightColumnFinder, matching: find.byKey(const Key('occupied-payment-bar'))), findsOneWidget);

      // Verify amount bar values
      expect(find.text('原价合计'), findsOneWidget);
      expect(find.text('¥200.00'), findsOneWidget);
      expect(find.text('优惠金额'), findsOneWidget);
      expect(find.text('-¥12.00'), findsOneWidget);
      expect(find.text('实收金额'), findsWidgets);
      expect(find.text('￥188.00'), findsOneWidget);

      // Verify payment cards exist in right column
      expect(find.byKey(const Key('pay-card-cash')), findsOneWidget);
      expect(find.byKey(const Key('pay-card-wechat')), findsOneWidget);
      expect(find.byKey(const Key('pay-card-alipay')), findsOneWidget);
    });

    testWidgets('Tapping payment card invokes onCheckout callback with payment code', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      String? selectedMethod;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OccupiedTableView(
              workspace: defaultWorkspace,
              busy: false,
              isDrawerOpen: true,
              paymentMethods: defaultWorkspace.paymentMethods,
              onBack: () {},
              onAddDishes: ([_]) {},
              onMerge: () {},
              onTransfer: ([_]) {},
              onClear: () {},
              onRefund: (_) {},
              onGift: (_) {},
              onDiscount: ([_]) {},
              onPrintReceipt: (_, [_]) {},
              onCheckout: (method) => selectedMethod = method,
              onBalanceCheckout: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pay-card-wechat')));
      await tester.pumpAndSettle();

      expect(selectedMethod, equals('wechat'));
    });

    testWidgets('Renders cash unopened badge in right column when drawer is closed', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OccupiedTableView(
              workspace: defaultWorkspace,
              busy: false,
              isDrawerOpen: false,
              paymentMethods: defaultWorkspace.paymentMethods,
              onBack: () {},
              onAddDishes: ([_]) {},
              onMerge: () {},
              onTransfer: ([_]) {},
              onClear: () {},
              onRefund: (_) {},
              onGift: (_) {},
              onDiscount: ([_]) {},
              onPrintReceipt: (_, [_]) {},
              onCheckout: (_) {},
              onBalanceCheckout: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未开班'), findsOneWidget);
    });
  });
}
