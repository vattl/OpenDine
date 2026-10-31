import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/occupied_table_view.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('Cashier Force Checkout Tests', () {
    test('checkout sends force: true and approvalToken in request body', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/checkout': jsonEncode({
          'code': 0,
          'order_no': 'ORD_FORCE_001',
          'status': 'success',
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 1,
        ),
      );

      await repository.checkout(
        orderNo: 'ORD_FORCE_001',
        paymentMethod: 'cash',
        force: true,
        approvalToken: 'app-token-12345',
      );

      expect(transport.requests, hasLength(1));
      final request = transport.requests.first;
      expect(request.method, 'POST');
      expect(request.uri.path, '/cashier/order/checkout');
      final body = jsonDecode(request.body!) as Map<String, dynamic>;
      expect(body['order_no'], 'ORD_FORCE_001');
      expect(body['payment_method'], 'cash');
      expect(body['force'], isTrue);
      expect(body['approvalToken'], 'app-token-12345');
    });

    test('checkoutTable sends force: true and approvalToken in request body', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/table/checkout': jsonEncode({
          'code': 0,
          'tableNumber': 'A08',
          'settledOrders': 2,
          'totalAmount': 198.0,
          'changeAmount': 0.0,
        }),
      });
      final repository = RealPosRepository(
        AdminApiClient(
          baseUrl: 'http://api.test',
          transport: transport,
          token: 'token',
          shopId: 1,
        ),
      );

      final result = await repository.checkoutTable(
        tableNumber: 'A08',
        paymentMethod: 'wechat',
        force: true,
        approvalToken: 'app-token-table-888',
      );

      expect(result.settledOrders, hasLength(2));
      expect(transport.requests, hasLength(1));
      final request = transport.requests.first;
      expect(request.method, 'POST');
      expect(request.uri.path, '/cashier/table/checkout');
      final body = jsonDecode(request.body!) as Map<String, dynamic>;
      expect(body['tableNumber'], 'A08');
      expect(body['paymentMethod'], 'wechat');
      expect(body['force'], isTrue);
      expect(body['approvalToken'], 'app-token-table-888');
    });

    testWidgets('OccupiedTableView renders occupied-force-checkout-button and triggers callback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final table = DiningTable.fromJson({'number': 'A08', 'status': 1});
      final order = PosOrder.fromJson({
        'id': 101,
        'order_no': 'ORD_A08_001',
        'table_number': 'A08',
        'diners': 3,
        'total': 188.0,
      });

      var forceCheckoutTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OccupiedTableView(
              workspace: PosWorkspace(
                table: table,
                categories: const [],
                dishes: const [],
                paymentMethods: const [],
                currentOrder: order,
              ),
              busy: false,
              onBack: () {},
              onAddDishes: ([_]) {},
              onMerge: () {},
              onTransfer: ([_]) {},
              onClear: () {},
              onRefund: (_) {},
              onGift: (_) {},
              onDiscount: ([_]) {},
              onForceCheckout: ([_]) {
                forceCheckoutTapped = true;
              },
              onPrintReceipt: (_, [_]) {},
              paymentMethods: const [],
              onCheckout: (_) {},
              onBalanceCheckout: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final forceBtn = find.byKey(const Key('occupied-force-checkout-button'));
      expect(forceBtn, findsOneWidget);
      expect(find.text('强制结账'), findsOneWidget);

      await tester.tap(forceBtn);
      await tester.pumpAndSettle();

      expect(forceCheckoutTapped, isTrue);
    });
  });
}
