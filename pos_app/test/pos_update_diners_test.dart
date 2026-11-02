import 'dart:convert';

import 'package:admin_panel_flutter/src/core/admin_api_client.dart';
import 'package:admin_panel_flutter/src/core/api_contract.dart';
import 'package:admin_panel_flutter/src/features/pos/data/real_pos_repository.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/pos_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/occupied_table_view.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_update_diners_dialog.dart';
import 'package:admin_panel_flutter/src/features/tables/domain/dining_table.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_http_transport.dart';

void main() {
  group('POS update diners contract & repository', () {
    test('cashierOrderUpdateDinersEndpoint has correct definition', () {
      expect(cashierOrderUpdateDinersEndpoint.method, 'POST');
      expect(
        cashierOrderUpdateDinersEndpoint.path,
        '/cashier/order/updateDiners',
      );
      expect(
        cashierOrderUpdateDinersEndpoint.permissionCode,
        'cashier:operate',
      );
      expect(cashierOrderUpdateDinersEndpoint.attachShopHeader, isTrue);
    });

    test('RealPosRepository.updateDiners sends correct order_no and number_of_diners', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/updateDiners': jsonEncode({
          'code': 200,
          'msg': 'success',
          'data': {'order_no': 'ORD20261020001', 'number_of_diners': 6},
        }),
      });

      final client = AdminApiClient(
        transport: transport,
        baseUrl: 'https://api.example.com',
      );
      final repo = RealPosRepository(client);

      await repo.updateDiners(orderNo: 'ORD20261020001', diners: 6);

      expect(transport.requests, hasLength(1));
      final req = transport.requests.first;
      expect(req.method, 'POST');
      expect(req.uri.path, '/cashier/order/updateDiners');
      final body = jsonDecode(req.body!) as Map<String, dynamic>;
      expect(body['order_no'], 'ORD20261020001');
      expect(body['number_of_diners'], 6);
    });

    test('RealPosRepository.updateDiners surfaces server errors e.g. 40936 or 4003', () async {
      final transport = FakeHttpTransport({
        'POST /cashier/order/updateDiners': jsonEncode({
          'code': 40936,
          'msg': '该订单所属营业日已完成日结封账，禁止修改用餐人数',
        }),
      });

      final client = AdminApiClient(
        transport: transport,
        baseUrl: 'https://api.example.com',
      );
      final repo = RealPosRepository(client);

      expect(
        () => repo.updateDiners(orderNo: 'ORD_CLOSED_01', diners: 4),
        throwsA(isA<ApiException>().having(
          (e) => e.message,
          'message',
          contains('日结封账'),
        )),
      );
    });
  });

  group('PosUpdateDinersDialog widget tests', () {
    testWidgets('displays original diners, stepper and quick buttons', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? confirmedDiners;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  confirmedDiners = await showPosUpdateDinersDialog(
                    context,
                    tableNumber: 'A01',
                    orderNo: 'ORD_TEST_01',
                    currentDiners: 3,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog header and original diners display
      expect(find.text('修改就餐人数 - A01'), findsOneWidget);
      expect(find.text('原就餐人数: 3 人 | 单号: ORD_TEST_01'), findsOneWidget);
      expect(find.text('3'), findsWidgets);

      // Verify quick number buttons 1..12
      for (var i = 1; i <= 12; i++) {
        expect(find.byKey(Key('pos-diners-quick-$i')), findsOneWidget);
      }

      // Tap quick button '6'
      await tester.tap(find.byKey(const Key('pos-diners-quick-6')));
      await tester.pumpAndSettle();
      expect(find.text('6'), findsWidgets);

      // Tap stepper plus button -> count becomes 7
      await tester.tap(find.byKey(const Key('pos-diners-stepper-plus')));
      await tester.pumpAndSettle();
      expect(find.text('7'), findsWidgets);

      // Tap stepper minus button -> count becomes 6
      await tester.tap(find.byKey(const Key('pos-diners-stepper-minus')));
      await tester.pumpAndSettle();
      expect(find.text('6'), findsWidgets);

      // Tap confirm button
      await tester.tap(find.byKey(const Key('pos-update-diners-confirm-button')));
      await tester.pumpAndSettle();

      expect(confirmedDiners, 6);
    });

    testWidgets('manual custom diners input validates 1..999 bounds', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? confirmedDiners;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  confirmedDiners = await showPosUpdateDinersDialog(
                    context,
                    tableNumber: 'A02',
                    orderNo: 'ORD_TEST_02',
                    currentDiners: 2,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap '自定义' button to open custom input
      await tester.tap(find.byKey(const Key('pos-diners-quick-custom')));
      await tester.pumpAndSettle();

      // Enter '25'
      final inputFinder = find.byKey(const Key('pos-update-diners-input'));
      expect(inputFinder, findsOneWidget);
      await tester.enterText(inputFinder, '25');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('pos-update-diners-confirm-button')));
      await tester.pumpAndSettle();

      expect(confirmedDiners, 25);
    });
  });

  group('OccupiedTableView update diners entry tests', () {
    testWidgets('OccupiedTableView renders update diners button and triggers callback', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final table = DiningTable.fromJson({'number': 'B02', 'status': 1});
      final order = PosOrder.fromJson({
        'id': 202,
        'order_no': 'ORD_B02_001',
        'table_number': 'B02',
        'diners': 4,
        'total': 268.0,
      });

      var updateDinersInvoked = false;

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
              onPrintReceipt: (_, [_]) {},
              paymentMethods: const [],
              onCheckout: (_) {},
              onBalanceCheckout: () {},
              onUpdateDiners: ([_]) {
                updateDinersInvoked = true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final updateBtnFinder = find.byKey(const Key('occupied-update-diners-button'));
      expect(updateBtnFinder, findsOneWidget);

      await tester.tap(updateBtnFinder);
      await tester.pumpAndSettle();

      expect(updateDinersInvoked, isTrue);
    });
  });
}
