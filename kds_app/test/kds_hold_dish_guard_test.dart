import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_controller.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_page.dart';

KdsV2Bootstrap _createBootstrap({required List<KdsV2Line> lines}) =>
    KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'pending_cook': [for (final line in lines) line.raw],
      },
    });

class _FakeTransport implements KdsV2Transport {
  KdsV2Bootstrap bootstrapResult = _createBootstrap(lines: []);

  @override
  Future<KdsV2Bootstrap> bootstrap() async => bootstrapResult;

  @override
  Future<KdsV2Changes> changes(int afterSeq) async =>
      const KdsV2Changes(eventSeq: 1, snapshotRequired: false, events: []);

  @override
  Future<KdsV2CommandResult> command(KdsV2Command command) async =>
      KdsV2CommandResult.fromJson({
        'command_id': command.commandId,
        'status': 'applied',
        'detail_id': command.target.detailId,
        'from_queue': command.target.fromQueue,
        'to_queue': command.target.fromQueue,
        'applied_quantity': command.quantity,
        'new_revision': 1,
      });

  @override
  Future<void> updateConfig(Map<String, dynamic> config) async {}

  @override
  Future<Map<String, dynamic>> businessDayOrders({int? afterId, int limit = 200}) async => {
        'data': {'orders': []}
      };
}

KdsV2Line _buildLine({
  required int detailId,
  required int quantity,
  bool held = false,
  int holdFlag = 0,
  int refundedQuantity = 0,
  int cookRemaining = 1,
  String lineStatus = 'normal',
}) {
  return KdsV2Line.fromJson({
    'detail_id': detailId,
    'order_id': 100,
    'dish_id': 20,
    'dish_name': '秘制烤五花',
    'line_quantity': quantity,
    'refunded_quantity': refundedQuantity,
    'prep_remaining': 0,
    'cook_remaining': cookRemaining,
    'ready_remaining': cookRemaining,
    'local_revision': 1,
    'order_revision': 1,
    'workflow_queue': 'pending_cook',
    'fulfillment_bucket': 'dine_in',
    'table_number': 'A01',
    'order_no': 'ORD20261019001',
    'specification': null,
    'unit': '份',
    'remark': null,
    'rushed': false,
    'lacked': false,
    'removed': false,
    'held': held,
    'hold_flag': holdFlag,
    'line_status': lineStatus,
    'created_at_ms': 1720000000000,
  });
}

void main() {
  group('KdsV2Controller.updateDishFlags tests', () {
    test('in-place updates held, hold_flag, and order_rece without full reload', () async {
      final initialLine = _buildLine(detailId: 101, quantity: 2, held: false, holdFlag: 0);
      final transport = _FakeTransport()
        ..bootstrapResult = _createBootstrap(lines: [initialLine]);

      final controller = KdsV2Controller(transport);
      await controller.start();

      expect(controller.state.lines.first.raw['held'], isFalse);
      expect(controller.state.lines.first.raw['hold_flag'], 0);

      // 1. Update to held (holdFlag = 1)
      controller.updateDishFlags(detailId: 101, holdFlag: 1);
      final heldLine = controller.state.lines.first;
      expect(heldLine.raw['held'], isTrue);
      expect(heldLine.raw['hold_flag'], 1);
      expect(heldLine.raw['order_rece'], 'mis_order');

      // 2. Update to unheld (holdFlag = 0)
      controller.updateDishFlags(detailId: 101, holdFlag: 0);
      final unheldLine = controller.state.lines.first;
      expect(unheldLine.raw['held'], isFalse);
      expect(unheldLine.raw['hold_flag'], 0);
      expect(unheldLine.raw['order_rece'], 'rec_order');
    });

    test('ignores non-positive detailId or unmatched lines safely', () async {
      final initialLine = _buildLine(detailId: 102, quantity: 1, held: false, holdFlag: 0);
      final transport = _FakeTransport()
        ..bootstrapResult = _createBootstrap(lines: [initialLine]);

      final controller = KdsV2Controller(transport);
      await controller.start();

      // Non-positive detailId
      controller.updateDishFlags(detailId: 0, holdFlag: 1);
      controller.updateDishFlags(detailId: -1, holdFlag: 1);
      expect(controller.state.lines.first.raw['held'], isFalse);

      // Unmatched detailId
      controller.updateDishFlags(detailId: 999, holdFlag: 1);
      expect(controller.state.lines.first.raw['held'], isFalse);
    });
  });

  group('showKdsHoldBlockedNotice tests', () {
    testWidgets('shows warning SnackBar when called', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('trigger-notice-button'),
                  onPressed: () => showKdsHoldBlockedNotice(context),
                  child: const Text('触发等叫拦截'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('trigger-notice-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('该菜品处于等叫状态，请先点击【起菜】后再制作！'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_filled), findsOneWidget);
    });
  });
}
