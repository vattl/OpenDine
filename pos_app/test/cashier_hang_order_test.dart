import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/pos/domain/hang_order_models.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/pos_hang_order_dialog.dart';
import 'package:admin_panel_flutter/src/features/pos/presentation/hang_order_pool_dialog.dart';
import 'package:admin_panel_flutter/src/features/pos/data/pos_repository.dart';

class _MockPosRepo implements PosRepository {
  List<HangOrderSummary> listToReturn = [];
  bool unhangSuccess = true;
  String? lastUnhungOrderNo;
  String? lastHungOrderNo;
  String? lastHungReason;
  String? lastClearedTableNumber;

  @override
  Future<List<HangOrderSummary>> getHangList() async => listToReturn;

  @override
  Future<bool> unhangOrder({required String orderNo}) async {
    lastUnhungOrderNo = orderNo;
    return unhangSuccess;
  }

  @override
  Future<String?> hangOrder({required String orderNo, String? reason}) async {
    lastHungOrderNo = orderNo;
    lastHungReason = reason;
    return 'HANG-$orderNo';
  }

  @override
  Future<void> clearTable(String tableNumber) async {
    lastClearedTableNumber = tableNumber;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('HangOrderSummary model tests', () {
    test('fromJson parses server fields correctly', () {
      final json = {
        'order_id': 101,
        'order_no': 'ORD20261019001',
        'table_number': 'A03',
        'number_of_diners': 4,
        'sett_amount': 258.50,
        'hang_time': '2026-10-19T10:00:00.000Z',
        'hang_reason': '顾客忘带手机回去取',
        'hang_admin_id': 12,
        'hang_minutes': 18,
      };

      final summary = HangOrderSummary.fromJson(json);

      expect(summary.orderId, 101);
      expect(summary.orderNo, 'ORD20261019001');
      expect(summary.tableNumber, 'A03');
      expect(summary.numberOfDiners, 4);
      expect(summary.settAmount, 258.50);
      expect(summary.hangReason, '顾客忘带手机回去取');
      expect(summary.hangAdminId, 12);
      expect(summary.hangMinutes, 18);
    });

    test('fromJson handles fallbacks and alternative keys', () {
      final json = {
        'id': 202,
        'orderNo': 'ORD20261019002',
        'people': 2,
        'amount': 88,
      };

      final summary = HangOrderSummary.fromJson(json);

      expect(summary.orderId, 202);
      expect(summary.orderNo, 'ORD20261019002');
      expect(summary.tableNumber, '');
      expect(summary.numberOfDiners, 2);
      expect(summary.settAmount, 88.0);
      expect(summary.hangReason, isNull);
      expect(summary.hangMinutes, 0);
    });
  });

  group('PosHangOrderDialog widget tests', () {
    testWidgets('selects quick reason chip and renders correctly', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: PosHangOrderDialog(
                tableNumber: 'A05',
                orderNo: 'ORD20261019003',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('挂起当前订单 - A05'), findsOneWidget);
      expect(find.text('单号: ORD20261019003'), findsOneWidget);

      // Verify all quick reasons are present
      for (final reason in PosHangOrderDialog.quickReasons) {
        expect(find.text(reason), findsOneWidget);
      }

      // Tap on a quick reason chip
      await tester.tap(find.byKey(const Key('hang-reason-chip-顾客忘带手机')));
      await tester.pumpAndSettle();

      // Verify the input has this text
      expect(find.text('顾客忘带手机'), findsWidgets);
      expect(find.byKey(const Key('hang-dialog-confirm-button')), findsOneWidget);
    });
  });

  group('HangOrderPoolDialog widget tests', () {
    testWidgets('renders list and triggers onUnhangOrder', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockPosRepo();
      mockRepo.listToReturn = [
        const HangOrderSummary(
          orderId: 301,
          orderNo: 'ORD20261019004',
          tableNumber: 'B02',
          numberOfDiners: 3,
          settAmount: 168.0,
          hangMinutes: 20,
          hangReason: '顾客暂离',
        ),
      ];

      HangOrderSummary? unhungItem;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HangOrderPoolDialog(
                repository: mockRepo,
                onUnhangOrder: (item) {
                  unhungItem = item;
                },
              ),
            ),
          ),
        ),
      );

      // Pump data loading
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('门店挂单池'), findsOneWidget);
      expect(find.text('共 1 笔挂单'), findsOneWidget);
      expect(find.text('B02'), findsOneWidget);
      expect(find.text('ORD20261019004'), findsOneWidget);
      expect(find.text('¥168.00'), findsOneWidget);
      expect(find.text('20分钟'), findsOneWidget);
      expect(find.text('顾客暂离'), findsOneWidget);

      // Click 取单结账
      await tester.tap(find.byKey(const Key('unhang-btn-ORD20261019004')));
      await tester.pumpAndSettle();

      expect(mockRepo.lastUnhungOrderNo, 'ORD20261019004');
      expect(unhungItem, isNotNull);
      expect(unhungItem!.orderNo, 'ORD20261019004');
    });

    testWidgets('renders empty state when no hang orders', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockPosRepo();
      mockRepo.listToReturn = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: HangOrderPoolDialog(
                repository: mockRepo,
                onUnhangOrder: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('门店挂单池'), findsOneWidget);
      expect(find.text('当前门店无任何挂起订单'), findsOneWidget);
    });
  });
}
