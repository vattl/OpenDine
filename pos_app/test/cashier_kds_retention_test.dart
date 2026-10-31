import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_command_service.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CashierKdsDatabase database;
  late LocalKdsCommandService commands;

  setUp(() {
    database = CashierKdsDatabase.inMemory();
    commands = LocalKdsCommandService(database);
  });
  tearDown(() => database.close());

  CashierOrderReceipt create(String eventId, int at) => database.createOrder(
    CashierOrderDraft(
      shopId: 1,
      tableNumber: '$at',
      fulfillmentType: 'dine_in',
      remark: '',
      createdAtMs: at,
      lines: const [
        CashierOrderLineDraft(
          dishId: 101,
          dishName: '油边王',
          specification: '',
          unit: '串',
          quantity: 1,
        ),
      ],
    ),
    eventId: eventId,
  );

  test('journal cleanup enforces age and maximum retained count', () {
    create('e1', 1000);
    create('e2', 1001);
    create('e3', 1002);

    final result = database.cleanupRetention(nowMs: 2000, maxJournalEvents: 2);

    expect(result['journal_deleted'], 1);
    expect(database.readChanges(shopId: 1, afterSeq: 0).map((e) => e.eventId), [
      'e2',
      'e3',
    ]);
  });

  test('30 day cleanup never deletes an order with undelivered outbox', () {
    final delivered = create('delivered-order', 1000);
    final deliveredLine = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    commands.execute(
      LocalKdsCommand(
        commandId: 'delivered-complete',
        type: LocalKdsCommandType.completeOrder,
        shopId: 1,
        target: LocalKdsCommandTarget(orderId: delivered.orderId),
        expectedRevision: deliveredLine.orderRevision,
        occurredAtMs: 1100,
      ),
    );
    var due = database.readDueCloudEvents(nowMs: 1200).single;
    database.applyCloudAckAndMarkDelivered(
      due,
      CashierCloudEventAck(
        eventId: due.eventId,
        cloudOrderId: 9001,
        cloudOrderNo: 'CLOUD-1',
        detailMappings: {deliveredLine.detailId: 9901},
      ),
      deliveredAtMs: 1200,
    );
    due = database.readDueCloudEvents(nowMs: 1200).single;
    database.applyCloudAckAndMarkDelivered(
      due,
      CashierCloudEventAck(eventId: due.eventId),
      deliveredAtMs: 1200,
    );

    final pending = create('pending-order', 1200);
    final pendingRevision = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .firstWhere((line) => line.orderId == pending.orderId)
        .orderRevision;
    commands.execute(
      LocalKdsCommand(
        commandId: 'pending-complete',
        type: LocalKdsCommandType.completeOrder,
        shopId: 1,
        target: LocalKdsCommandTarget(orderId: pending.orderId),
        expectedRevision: pendingRevision,
        occurredAtMs: 1300,
      ),
    );
    final result = database.cleanupRetention(
      nowMs: const Duration(days: 31).inMilliseconds,
    );

    expect(result['completed_orders_deleted'], 1);
    final done = database.readWorkflowBoard(shopId: 1, queue: 'done').lines;
    expect(done.map((line) => line.orderId), [pending.orderId]);
    expect(
      database.readPendingCloudEvents().any(
        (event) => event.aggregateKey == 'order:${pending.orderId}',
      ),
      isTrue,
    );
  });

  test(
    'retention removes only terminal outbox rows and keeps sequence high water',
    () {
      create('terminal-order', 1000);
      final event = database.readDueCloudEvents(nowMs: 1000).single;
      final terminalLine = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      database.applyCloudAckAndMarkDelivered(
        event,
        CashierCloudEventAck(
          eventId: event.eventId,
          cloudOrderId: 9002,
          cloudOrderNo: 'CLOUD-2',
          detailMappings: {terminalLine.detailId: 9902},
        ),
        deliveredAtMs: 1000,
      );
      final pending = create('pending-order', 1001);

      final result = database.cleanupRetention(
        nowMs: const Duration(days: 31).inMilliseconds,
      );

      expect(result['terminal_outbox_deleted'], 1);
      expect(
        database.readPendingCloudEvents().map((event) => event.eventId),
        contains('pending-order'),
      );
      expect(pending.orderId, greaterThan(0));
    },
  );

  test('walCheckpointPassive executes safely without error', () {
    expect(() => database.walCheckpointPassive(), returnsNormally);
  });

  test('readDuePendingCommands respects due time and batch limit', () {
    database.insertPendingCommand(
      commandId: 'cmd-due-1',
      shopId: 1,
      commandType: 'advance_item',
      targetJson: '{"detail_id": 101}',
      payloadJson: '{"quantity": 1}',
      occurredAtMs: 1000,
      actorId: 'KDS-1',
    );
    database.insertPendingCommand(
      commandId: 'cmd-due-2',
      shopId: 1,
      commandType: 'advance_item',
      targetJson: '{"detail_id": 102}',
      payloadJson: '{"quantity": 1}',
      occurredAtMs: 1005,
      actorId: 'KDS-1',
    );
    database.insertPendingCommand(
      commandId: 'cmd-future',
      shopId: 1,
      commandType: 'advance_item',
      targetJson: '{"detail_id": 103}',
      payloadJson: '{"quantity": 1}',
      occurredAtMs: 1010,
      actorId: 'KDS-1',
    );
    // cmd-future rescheduled to future (3000ms)
    database.reschedulePendingCommand(1, 'cmd-future', 3000, 1, 'retry later');

    // Query due at 2000ms with limit 1
    final batch1 = database.readDuePendingCommands(nowMs: 2000, limit: 1);
    expect(batch1.length, 1);
    expect(batch1.single['command_id'], 'cmd-due-1');

    // Query due at 2000ms with limit 10
    final batchAllDue = database.readDuePendingCommands(nowMs: 2000, limit: 10);
    expect(batchAllDue.map((c) => c['command_id']), ['cmd-due-1', 'cmd-due-2']);

    // Query due at 4000ms includes future command
    final batchAt4000 = database.readDuePendingCommands(nowMs: 4000, limit: 10);
    expect(batchAt4000.map((c) => c['command_id']), [
      'cmd-due-1',
      'cmd-due-2',
      'cmd-future',
    ]);
  });

  test(
    'retention cleans up terminal pending commands and preserves active commands',
    () {
      // 1. Insert and complete a command (status -> APPLIED)
      database.insertPendingCommand(
        commandId: 'cmd-terminal-old',
        shopId: 1,
        commandType: 'advance_item',
        targetJson: '{"detail_id": 101}',
        payloadJson: '{"quantity": 1}',
        occurredAtMs: 1000,
        actorId: 'KDS-1',
      );
      database.updatePendingCommandStatus(
        1,
        'cmd-terminal-old',
        'APPLIED',
        resultJson: '{"status":"APPLIED"}',
      );

      // 2. Insert and reject a command (status -> REJECTED)
      database.insertPendingCommand(
        commandId: 'cmd-rejected-old',
        shopId: 1,
        commandType: 'advance_item',
        targetJson: '{"detail_id": 102}',
        payloadJson: '{"quantity": 1}',
        occurredAtMs: 1000,
        actorId: 'KDS-1',
      );
      database.updatePendingCommandStatus(
        1,
        'cmd-rejected-old',
        'REJECTED',
        lastError: 'business conflict',
      );

      // 3. Insert an active pending command
      database.insertPendingCommand(
        commandId: 'cmd-active-pending',
        shopId: 1,
        commandType: 'advance_item',
        targetJson: '{"detail_id": 103}',
        payloadJson: '{"quantity": 1}',
        occurredAtMs: 1000,
        actorId: 'KDS-1',
      );

      // Run retention cleanup 31 days in the future
      final result = database.cleanupRetention(
        nowMs:
            DateTime.now().millisecondsSinceEpoch +
            const Duration(days: 31).inMilliseconds,
        terminalCommandRetention: const Duration(days: 30),
      );

      expect(result['terminal_commands_deleted'], 2);
      // Active command remains in pending_commands
      expect(database.readPendingCommand(1, 'cmd-active-pending'), isNotNull);
      // Terminal old commands are removed
      expect(database.readPendingCommand(1, 'cmd-terminal-old'), isNull);
      expect(database.readPendingCommand(1, 'cmd-rejected-old'), isNull);
    },
  );
}

