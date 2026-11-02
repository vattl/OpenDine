import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_command_service.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CashierKdsDatabase database;
  late LocalKdsCommandService service;

  setUp(() {
    database = CashierKdsDatabase.inMemory();
    service = LocalKdsCommandService(database);
  });

  tearDown(() => database.close());

  CashierOrderReceipt seedOrder({int createdAtMs = 1000}) =>
      database.createOrder(
        CashierOrderDraft(
          shopId: 1,
          tableNumber: '8',
          fulfillmentType: 'dine_in',
          remark: '',
          createdAtMs: createdAtMs,
          lines: const [
            CashierOrderLineDraft(
              dishId: 101,
              dishName: '油边王',
              specification: '',
              unit: '串',
              quantity: 2,
            ),
          ],
        ),
        eventId: 'order-$createdAtMs',
      );

  CashierWorkflowLine currentLine(int detailId) =>
      const ['pending_prep', 'pending_cook', 'ready_serve', 'done']
          .expand(
            (queue) =>
                database.readWorkflowBoard(shopId: 1, queue: queue).lines,
          )
          .firstWhere((line) => line.detailId == detailId);

  int currentOrderRevision(int orderId) =>
      const ['pending_prep', 'pending_cook', 'ready_serve', 'done']
          .expand(
            (queue) =>
                database.readWorkflowBoard(shopId: 1, queue: queue).lines,
          )
          .firstWhere((line) => line.orderId == orderId)
          .orderRevision;

  test('command commits line, journal and outbox with one event sequence', () {
    seedOrder();
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;

    final result = service.execute(
      LocalKdsCommand(
        commandId: 'command-1',
        type: LocalKdsCommandType.advanceItem,
        shopId: 1,
        target: LocalKdsCommandTarget(
          detailId: line.detailId,
          fromQueue: 'pending_prep',
        ),
        quantity: 2,
        expectedRevision: line.localRevision,
        occurredAtMs: 2000,
      ),
    );

    expect(result.eventSeq, greaterThan(1));
    expect(result.patches, hasLength(1));
    expect(result.patches.single['workflow_queue'], 'pending_cook');
    expect(
      database.readChanges(shopId: 1, afterSeq: 0).last.eventSeq,
      result.eventSeq,
    );
    expect(database.readPendingCloudEvents().last.eventId, 'command-1');
  });

  test('cloud-first KDS state event uses formal cloud ids', () {
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '8',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 2,
            cloudDetailId: 9901,
          ),
        ],
      ),
      eventId: 'cloud-first-order',
      cloudOrderId: 9001,
      cloudOrderNo: 'CLOUD-9001',
      enqueueCloudEvent: false,
    );
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;

    service.execute(
      LocalKdsCommand(
        commandId: 'cloud-first-advance',
        type: LocalKdsCommandType.advanceItem,
        shopId: 1,
        target: LocalKdsCommandTarget(
          detailId: line.detailId,
          fromQueue: 'pending_prep',
        ),
        quantity: 1,
        expectedRevision: line.localRevision,
        occurredAtMs: 2000,
      ),
    );

    final event = database.readPendingCloudEvents().single;
    final payload = event.payload;
    final formalOrder = (payload['orders'] as List).single as Map;
    final formalLine = (payload['lines'] as List).single as Map;
    expect(event.eventType, 'kds_state_changed');
    // 本地出生订单（云端联调实测）：aggregate 终身固定为本地 id，且云端
    // 校验 aggregate 与 payload 本地订单 id 一致，因此 local_order_id /
    // local_detail_id 别名必须始终携带；已映射时 order_id / detail_id
    // 同时使用正式 id。
    expect(event.aggregateKey, 'order:1');
    expect(payload['order_id'], 9001);
    expect(payload['local_order_id'], 1);
    expect(formalOrder['order_id'], 9001);
    expect(formalOrder['local_order_id'], 1);
    expect(formalLine['order_id'], 9001);
    expect(formalLine['detail_id'], 9901);
    expect(formalLine['local_order_id'], 1);
    expect(formalLine['local_detail_id'], 1);
  });

  test('state-changed ACK applies detail mappings to unmapped lines', () {
    final order = seedOrder();
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    service.execute(
      LocalKdsCommand(
        commandId: 'rush-before-map',
        type: LocalKdsCommandType.rushOrder,
        shopId: 1,
        target: LocalKdsCommandTarget(orderId: order.orderId),
        expectedRevision: currentOrderRevision(order.orderId),
        occurredAtMs: 2000,
      ),
    );
    final event = database.readPendingCloudEvents().last;
    expect(event.eventType, 'kds_state_changed');

    // 云端为该订单中尚未映射的行返回正式明细映射。
    database.applyCloudAckAndMarkDelivered(
      event,
      CashierCloudEventAck(
        eventId: event.eventId,
        detailMappings: {line.detailId: 55501},
      ),
      deliveredAtMs: 3000,
    );

    // 后续事件的行级 id 应使用云端正式 detail_id。
    service.execute(
      LocalKdsCommand(
        commandId: 'rush-after-map',
        type: LocalKdsCommandType.rushItem,
        shopId: 1,
        target: LocalKdsCommandTarget(detailId: line.detailId),
        expectedRevision: currentLine(line.detailId).localRevision,
        occurredAtMs: 4000,
      ),
    );
    final next = database.readPendingCloudEvents().last;
    final payloadLine = (next.payload['lines'] as List).single as Map;
    expect(payloadLine['detail_id'], 55501);
  });

  test('same command id only replays an identical fingerprint', () {
    final order = seedOrder();
    final command = LocalKdsCommand(
      commandId: 'rush-1',
      type: LocalKdsCommandType.rushOrder,
      shopId: 1,
      target: LocalKdsCommandTarget(orderId: order.orderId),
      expectedRevision: currentOrderRevision(order.orderId),
      occurredAtMs: 2000,
    );

    final first = service.execute(command);
    final duplicate = service.execute(command.copyWith(occurredAtMs: 2100));

    expect(first.duplicate, isFalse);
    expect(duplicate.duplicate, isTrue);
    expect(duplicate.eventSeq, first.eventSeq);
    expect(
      () => service.execute(
        command.copyWith(
          target: LocalKdsCommandTarget(orderId: order.orderId + 1),
        ),
      ),
      throwsA(isA<CashierKdsValidation>()),
    );
  });

  test(
    'command audit preserves actor and full before/after state on replay',
    () {
      seedOrder();
      final line = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      final command = LocalKdsCommand(
        commandId: 'audited-command',
        type: LocalKdsCommandType.holdItem,
        shopId: 1,
        target: LocalKdsCommandTarget(detailId: line.detailId),
        expectedRevision: line.localRevision,
        actorDeviceCode: 'KDS-A',
        occurredAtMs: 2000,
      );

      service.execute(command);
      final firstAudit = database.readOperationAudit(command.commandId)!;
      final duplicate = service.execute(command.copyWith(occurredAtMs: 2100));

      expect(duplicate.duplicate, isTrue);
      expect(firstAudit['actor_device_code'], 'KDS-A');
      expect((firstAudit['before_state'] as Map)['orders'], hasLength(1));
      expect((firstAudit['before_state'] as Map)['lines'], hasLength(1));
      expect((firstAudit['after_state'] as Map)['orders'], hasLength(1));
      expect((firstAudit['after_state'] as Map)['lines'], hasLength(1));
      expect(database.readOperationAudit(command.commandId), firstAudit);
      expect(
        () => service.execute(command.copyWith(actorDeviceCode: 'KDS-B')),
        throwsA(isA<CashierKdsValidation>()),
      );
    },
  );

  test('revision contract rejects omitted and non-exact target revisions', () {
    final first = seedOrder(createdAtMs: 1000);
    seedOrder(createdAtMs: 1001);
    final lines = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines;

    expect(
      () => service.execute(
        LocalKdsCommand(
          commandId: 'missing-order-revision',
          type: LocalKdsCommandType.rushOrder,
          shopId: 1,
          target: LocalKdsCommandTarget(orderId: first.orderId),
          occurredAtMs: 2000,
        ),
      ),
      throwsA(isA<CashierKdsValidation>()),
    );
    expect(
      () => service.execute(
        LocalKdsCommand(
          commandId: 'missing-line-revision',
          type: LocalKdsCommandType.holdItem,
          shopId: 1,
          target: LocalKdsCommandTarget(detailId: lines.first.detailId),
          occurredAtMs: 2001,
        ),
      ),
      throwsA(isA<CashierKdsValidation>()),
    );
    for (final revisions in [
      {'${lines.first.detailId}': lines.first.localRevision},
      {
        for (final line in lines) '${line.detailId}': line.localRevision,
        '99999': 1,
      },
    ]) {
      expect(
        () => service.execute(
          LocalKdsCommand(
            commandId: 'bad-revision-set-${revisions.length}',
            type: LocalKdsCommandType.advanceItem,
            shopId: 1,
            target: LocalKdsCommandTarget(
              detailIds: lines.map((line) => line.detailId).toList(),
              fromQueue: 'pending_prep',
            ),
            quantity: 1,
            payload: {'expected_revisions': revisions},
            occurredAtMs: 2100,
          ),
        ),
        throwsA(isA<CashierKdsValidation>()),
      );
    }
  });

  test('cloud config refresh preserves local stock and sold-out facts', () {
    database.replaceDishCatalog(
      shopId: 1,
      updatedAtMs: 500,
      items: const [
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '旧菜名',
          unit: '串',
          sequence: 0,
          stock: 5,
        ),
      ],
    );
    seedOrder();
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    service.execute(
      LocalKdsCommand(
        commandId: 'local-sold-out',
        type: LocalKdsCommandType.lackItem,
        shopId: 1,
        target: LocalKdsCommandTarget(detailId: line.detailId),
        expectedRevision: line.localRevision,
        payload: const {'set_sold_out': true},
        occurredAtMs: 1100,
      ),
    );

    database.applyConfigSnapshot(
      const CashierKdsConfigSnapshot(
        shopId: 1,
        version: 1,
        payload: {
          'authority_device': {
            'device_code': 'CASHIER-A',
            'enforcement': 'primary_only',
          },
          'catalog': [
            {
              'dish_id': 101,
              'dish_name': '云端新菜名',
              'unit': '份',
              'sorting': 3,
              'stock': 99,
              'sold_out': false,
              'onsale': true,
            },
          ],
        },
        updatedAtMs: 2000,
        expiresAtMs: 3000,
      ),
    );

    final dish = database.readDishCatalog(shopId: 1).single;
    expect(dish.dishName, '云端新菜名');
    expect(dish.unit, '份');
    expect(dish.stock, 5);
    expect(dish.soldOut, isTrue);
    expect(dish.onSale, isTrue);
  });

  test('hold item and archive clear use the same command journal', () {
    final order = seedOrder();
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    final held = service.execute(
      LocalKdsCommand(
        commandId: 'hold-1',
        type: LocalKdsCommandType.holdItem,
        shopId: 1,
        target: LocalKdsCommandTarget(detailId: line.detailId),
        expectedRevision: line.localRevision,
        occurredAtMs: 2000,
      ),
    );
    expect(held.patches.single['held'], isTrue);

    service.execute(
      LocalKdsCommand(
        commandId: 'archive-1',
        type: LocalKdsCommandType.archiveOrder,
        shopId: 1,
        target: LocalKdsCommandTarget(orderId: order.orderId),
        expectedRevision: currentOrderRevision(order.orderId),
        occurredAtMs: 3000,
      ),
    );
    final cleared = service.execute(
      const LocalKdsCommand(
        commandId: 'clear-1',
        type: LocalKdsCommandType.archiveClear,
        shopId: 1,
        target: LocalKdsCommandTarget(),
        occurredAtMs: 4000,
      ),
    );
    expect(cleared.orderSummary?['cleared_count'], 0);
    expect(
      database.readChanges(shopId: 1, afterSeq: 0).length,
      greaterThanOrEqualTo(4),
    );
  });

  test('all item and order commands return complete snapshot patches', () {
    final order = seedOrder();
    var line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    LocalKdsCommandResult run(
      String id,
      LocalKdsCommandType type, {
      LocalKdsCommandTarget? target,
      int? quantity,
      Map<String, Object?> payload = const {},
    }) {
      final resolvedTarget =
          target ?? LocalKdsCommandTarget(detailId: line.detailId);
      final expectedRevision = type == LocalKdsCommandType.archiveClear
          ? null
          : resolvedTarget.orderId != null
          ? currentOrderRevision(resolvedTarget.orderId!)
          : resolvedTarget.detailIds.length > 1
          ? null
          : currentLine(resolvedTarget.detailId!).localRevision;
      return service.execute(
        LocalKdsCommand(
          commandId: id,
          type: type,
          shopId: 1,
          target: resolvedTarget,
          quantity: quantity,
          expectedRevision: expectedRevision,
          payload: payload,
          occurredAtMs: 3000 + database.latestEventSeq,
        ),
      );
    }

    final advanced = run(
      'advance-order',
      LocalKdsCommandType.advanceOrder,
      target: LocalKdsCommandTarget(
        orderId: order.orderId,
        fromQueue: 'pending_prep',
      ),
    );
    expect(advanced.orderSummary?['order_id'], order.orderId);
    line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
        .lines
        .single;
    expect(
      run(
        'revoke',
        LocalKdsCommandType.revokeItem,
        target: LocalKdsCommandTarget(
          detailId: line.detailId,
          fromQueue: 'pending_cook',
        ),
      ).patches.single,
      containsPair('workflow_queue', 'pending_prep'),
    );
    expect(
      run(
        'lack',
        LocalKdsCommandType.lackItem,
        payload: const {'set_sold_out': true},
      ).patches.single['lacked'],
      isTrue,
    );
    expect(
      run('rush-item', LocalKdsCommandType.rushItem).patches.single['rushed'],
      isTrue,
    );
    expect(
      run('hold', LocalKdsCommandType.holdItem).patches.single['held'],
      isTrue,
    );
    expect(
      run('release', LocalKdsCommandType.releaseItem).patches.single['held'],
      isFalse,
    );
    expect(
      run(
        'refund',
        LocalKdsCommandType.refundItem,
        target: LocalKdsCommandTarget(
          detailId: line.detailId,
          fromQueue: 'pending_prep',
        ),
        quantity: 1,
      ).patches.single['refunded_quantity'],
      1,
    );
    final completed = run(
      'complete',
      LocalKdsCommandType.completeOrder,
      target: LocalKdsCommandTarget(orderId: order.orderId),
    );
    expect(completed.orderSummary?['completed'], isTrue);
    expect(completed.patches.single['completed_at_ms'], isA<int>());
    expect(
      run(
        'archive',
        LocalKdsCommandType.archiveOrder,
        target: LocalKdsCommandTarget(orderId: order.orderId),
      ).orderSummary?['archived'],
      isTrue,
    );
  });

  test('merged advance distributes total FIFO and splits cloud aggregates', () {
    final first = seedOrder(createdAtMs: 1000);
    final second = seedOrder(createdAtMs: 1001);
    final lines = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines;

    final result = service.execute(
      LocalKdsCommand(
        commandId: 'merged-advance',
        type: LocalKdsCommandType.advanceItem,
        shopId: 1,
        target: LocalKdsCommandTarget(
          detailIds: lines.map((line) => line.detailId).toList(),
          fromQueue: 'pending_prep',
        ),
        quantity: 3,
        payload: {
          'expected_revisions': {
            for (final line in lines) '${line.detailId}': line.localRevision,
          },
        },
        occurredAtMs: 3000,
      ),
    );

    expect(result.patches.map((patch) => patch['prep_remaining']), [0, 1]);
    expect(result.patches.map((patch) => patch['order_id']), [
      first.orderId,
      second.orderId,
    ]);
    final mergedEvents = database
        .readPendingCloudEvents()
        .where((event) => event.eventType == 'kds_state_changed')
        .toList();
    expect(mergedEvents, hasLength(2));
    expect(mergedEvents.map((event) => event.aggregateKey).toSet(), {
      'order:${first.orderId}',
      'order:${second.orderId}',
    });
    expect(
      mergedEvents.every(
        (event) =>
            event.payload['operation_type'] == 'advance_item' &&
            event.payload['local_order_id'] is int &&
            event.payload['order_revision'] is int &&
            (event.payload['orders'] as List).length == 1 &&
            (event.payload['lines'] as List).length == 1 &&
            event.payload['dish_availability'] is List,
      ),
      isTrue,
    );
    for (final event in mergedEvents) {
      _expectStateChangedContract(event);
    }
  });

  test(
    'merged serving completion gives each order a unique operation and an independent print lane',
    () {
      seedOrder(createdAtMs: 1000);
      seedOrder(createdAtMs: 1001);
      final prepLines = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines;
      for (final line in prepLines) {
        service.execute(
          LocalKdsCommand(
            commandId: 'prep-${line.orderId}',
            type: LocalKdsCommandType.advanceItem,
            shopId: 1,
            target: LocalKdsCommandTarget(
              detailId: line.detailId,
              fromQueue: 'pending_prep',
            ),
            quantity: 2,
            expectedRevision: line.localRevision,
            occurredAtMs: 2000 + line.orderId,
          ),
        );
      }
      final cookLines = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
          .lines;
      final mergedCommandId = List.filled(128, 'm').join();

      service.execute(
        LocalKdsCommand(
          commandId: mergedCommandId,
          type: LocalKdsCommandType.advanceItem,
          shopId: 1,
          target: LocalKdsCommandTarget(
            detailIds: cookLines.map((line) => line.detailId).toList(),
            fromQueue: 'pending_cook',
          ),
          quantity: 3,
          payload: {
            'expected_revisions': {
              for (final line in cookLines)
                '${line.detailId}': line.localRevision,
            },
          },
          occurredAtMs: 3000,
        ),
      );

      final cookingEvents = database
          .readPendingCloudEvents()
          .where((event) => event.createdAtMs == 3000)
          .toList(growable: false);
      expect(
        cookingEvents.where(
          (event) => event.eventType == cashierServeTicketPrintEventType,
        ),
        isEmpty,
      );

      final serveLines = database
          .readWorkflowBoard(shopId: 1, queue: 'ready_serve')
          .lines;
      service.execute(
        LocalKdsCommand(
          commandId: 'merged-serve',
          type: LocalKdsCommandType.advanceItem,
          shopId: 1,
          target: LocalKdsCommandTarget(
            detailIds: serveLines.map((line) => line.detailId).toList(),
            fromQueue: 'ready_serve',
          ),
          quantity: 3,
          payload: {
            'expected_revisions': {
              for (final line in serveLines)
                '${line.detailId}': line.localRevision,
            },
          },
          occurredAtMs: 3100,
        ),
      );

      final commandEvents = database
          .readPendingCloudEvents()
          .where((event) => event.createdAtMs == 3100)
          .toList(growable: false);
      final stateEvents = commandEvents
          .where((event) => event.eventType == 'kds_state_changed')
          .toList(growable: false);
      final printEvents = commandEvents
          .where((event) => event.eventType == cashierServeTicketPrintEventType)
          .toList(growable: false);

      expect(stateEvents, hasLength(2));
      expect(printEvents, hasLength(2));
      final operationIds = stateEvents
          .map((event) => '${event.payload['operation_id']}')
          .toSet();
      expect(operationIds, hasLength(2));
      expect(operationIds.every((id) => id.length <= 128), isTrue);
      expect(
        commandEvents.every((event) => event.eventId.length <= 128),
        isTrue,
      );
      expect(printEvents.map((event) => event.aggregateKey).toSet(), {
        for (final event in stateEvents) 'serve-print:${event.aggregateKey}',
      });

      for (final stateEvent in stateEvents) {
        final localOrderId = stateEvent.payload['local_order_id'] as int;
        final creationEvent = database.readPendingCloudEvents().firstWhere(
          (event) =>
              event.eventType == 'order_created' &&
              event.payload['local_order_id'] == localOrderId,
        );
        final mappings = <int, int>{
          for (final raw in creationEvent.payload['lines'] as List)
            (raw as Map)['local_detail_id'] as int:
                10000 + (raw['local_detail_id'] as int),
        };
        database.applyCloudAckAndMarkDelivered(
          creationEvent,
          CashierCloudEventAck(
            eventId: creationEvent.eventId,
            cloudOrderId: 9000 + localOrderId,
            cloudOrderNo: 'CLOUD-$localOrderId',
            detailMappings: mappings,
          ),
          deliveredAtMs: 3150,
        );
      }

      database.markCloudEventDeadLetter(
        stateEvents.first.eventId,
        updatedAtMs: 3200,
        error: 'state replication failed',
      );
      final dueBatches = database.readDueCloudEventBatches(nowMs: 4000);
      expect(
        dueBatches
            .take(2)
            .every(
              (batch) =>
                  batch.first.eventType == cashierServeTicketPrintEventType,
            ),
        isTrue,
      );
      final duePrintIds = dueBatches
          .expand((batch) => batch)
          .where((event) => event.eventType == cashierServeTicketPrintEventType)
          .map((event) => event.eventId)
          .toSet();
      expect(duePrintIds, printEvents.map((event) => event.eventId).toSet());
    },
  );

  test('merged advance rejects mixed dishes in one bucket', () {
    seedOrder(createdAtMs: 1000);
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '9',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1001,
        lines: [
          CashierOrderLineDraft(
            dishId: 202,
            dishName: '吊龙',
            specification: '',
            unit: '份',
            quantity: 2,
          ),
        ],
      ),
      eventId: 'mixed-order',
    );
    final lines = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines;
    final before = database.readPendingCloudEvents().length;

    expect(
      () => service.execute(
        LocalKdsCommand(
          commandId: 'mixed-advance',
          type: LocalKdsCommandType.advanceItem,
          shopId: 1,
          target: LocalKdsCommandTarget(
            detailIds: lines.map((line) => line.detailId).toList(),
            fromQueue: 'pending_prep',
          ),
          quantity: 2,
          occurredAtMs: 3000,
        ),
      ),
      throwsA(isA<CashierKdsValidation>()),
    );
    expect(database.readPendingCloudEvents(), hasLength(before));
    expect(
      database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .every((line) => line.prepRemaining == 2),
      isTrue,
    );
  });

  test('merged advance rejects mixed fulfillment buckets', () {
    seedOrder(createdAtMs: 1000);
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '打包',
        fulfillmentType: 'takeout',
        remark: '',
        createdAtMs: 1001,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 2,
          ),
        ],
      ),
      eventId: 'takeout-order',
    );
    final lines = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines;

    expect(
      () => service.execute(
        LocalKdsCommand(
          commandId: 'mixed-fulfillment',
          type: LocalKdsCommandType.advanceItem,
          shopId: 1,
          target: LocalKdsCommandTarget(
            detailIds: lines.map((line) => line.detailId).toList(),
            fromQueue: 'pending_prep',
          ),
          quantity: 2,
          occurredAtMs: 3000,
        ),
      ),
      throwsA(isA<CashierKdsValidation>()),
    );
  });

  test('partial advance and revoke split one line across queue views', () {
    seedOrder();
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    service.execute(
      LocalKdsCommand(
        commandId: 'partial-prep',
        type: LocalKdsCommandType.advanceItem,
        shopId: 1,
        target: LocalKdsCommandTarget(
          detailId: line.detailId,
          fromQueue: 'pending_prep',
        ),
        quantity: 1,
        expectedRevision: line.localRevision,
        occurredAtMs: 2000,
      ),
    );
    expect(
      database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single
          .quantity,
      1,
    );
    expect(
      database
          .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
          .lines
          .single
          .quantity,
      1,
    );
    service.execute(
      LocalKdsCommand(
        commandId: 'undo-prep',
        type: LocalKdsCommandType.revokeItem,
        shopId: 1,
        target: LocalKdsCommandTarget(
          detailId: line.detailId,
          fromQueue: 'pending_cook',
        ),
        quantity: 1,
        expectedRevision: database
            .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
            .lines
            .single
            .localRevision,
        occurredAtMs: 2100,
      ),
    );
    expect(
      database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single
          .quantity,
      2,
    );
    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_cook').lines,
      isEmpty,
    );
  });

  test('archive clear deletes only 30-day cloud-delivered aggregates', () {
    final order = seedOrder();
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    service.execute(
      LocalKdsCommand(
        commandId: 'old-complete',
        type: LocalKdsCommandType.completeOrder,
        shopId: 1,
        target: LocalKdsCommandTarget(orderId: order.orderId),
        expectedRevision: currentOrderRevision(order.orderId),
        occurredAtMs: 1100,
      ),
    );
    service.execute(
      LocalKdsCommand(
        commandId: 'old-archive',
        type: LocalKdsCommandType.archiveOrder,
        shopId: 1,
        target: LocalKdsCommandTarget(orderId: order.orderId),
        expectedRevision: currentOrderRevision(order.orderId),
        occurredAtMs: 1200,
      ),
    );
    var due = database.readDueCloudEvents(nowMs: 2000).single;
    database.applyCloudAckAndMarkDelivered(
      due,
      CashierCloudEventAck(
        eventId: due.eventId,
        cloudOrderId: 9001,
        cloudOrderNo: 'CLOUD-1',
        detailMappings: {line.detailId: 9901},
      ),
      deliveredAtMs: 2000,
    );
    while (database.readDueCloudEvents(nowMs: 2000).isNotEmpty) {
      due = database.readDueCloudEvents(nowMs: 2000).single;
      database.applyCloudAckAndMarkDelivered(
        due,
        CashierCloudEventAck(eventId: due.eventId),
        deliveredAtMs: 2000,
      );
    }
    final outboxBefore = database.readPendingCloudEvents().length;

    final cleared = service.execute(
      LocalKdsCommand(
        commandId: 'eligible-clear',
        type: LocalKdsCommandType.archiveClear,
        shopId: 1,
        target: const LocalKdsCommandTarget(),
        occurredAtMs: const Duration(days: 31).inMilliseconds,
      ),
    );

    expect(cleared.orderSummary?['cleared_count'], 1);
    expect(database.readPendingCloudEvents(), hasLength(outboxBefore));
    expect(database.readWorkflowBoard(shopId: 1, queue: 'done').lines, isEmpty);
  });

  test('dish_availability stock=-1 sentinel is converted to null for cloud', () {
    // Seed catalog: dish 101 unlimited (stock=-1), dish 202 limited (stock=50)
    database.replaceDishCatalog(
      shopId: 1,
      updatedAtMs: 4000,
      items: const [
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '油边王',
          unit: '串',
          sequence: 1,
          stock: -1,
        ),
        CashierDishCatalogItem(
          dishId: 202,
          dishName: '羊肉串',
          unit: '串',
          sequence: 2,
          stock: 50,
        ),
      ],
    );

    // Create an order with both dishes
    final receipt = database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '10',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 5000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
          CashierOrderLineDraft(
            dishId: 202,
            dishName: '羊肉串',
            specification: '',
            unit: '串',
            quantity: 3,
          ),
        ],
      ),
      eventId: 'sentinel-order',
    );

    final lines = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .where((line) => line.orderId == receipt.orderId && line.dishId == 101)
        .toList();
    expect(lines, hasLength(1));

    service.execute(
      LocalKdsCommand(
        commandId: 'sentinel-advance',
        type: LocalKdsCommandType.advanceItem,
        shopId: 1,
        target: LocalKdsCommandTarget(
          detailId: lines.single.detailId,
          fromQueue: 'pending_prep',
        ),
        quantity: 1,
        expectedRevision: lines.single.localRevision,
        occurredAtMs: 6000,
      ),
    );

    final event = database.readPendingCloudEvents().lastWhere(
      (e) => e.eventId == 'sentinel-advance',
    );
    final availability = event.payload['dish_availability'] as List<dynamic>;

    final dish101 = availability.cast<Map>().firstWhere(
      (item) => item['dish_id'] == 101,
    );
    final dish202 = availability.cast<Map>().firstWhere(
      (item) => item['dish_id'] == 202,
    );

    // stock=-1 (unlimited) must be converted to null for the cloud
    expect(
      dish101['stock'],
      isNull,
      reason: 'stock=-1 sentinel must not leak to cloud',
    );
    // stock=50 (limited) must be preserved as-is
    expect(dish202['stock'], 50);
  });
}

void _expectStateChangedContract(CashierCloudEvent event) {
  expect(event.eventType, 'kds_state_changed');
  final payload = event.payload;
  expect('${payload['device_code']}'.trim(), isNotEmpty);
  expect(payload['local_order_id'], isA<int>());
  expect(payload['order_revision'], isA<int>());
  expect(payload['operation_type'], isNotEmpty);
  expect(payload['orders'], isA<List>());
  expect(payload['lines'], isA<List>());
  expect(payload['dish_availability'], isA<List>());
  for (final raw in payload['dish_availability'] as List) {
    final item = raw as Map;
    final stock = item['stock'];
    if (stock != null) {
      expect(
        stock as int,
        greaterThanOrEqualTo(0),
        reason: 'stock sentinel (-1) must not leak to cloud',
      );
    }
  }
  final order = (payload['orders'] as List).single as Map;
  expect(order['order_id'], payload['local_order_id']);
  expect(order['local_order_id'], payload['local_order_id']);
  expect(order['order_revision'], payload['order_revision']);
  expect(order['status'], isNotEmpty);
  for (final raw in payload['lines'] as List) {
    final line = raw as Map;
    expect(line['detail_id'], isA<int>());
    expect(line['local_detail_id'], line['detail_id']);
    expect(line['local_order_id'], line['order_id']);
    expect(line['local_revision'], isA<int>());
    expect(line['removed'], isA<bool>());
    final prep = line['prep_remaining'] as int;
    final cook = line['cook_remaining'] as int;
    final ready = line['ready_remaining'] as int;
    final active =
        (line['line_quantity'] as int) - (line['refunded_quantity'] as int);
    expect(
      0 <= prep && prep <= cook && cook <= ready && ready <= active,
      isTrue,
    );
  }
}
