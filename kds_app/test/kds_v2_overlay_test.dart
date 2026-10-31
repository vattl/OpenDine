import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_overlay.dart';

void main() {
  group('KdsV2Overlay & applyOverlaysToLines', () {
    KdsV2Line createBaseLine({
      int detailId = 101,
      int orderId = 1,
      int dishId = 10,
      String dishName = '羊肉串',
      int lineQuantity = 5,
      int prepRemaining = 5,
      int cookRemaining = 5,
      int readyRemaining = 5,
    }) {
      return KdsV2Line.fromJson({
        'detail_id': detailId,
        'order_id': orderId,
        'dish_id': dishId,
        'dish_name': dishName,
        'line_quantity': lineQuantity,
        'refunded_quantity': 0,
        'prep_remaining': prepRemaining,
        'cook_remaining': cookRemaining,
        'ready_remaining': readyRemaining,
        'local_revision': 1,
        'order_revision': 1,
        'workflow_queue': 'pending_prep',
        'fulfillment_bucket': 'dine_in',
        'table_number': 'A01',
        'order_no': 'ORD001',
        'specification': '',
        'unit': '串',
        'remark': '',
        'created_at_ms': 1720000000000,
        'held': false,
        'rushed': false,
        'lacked': false,
        'removed': false,
      });
    }

    test('inferDestQueue correctly detects next queue in three-flow workflow', () {
      expect(inferDestQueue(KdsV2CommandType.advanceItem, 'pending_prep'), 'pending_cook');
      expect(inferDestQueue(KdsV2CommandType.advanceItem, 'pending_cook'), 'ready_serve');
      expect(inferDestQueue(KdsV2CommandType.advanceItem, 'ready_serve'), 'done');
      expect(inferDestQueue(KdsV2CommandType.advanceItem, 'done'), isNull);

      expect(inferDestQueue(KdsV2CommandType.revokeItem, 'done'), 'ready_serve');
      expect(inferDestQueue(KdsV2CommandType.revokeItem, 'ready_serve'), 'pending_cook');
      expect(inferDestQueue(KdsV2CommandType.revokeItem, 'pending_cook'), 'pending_prep');
    });

    test('no overlays returns original lines and slices', () {
      final line = createBaseLine();
      final projected = applyOverlaysToLines([line], const []);

      expect(projected.length, 1);
      expect(projected.first.slices.length, 1);
      expect(projected.first.slices.first.queue, 'pending_prep');
      expect(projected.first.slices.first.quantity, 5);
      expect(projected.first.slices.first.isOptimistic, isFalse);
    });

    test('advance overlay projects optimistic slice into destination queue', () {
      final line = createBaseLine(
        prepRemaining: 5,
        cookRemaining: 5,
        readyRemaining: 5,
      );

      final overlay = KdsV2OptimisticOverlay(
        commandId: 'cmd-adv-1',
        aggregateKey: 'order:1',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(orderId: 1, detailId: 101, fromQueue: 'pending_prep'),
        fromQueue: 'pending_prep',
        toQueue: 'pending_cook',
        quantity: 2,
        status: KdsOverlayStatus.persisting,
        createdAt: DateTime.now(),
      );

      final projected = applyOverlaysToLines([line], [overlay]);

      expect(projected.length, 1);
      final slices = projected.first.slices;
      expect(slices.length, 2);

      // Remaining in pending_prep: 5 - 2 = 3
      final prepSlice = slices.firstWhere((s) => s.queue == 'pending_prep');
      expect(prepSlice.quantity, 3);
      expect(prepSlice.isOptimistic, isFalse);

      // Advanced to pending_cook: 2 (optimistic)
      final cookSlice = slices.firstWhere((s) => s.queue == 'pending_cook');
      expect(cookSlice.quantity, 2);
      expect(cookSlice.isOptimistic, isTrue);
      expect(cookSlice.overlayStatus, KdsOverlayStatus.persisting);
      expect(cookSlice.commandId, 'cmd-adv-1');
      expect(projected.first.optimisticQueues, contains('pending_cook'));
    });

    test('multiple overlays from pending to sending update slice overlayStatus', () {
      final line = createBaseLine(
        prepRemaining: 5,
        cookRemaining: 5,
        readyRemaining: 5,
      );

      final overlayPending = KdsV2OptimisticOverlay(
        commandId: 'cmd-adv-1',
        aggregateKey: 'order:1',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(orderId: 1, detailId: 101, fromQueue: 'pending_prep'),
        fromQueue: 'pending_prep',
        toQueue: 'pending_cook',
        quantity: 2,
        status: KdsOverlayStatus.pending,
        createdAt: DateTime.now(),
      );

      var projected = applyOverlaysToLines([line], [overlayPending]);

      var cookSlice = projected.first.slices.firstWhere((s) => s.queue == 'pending_cook');
      expect(cookSlice.overlayStatus, KdsOverlayStatus.pending);

      // Status transitions to sending
      final overlaySending = overlayPending.copyWith(status: KdsOverlayStatus.sending);
      projected = applyOverlaysToLines([line], [overlaySending]);

      cookSlice = projected.first.slices.firstWhere((s) => s.queue == 'pending_cook');
      expect(cookSlice.overlayStatus, KdsOverlayStatus.sending);
    });

    test('unknown status overlay marks slice with unknown for visual inspection', () {
      final line = createBaseLine(
        prepRemaining: 5,
        cookRemaining: 5,
        readyRemaining: 5,
      );

      final overlayUnknown = KdsV2OptimisticOverlay(
        commandId: 'cmd-unk-1',
        aggregateKey: 'order:1',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(orderId: 1, detailId: 101, fromQueue: 'pending_prep'),
        fromQueue: 'pending_prep',
        toQueue: 'pending_cook',
        quantity: 1,
        status: KdsOverlayStatus.unknown,
        createdAt: DateTime.now(),
      );

      final projected = applyOverlaysToLines([line], [overlayUnknown]);

      final cookSlice = projected.first.slices.firstWhere((s) => s.queue == 'pending_cook');
      expect(cookSlice.isOptimistic, isTrue);
      expect(cookSlice.overlayStatus, KdsOverlayStatus.unknown);
    });

    test('conflict status overlay marks slice with conflict for rollback inspection', () {
      final line = createBaseLine(
        prepRemaining: 5,
        cookRemaining: 5,
        readyRemaining: 5,
      );

      final overlayConflict = KdsV2OptimisticOverlay(
        commandId: 'cmd-conf-1',
        aggregateKey: 'order:1',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(orderId: 1, detailId: 101, fromQueue: 'pending_prep'),
        fromQueue: 'pending_prep',
        toQueue: 'pending_cook',
        quantity: 1,
        status: KdsOverlayStatus.conflict,
        createdAt: DateTime.now(),
      );

      final projected = applyOverlaysToLines([line], [overlayConflict]);

      final cookSlice = projected.first.slices.firstWhere((s) => s.queue == 'pending_cook');
      expect(cookSlice.isOptimistic, isTrue);
      expect(cookSlice.overlayStatus, KdsOverlayStatus.conflict);
    });

    test('multi-step advance from prep to ready via sequential overlays', () {
      final line = createBaseLine(
        prepRemaining: 5,
        cookRemaining: 5,
        readyRemaining: 5,
      );

      // Advance 3 from prep to cook
      final o1 = KdsV2OptimisticOverlay(
        commandId: 'cmd-1',
        aggregateKey: 'order:1',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(orderId: 1, detailId: 101, fromQueue: 'pending_prep'),
        fromQueue: 'pending_prep',
        toQueue: 'pending_cook',
        quantity: 3,
        status: KdsOverlayStatus.sending,
        createdAt: DateTime.now(),
      );

      // Advance 2 from cook to ready
      final o2 = KdsV2OptimisticOverlay(
        commandId: 'cmd-2',
        aggregateKey: 'order:1',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(orderId: 1, detailId: 101, fromQueue: 'pending_cook'),
        fromQueue: 'pending_cook',
        toQueue: 'ready_serve',
        quantity: 2,
        status: KdsOverlayStatus.pending,
        createdAt: DateTime.now(),
      );

      final projected = applyOverlaysToLines([line], [o1, o2]);

      final slices = projected.first.slices;
      // prep: 5 - 3 = 2
      expect(slices.firstWhere((s) => s.queue == 'pending_prep').quantity, 2);
      // cook: 3 - 2 = 1 (optimistic)
      expect(slices.firstWhere((s) => s.queue == 'pending_cook').quantity, 1);
      // ready: 2 (optimistic)
      expect(slices.firstWhere((s) => s.queue == 'ready_serve').quantity, 2);
    });

    test('reconciliation clears overlay when authoritative line arrives', () {
      final initialLine = createBaseLine(
        prepRemaining: 5,
        cookRemaining: 5,
        readyRemaining: 5,
      );

      final overlay = KdsV2OptimisticOverlay(
        commandId: 'cmd-adv-1',
        aggregateKey: 'order:1',
        commandType: KdsV2CommandType.advanceItem,
        target: const KdsV2CommandTarget(orderId: 1, detailId: 101, fromQueue: 'pending_prep'),
        fromQueue: 'pending_prep',
        toQueue: 'pending_cook',
        quantity: 2,
        status: KdsOverlayStatus.sending,
        createdAt: DateTime.now(),
      );

      // Before ACK
      var projected = applyOverlaysToLines([initialLine], [overlay]);
      expect(projected.first.slices.firstWhere((s) => s.queue == 'pending_cook').isOptimistic, isTrue);

      // Server ACK arrives with new authoritative cumulative values: prep_remaining = 3
      final updatedAuthoritativeLine = createBaseLine(
        prepRemaining: 3,
        cookRemaining: 5,
        readyRemaining: 5,
      );

      // On ACK, overlay is removed from list
      projected = applyOverlaysToLines([updatedAuthoritativeLine], const []);

      final cookSlice = projected.first.slices.firstWhere((s) => s.queue == 'pending_cook');
      expect(cookSlice.quantity, 2);
      expect(cookSlice.isOptimistic, isFalse);
      expect(cookSlice.overlayStatus, isNull);
    });
  });
}
