import 'dart:io';

import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late CashierKdsDatabase database;

  setUp(() {
    database = CashierKdsDatabase.inMemory();
  });

  tearDown(() {
    database.close();
  });

  test(
    'pairing an online device code twice is rejected, offline takeover allowed',
    () {
      const baseMs = 1000000;
      database.createPairingCode(
        shopId: 1,
        codeHash: 'hash-a',
        expiresAtMs: baseMs + 600000,
        createdAtMs: baseMs,
      );
      database.pairDevice(
        pairingCodeHash: 'hash-a',
        tokenHash: 'token-old',
        deviceCode: 'KDS-DUP',
        deviceName: '后厨一屏',
        screenTag: 'workflow_board',
        workflows: const ['prep', 'cook', 'serve'],
        nowMs: baseMs,
      );

      database.createPairingCode(
        shopId: 1,
        codeHash: 'hash-b',
        expiresAtMs: baseMs + 600000,
        createdAtMs: baseMs,
      );
      // 60s 后旧设备仍在线（心跳 90s 容忍内）：同码新 token 配对被拒绝
      expect(
        () => database.pairDevice(
          pairingCodeHash: 'hash-b',
          tokenHash: 'token-new',
          deviceCode: 'KDS-DUP',
          deviceName: '后厨二屏',
          screenTag: 'workflow_board',
          workflows: const ['prep', 'cook', 'serve'],
          nowMs: baseMs + 60000,
        ),
        throwsA(isA<CashierKdsValidation>()),
      );
      // 配对码未被消耗，旧设备 token 仍有效
      expect(database.authenticateDevice('token-old'), isNotNull);

      // 旧设备离线（心跳超 90s）后允许接管恢复
      database.pairDevice(
        pairingCodeHash: 'hash-b',
        tokenHash: 'token-new',
        deviceCode: 'KDS-DUP',
        deviceName: '后厨二屏',
        screenTag: 'workflow_board',
        workflows: const ['prep', 'cook', 'serve'],
        nowMs: baseMs + 120000,
      );
      expect(database.authenticateDevice('token-new'), isNotNull);
      expect(database.authenticateDevice('token-old'), isNull);
    },
  );

  test('print on advance is disabled by default and persisted per shop', () {
    expect(database.readPrintOnAdvance(shopId: 1), isFalse);
    expect(database.readLanConfigVersion(1), 0);

    final change = database.setPrintOnAdvance(
      shopId: 1,
      enabled: true,
      updatedAtMs: 1000,
    );

    expect(change, isNotNull);
    expect(database.readPrintOnAdvance(shopId: 1), isTrue);
    expect(database.readPrintOnAdvance(shopId: 2), isFalse);
    expect(database.readLanConfigVersion(1), change!.configVersion);
    expect(
      database.setPrintOnAdvance(shopId: 1, enabled: true, updatedAtMs: 2000),
      isNull,
    );
  });

  test('creating a local order atomically creates its cloud outbox event', () {
    final receipt = database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '18',
        fulfillmentType: 'dine_in',
        remark: '整单少辣',
        createdAtMs: 1000,
        lines: const [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '微辣',
            unit: '串',
            quantity: 2,
          ),
        ],
      ),
      eventId: 'order-event-1',
    );

    final board = database.readWorkflowBoard(shopId: 1, queue: 'pending_prep');
    final outbox = database.readPendingCloudEvents();

    expect(receipt.orderId, greaterThan(0));
    expect(receipt.orderNo, isNotEmpty);
    expect(board.lines, hasLength(1));
    expect(board.lines.single.tableNumber, '18');
    expect(board.lines.single.prepRemaining, 2);
    expect(outbox, hasLength(1));
    expect(outbox.single.eventId, 'order-event-1');
    expect(outbox.single.eventType, 'order_created');
    expect(outbox.single.aggregateKey, 'order:${receipt.orderId}');
    expect(outbox.single.aggregateSequence, 1);
    expect(
      (outbox.single.payload['lines'] as List).single,
      containsPair('local_detail_id', board.lines.single.detailId),
    );
  });

  test('advancing a line updates workflow and outbox in one transaction', () {
    final order = database.createOrder(
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
          ),
        ],
      ),
      eventId: 'order-event-1',
    );
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;

    final patch = database.advanceLine(
      shopId: 1,
      detailId: line.detailId,
      fromQueue: 'pending_prep',
      quantity: 2,
      operationId: 'advance-event-1',
      expectedRevision: line.localRevision,
      occurredAtMs: 2000,
    );

    expect(patch.workflowQueue, 'pending_cook');
    expect(patch.prepRemaining, 0);
    expect(patch.cookRemaining, 2);
    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
      isEmpty,
    );
    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_cook').lines,
      hasLength(1),
    );
    expect(database.readPendingCloudEvents(), hasLength(2));
    final events = database.readPendingCloudEvents();
    expect(events.map((event) => event.aggregateKey).toSet(), {
      'order:${order.orderId}',
    });
    expect(events.map((event) => event.aggregateSequence), [1, 2]);
    expect(order.orderId, patch.orderId);
  });

  test(
    'serving completion queues its exact quantity for serve ticket printing',
    () {
      final order = database.createOrder(
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
            ),
          ],
        ),
        eventId: 'order-event-serve',
      );

      var line = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;
      database.advanceLine(
        shopId: 1,
        detailId: line.detailId,
        fromQueue: 'pending_prep',
        quantity: 2,
        operationId: 'advance-prep',
        expectedRevision: line.localRevision,
        occurredAtMs: 2000,
      );
      line = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
          .lines
          .single;
      database.advanceLine(
        shopId: 1,
        detailId: line.detailId,
        fromQueue: 'pending_cook',
        quantity: 1,
        operationId: 'advance-cook',
        expectedRevision: line.localRevision,
        occurredAtMs: 3000,
      );

      expect(
        database.readPendingCloudEvents().where(
          (event) => event.eventType == cashierServeTicketPrintEventType,
        ),
        isEmpty,
        reason: 'moving from pending cook to ready serve must not print',
      );

      line = database
          .readWorkflowBoard(shopId: 1, queue: 'ready_serve')
          .lines
          .single;
      database.advanceLine(
        shopId: 1,
        detailId: line.detailId,
        fromQueue: 'ready_serve',
        quantity: 1,
        operationId: 'advance-serve',
        expectedRevision: line.localRevision,
        occurredAtMs: 3500,
      );

      final events = database.readPendingCloudEvents();
      final printEvent = events.last;
      expect(printEvent.eventId, 'advance-serve:serve-print');
      expect(printEvent.eventType, 'serve_ticket_print_requested');
      expect(printEvent.aggregateKey, 'serve-print:order:${order.orderId}');
      expect(printEvent.aggregateSequence, 1);
      expect(printEvent.payload['lines'], [
        {'local_detail_id': line.detailId, 'quantity': 1},
      ]);
      expect(
        database
            .readDueCloudEventBatches(nowMs: 4000)
            .expand((batch) => batch)
            .where(
              (event) => event.eventType == cashierServeTicketPrintEventType,
            ),
        isEmpty,
        reason: 'printing must wait until local detail ids have cloud mappings',
      );

      database.applyCloudAckAndMarkDelivered(
        events.first,
        CashierCloudEventAck(
          eventId: events.first.eventId,
          cloudOrderId: 9001,
          cloudOrderNo: 'CLOUD-9001',
          detailMappings: {line.detailId: 9123},
        ),
        deliveredAtMs: 5000,
      );
      for (final stateEvent in events.where(
        (event) => event.eventType == 'kds_state_changed',
      )) {
        database.applyCloudAckAndMarkDelivered(
          stateEvent,
          CashierCloudEventAck(eventId: stateEvent.eventId),
          deliveredAtMs: 5000,
        );
      }
      final duePrintEvent = database
          .readDueCloudEventBatches(nowMs: 5000)
          .single
          .single;
      expect(duePrintEvent.payload['lines'], [
        {'local_detail_id': line.detailId, 'detail_id': 9123, 'quantity': 1},
      ]);
    },
  );

  test('disabled serve printing does not queue a print request', () {
    database.applyConfigSnapshot(
      const CashierKdsConfigSnapshot(
        shopId: 1,
        version: 1,
        payload: {
          'cashier_authority': {
            'cashier_device_code': 'cashier-a',
            'enforcement': 'primary_only',
          },
          'workflow': {'serve_print_enabled': 0},
        },
        updatedAtMs: 1000,
        expiresAtMs: 100000,
      ),
    );
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '8',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1100,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'order-print-disabled',
    );
    var line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: line.detailId,
      fromQueue: 'pending_prep',
      quantity: 1,
      operationId: 'prep-print-disabled',
      expectedRevision: line.localRevision,
      occurredAtMs: 1200,
    );
    line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: line.detailId,
      fromQueue: 'pending_cook',
      quantity: 1,
      operationId: 'cook-print-disabled',
      expectedRevision: line.localRevision,
      occurredAtMs: 1300,
    );
    line = database
        .readWorkflowBoard(shopId: 1, queue: 'ready_serve')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: line.detailId,
      fromQueue: 'ready_serve',
      quantity: 1,
      operationId: 'serve-print-disabled',
      expectedRevision: line.localRevision,
      occurredAtMs: 1400,
    );

    expect(
      database.readPendingCloudEvents().where(
        (event) => event.eventType == cashierServeTicketPrintEventType,
      ),
      isEmpty,
    );
  });

  test('replaying an operation id is idempotent', () {
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '3',
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
          ),
        ],
      ),
      eventId: 'order-event-1',
    );
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;

    final first = database.advanceLine(
      shopId: 1,
      detailId: line.detailId,
      fromQueue: 'pending_prep',
      quantity: 1,
      operationId: 'advance-event-1',
      expectedRevision: line.localRevision,
      occurredAtMs: 2000,
    );
    final duplicate = database.advanceLine(
      shopId: 1,
      detailId: line.detailId,
      fromQueue: 'pending_prep',
      quantity: 1,
      operationId: 'advance-event-1',
      expectedRevision: line.localRevision,
      occurredAtMs: 2100,
    );

    expect(duplicate.localRevision, first.localRevision);
    expect(duplicate.prepRemaining, 1);
    expect(first.duplicate, isFalse);
    expect(duplicate.duplicate, isTrue);
    expect(database.readPendingCloudEvents(), hasLength(2));
  });

  test(
    'replaying an order client id returns the original order and outbox',
    () {
      const draft = CashierOrderDraft(
        shopId: 1,
        tableNumber: '18',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      );

      final first = database.createOrder(draft, eventId: 'client-order-1');
      final duplicate = database.createOrder(draft, eventId: 'client-order-1');

      expect(duplicate.orderId, first.orderId);
      expect(duplicate.orderNo, first.orderNo);
      expect(first.duplicate, isFalse);
      expect(duplicate.duplicate, isTrue);
      expect(database.readPendingCloudEvents(), hasLength(1));
      expect(
        database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
        hasLength(1),
      );
    },
  );

  test('same order event id with different payload is rejected', () {
    const line = CashierOrderLineDraft(
      dishId: 101,
      dishName: '油边王',
      specification: '',
      unit: '串',
      quantity: 1,
    );
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '18',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [line],
      ),
      eventId: 'same-client-id',
    );

    expect(
      () => database.createOrder(
        const CashierOrderDraft(
          shopId: 1,
          tableNumber: '19',
          fulfillmentType: 'dine_in',
          remark: '',
          createdAtMs: 2000,
          lines: [line],
        ),
        eventId: 'same-client-id',
      ),
      throwsA(isA<CashierKdsValidation>()),
    );
    expect(database.readPendingCloudEvents(), hasLength(1));
  });

  test('same order outbox events are released in aggregate sequence order', () {
    final order = database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '6',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'order-event-1',
    );
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: line.detailId,
      fromQueue: 'pending_prep',
      quantity: 1,
      operationId: 'advance-event-1',
      expectedRevision: line.localRevision,
      occurredAtMs: 2000,
    );

    expect(database.readDueCloudEvents(nowMs: 2000), hasLength(1));
    final createdEvent = database.readDueCloudEvents(nowMs: 2000).single;
    database.applyCloudAckAndMarkDelivered(
      createdEvent,
      const CashierCloudEventAck(
        eventId: 'order-event-1',
        cloudOrderId: 9001,
        cloudOrderNo: 'CLOUD-9001',
        detailMappings: {1: 9901},
      ),
      deliveredAtMs: 2100,
    );
    final next = database.readDueCloudEvents(nowMs: 2200);

    expect(next.single.eventId, 'advance-event-1');
    expect(next.single.aggregateKey, 'order:${order.orderId}');
    expect(next.single.aggregateSequence, 2);
  });

  test('revision conflict leaves line and outbox unchanged', () {
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '3',
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
          ),
        ],
      ),
      eventId: 'order-event-1',
    );
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;

    expect(
      () => database.advanceLine(
        shopId: 1,
        detailId: line.detailId,
        fromQueue: 'pending_prep',
        quantity: 1,
        operationId: 'advance-event-1',
        expectedRevision: 99,
        occurredAtMs: 2000,
      ),
      throwsA(isA<CashierKdsConflict>()),
    );

    final unchanged = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    expect(unchanged.prepRemaining, 2);
    expect(database.readPendingCloudEvents(), hasLength(1));
  });

  test('dish catalog replacement preserves backend display order', () {
    database.replaceDishCatalog(
      shopId: 1,
      updatedAtMs: 2000,
      items: const [
        CashierDishCatalogItem(
          dishId: 202,
          dishName: '第二道菜',
          unit: '份',
          sequence: 1,
        ),
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '第一道菜',
          unit: '串',
          sequence: 0,
        ),
      ],
    );

    final catalog = database.readDishCatalog(shopId: 1);

    expect(catalog.map((item) => item.dishId), [101, 202]);
    expect(catalog.map((item) => item.sequence), [0, 1]);
  });

  test('catalog structure changes advance the LAN config version once', () {
    const initial = [
      CashierDishCatalogItem(
        dishId: 101,
        dishName: '油边王',
        unit: '串',
        sequence: 0,
        categoryId: 10,
        categoryName: '肉串',
        categorySequence: 1,
        dishSequence: 1,
      ),
    ];

    final first = database.replaceDishCatalog(
      shopId: 1,
      items: initial,
      updatedAtMs: 1000,
    );
    final availabilityOnly = database.replaceDishCatalog(
      shopId: 1,
      items: const [
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '油边王',
          unit: '串',
          sequence: 0,
          categoryId: 10,
          categoryName: '肉串',
          categorySequence: 1,
          dishSequence: 1,
          stock: 20,
        ),
      ],
      updatedAtMs: 1100,
    );
    final reordered = database.replaceDishCatalog(
      shopId: 1,
      items: const [
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '油边王',
          unit: '串',
          sequence: 0,
          categoryId: 10,
          categoryName: '肉串',
          categorySequence: 2,
          dishSequence: 1,
        ),
      ],
      updatedAtMs: 1200,
    );

    expect(first?.configVersion, 1);
    expect(availabilityOnly, isNull);
    expect(reordered?.configVersion, 2);
    expect(reordered?.eventSeq, greaterThan(first!.eventSeq));
    expect(database.readLanConfigVersion(1), 2);
  });

  test('creating a KDS order does not validate or deduct cached stock', () {
    database.replaceDishCatalog(
      shopId: 1,
      updatedAtMs: 900,
      items: const [
        CashierDishCatalogItem(
          dishId: 101,
          dishName: '油边王',
          unit: '串',
          sequence: 0,
          stock: 2,
        ),
      ],
    );
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '1',
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
          ),
        ],
      ),
      eventId: 'order-event-1',
    );

    final unchanged = database.readDishCatalog(shopId: 1).single;
    expect(unchanged.stock, 2);
    expect(unchanged.soldOut, isFalse);
    expect(database.readPendingCloudEvents(), hasLength(1));
  });

  test('cloud-confirmed order is local-only and keeps cloud identity', () {
    final receipt = database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '18',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'cloud-order-9001',
      cloudOrderId: 9001,
      cloudOrderNo: 'CLOUD-9001',
      enqueueCloudEvent: false,
    );

    expect(receipt.orderNo, 'CLOUD-9001');
    expect(database.resolveCloudOrderId(1, receipt.orderId), 9001);
    expect(database.resolveCloudOrderNo(1, receipt.orderNo), 'CLOUD-9001');
    expect(database.readPendingCloudEvents(), isEmpty);
    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
      hasLength(1),
    );
  });

  test(
    'migration discards premature serve prints and resequences remaining outbox',
    () {
      database.close();
      final directory = Directory.systemTemp.createTempSync(
        'cashier-kds-test-',
      );
      final path = '${directory.path}${Platform.pathSeparator}legacy.sqlite';
      final legacy = sqlite3.open(path);
      legacy.execute('''
      CREATE TABLE cloud_outbox (
        event_id TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        event_type TEXT NOT NULL,
        aggregate_key TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        state TEXT NOT NULL DEFAULT 'pending',
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
      legacy.execute(
        'INSERT INTO cloud_outbox VALUES '
        "('event-1', 1, 'order_created', 'order:1', '{}', 'pending', 0, 1, 1, 1), "
        "('event-2', 1, 'kds_advance_item', 'order:1', '{}', 'pending', 0, 2, 2, 2), "
        "('event-3', 1, 'serve_ticket_print_requested', 'order:1', '{\"lines\":[]}', 'pending', 0, 3, 3, 3)",
      );
      legacy.close();

      database = CashierKdsDatabase.open(path);
      final events = database.readPendingCloudEvents();

      expect(
        events.map((event) => (event.aggregateKey, event.aggregateSequence)),
        [('order:1', 1), ('order:1', 2)],
      );
      database.close();
      directory.deleteSync(recursive: true);
      database = CashierKdsDatabase.inMemory();
    },
  );

  test(
    'migration keeps ready-serve print events across later app launches',
    () {
      database.close();
      final directory = Directory.systemTemp.createTempSync(
        'cashier-kds-test-',
      );
      final path = '${directory.path}${Platform.pathSeparator}current.sqlite';
      database = CashierKdsDatabase.open(path);
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
              quantity: 1,
            ),
          ],
        ),
        eventId: 'reopen-order',
      );
      for (final queue in ['pending_prep', 'pending_cook', 'ready_serve']) {
        final line = database
            .readWorkflowBoard(shopId: 1, queue: queue)
            .lines
            .single;
        database.advanceLine(
          shopId: 1,
          detailId: line.detailId,
          fromQueue: queue,
          quantity: 1,
          operationId: 'reopen-$queue',
          expectedRevision: line.localRevision,
          occurredAtMs: line.localRevision * 1000,
        );
      }
      database.close();

      database = CashierKdsDatabase.open(path);
      expect(
        database.readPendingCloudEvents().where(
          (event) => event.eventType == cashierServeTicketPrintEventType,
        ),
        hasLength(1),
      );
      database.close();
      directory.deleteSync(recursive: true);
      database = CashierKdsDatabase.inMemory();
    },
  );

  test('outbox sequence migration runs once and preserves later sequences', () {
    database.close();
    final directory = Directory.systemTemp.createTempSync('cashier-kds-test-');
    final path = '${directory.path}${Platform.pathSeparator}sequence.sqlite';
    database = CashierKdsDatabase.open(path);
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '9',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'sequence-order',
    );
    database.close();
    final raw = sqlite3.open(path);
    raw.execute(
      "UPDATE cloud_outbox SET aggregate_sequence = 99 WHERE event_id = 'sequence-order'",
    );
    raw.close();

    database = CashierKdsDatabase.open(path);
    expect(database.readPendingCloudEvents().single.aggregateSequence, 99);
    database.close();
    directory.deleteSync(recursive: true);
    database = CashierKdsDatabase.inMemory();
  });

  test('audited manual retry requeues one dead letter immediately', () {
    database.createOrder(
      const CashierOrderDraft(
        shopId: 1,
        tableNumber: '18',
        fulfillmentType: 'dine_in',
        remark: '',
        createdAtMs: 1000,
        lines: [
          CashierOrderLineDraft(
            dishId: 101,
            dishName: '油边王',
            specification: '',
            unit: '串',
            quantity: 1,
          ),
        ],
      ),
      eventId: 'order-event-retry',
    );
    database.markCloudEventDeadLetter(
      'order-event-retry',
      updatedAtMs: 1100,
      error: 'legacy payload rejected',
    );
    expect(database.readOutboxStats().lastError, 'legacy payload rejected');

    database.retryCloudEvent(
      'order-event-retry',
      actorDeviceCode: 'CASHIER-A',
      reason: 'operator confirmed payload is now accepted',
      nowMs: 1200,
    );

    expect(database.readOutboxStats().deadLetter, 0);
    expect(database.readOutboxStats().pending, 1);
    expect(
      database.readDueCloudEvents(nowMs: 1200).single.eventId,
      'order-event-retry',
    );
  });

  test(
    'pickup and takeout fulfillment types are parsed, tracked, and advance_order works',
    () {
      final receipt = database.applyCloudDeliveryEvent({
        'eventId': 'cloud-delivery-pickup-1',
        'cursor': 100,
        'eventType': 'ORDER_READY',
        'occurredAtMs': 2000,
        'projection': {
          'shopId': 1,
          'orderId': 88801,
          'orderNo': 'A01',
          'tableNumber': 'A01',
          'fulfillmentType': 'PICKUP',
          'orderRemark': '打包带走',
          'numberOfDiners': 1,
          'projectionVersion': 1,
          'lines': [
            {
              'detailId': 9901,
              'dishId': 201,
              'dishName': '烤生蚝',
              'quantity': 4,
              'remainingQuantity': 4,
              'refundedQuantity': 0,
              'is_combo': 1,
              'combo_name': '生蚝套餐',
              'combo_id': 501,
            },
            {
              'detailId': 9902,
              'dishId': 202,
              'dishName': '羊肉串',
              'quantity': 10,
              'remainingQuantity': 10,
              'refundedQuantity': 0,
              'held': true,
            },
          ],
        },
      });

      final board = database.readWorkflowBoard(
        shopId: 1,
        queue: 'pending_prep',
      );
      expect(board.lines, hasLength(2));
      final oysterLine = board.lines.firstWhere((l) => l.dishId == 201);
      expect(oysterLine.fulfillmentType, 'pickup');
      expect(oysterLine.isCombo, isTrue);
      expect(oysterLine.comboName, '生蚝套餐');
      expect(oysterLine.comboId, 501);
      expect(oysterLine.toApiJson()['fulfillment_bucket'], 'pickup');
      expect(oysterLine.toApiJson()['fulfillment_channel'], 'pickup');
      expect(oysterLine.toApiJson()['is_combo'], isTrue);

      // Test advance_order using cloud_order_id (88801)
      final advanceResult = database.executeKdsCommand(
        const LocalKdsCommand(
          commandId: 'cmd-advance-pickup',
          type: LocalKdsCommandType.advanceOrder,
          shopId: 1,
          target: LocalKdsCommandTarget(
            orderId: 88801,
            fromQueue: 'pending_prep',
          ),
          expectedRevision: 1,
          occurredAtMs: 2100,
        ),
      );

      expect(advanceResult.patches, hasLength(2));
      final cookBoard = database.readWorkflowBoard(
        shopId: 1,
        queue: 'pending_cook',
      );
      expect(cookBoard.lines, hasLength(1));
      expect(cookBoard.lines.single.dishId, 201);
      expect(cookBoard.lines.single.cookRemaining, 4);
      expect(cookBoard.lines.single.prepRemaining, 0);

      // order_details projection check
      final details = database.readOrderDetailsProjection(
        shopId: 1,
        orderIds: [receipt.orderId],
      );
      expect(details, hasLength(2));
      expect(details.first['fulfillment_type'], 'pickup');
      expect(details.first['fulfillment_channel'], 'pickup');
      expect(details.first['is_combo'], isTrue);
      // 行级队列标记（与云端 detail 一致）：未完成行保留队列与剩余量
      expect(details.first['doneLine'], 0);
      expect(details.first['workflowQueue'], isNotEmpty);
      expect(details.first['readyRemaining'], isA<int>());
      expect(details.first['prepRemaining'], isA<int>());
      expect(details.first['cookRemaining'], isA<int>());

      // completeOrder 后行级 done 标记翻转为 1、队列 done、剩余量清零
      database.executeKdsCommand(
        const LocalKdsCommand(
          commandId: 'cmd-complete-pickup',
          type: LocalKdsCommandType.completeOrder,
          shopId: 1,
          target: LocalKdsCommandTarget(orderId: 88801),
          expectedRevision: 2,
          occurredAtMs: 2200,
        ),
      );
      final doneDetails = database.readOrderDetailsProjection(
        shopId: 1,
        orderIds: [receipt.orderId],
      );
      expect(doneDetails.first['doneLine'], 1);
      expect(doneDetails.first['workflowQueue'], 'done');
      expect(doneDetails.first['readyRemaining'], 0);
      expect(doneDetails.first['prepRemaining'], 0);
      expect(doneDetails.first['cookRemaining'], 0);
    },
  );

  test(
    'clearSyncQueue discards pending, retrying, and dead-letter outbox events with audit record',
    () {
      database.createOrder(
        const CashierOrderDraft(
          shopId: 1,
          tableNumber: '18',
          fulfillmentType: 'dine_in',
          remark: '',
          createdAtMs: 1000,
          lines: [
            CashierOrderLineDraft(
              dishId: 101,
              dishName: '油边王',
              specification: '',
              unit: '串',
              quantity: 1,
            ),
          ],
        ),
        eventId: 'order-event-1',
      );
      database.createOrder(
        const CashierOrderDraft(
          shopId: 1,
          tableNumber: '19',
          fulfillmentType: 'dine_in',
          remark: '',
          createdAtMs: 1050,
          lines: [
            CashierOrderLineDraft(
              dishId: 102,
              dishName: '羊肉串',
              specification: '',
              unit: '串',
              quantity: 2,
            ),
          ],
        ),
        eventId: 'order-event-2',
      );

      database.markCloudEventDeadLetter(
        'order-event-2',
        updatedAtMs: 1100,
        error: 'fatal server error',
      );

      var stats = database.readOutboxStats();
      expect(stats.pending, 1);
      expect(stats.deadLetter, 1);

      final cleared = database.clearSyncQueue(
        actorDeviceCode: 'CASHIER-TEST',
        reason: '管理员一键清空同步队列',
        nowMs: 1200,
      );

      expect(cleared, 2);
      stats = database.readOutboxStats();
      expect(stats.pending, 0);
      expect(stats.retrying, 0);
      expect(stats.deadLetter, 0);
      expect(stats.authPaused, 0);
      expect(database.readPendingCloudEvents(), isEmpty);
      expect(database.readDeadLetters(), isEmpty);
    },
  );

  test(
    'workflow board and queue counts honor the business-day window when provided',
    () {
      // 两个在制订单：一个在当前营业日窗口内，一个在窗口外（历史日）。
      final inWindow = database.createOrder(
        const CashierOrderDraft(
          shopId: 1,
          tableNumber: 'A1',
          fulfillmentType: 'dine_in',
          remark: '',
          createdAtMs: 5000,
          lines: [
            CashierOrderLineDraft(
              dishId: 201,
              dishName: '窗口内菜',
              specification: '',
              unit: '份',
              quantity: 2,
            ),
          ],
        ),
        eventId: 'order-in-window',
      );
      database.createOrder(
        const CashierOrderDraft(
          shopId: 1,
          tableNumber: 'B2',
          fulfillmentType: 'dine_in',
          remark: '',
          createdAtMs: 1000000,
          lines: [
            CashierOrderLineDraft(
              dishId: 202,
              dishName: '窗口外菜',
              specification: '',
              unit: '份',
              quantity: 3,
            ),
          ],
        ),
        eventId: 'order-out-window',
      );

      database.commitBusinessDayWindow(1, startMs: 1000, endMs: 60000);

      // 不传窗口：保持旧行为，两个订单都在。
      final noWindow = database.readWorkflowBoard(
        shopId: 1,
        queue: 'pending_prep',
      );
      expect(noWindow.lines, hasLength(2));
      expect(
        database.readQueueCounts(1)['pending_prep'],
        5,
      ); // 数量口径：SUM 可见量 2+3

      // 传窗口：只返回营业日窗口内的订单，历史日订单被过滤。
      final filtered = database.readWorkflowBoard(
        shopId: 1,
        queue: 'pending_prep',
        startMs: 1000,
        endMs: 60000,
      );
      expect(filtered.lines, hasLength(1));
      expect(filtered.lines.single.orderId, inWindow.orderId);
      expect(filtered.lines.single.tableNumber, 'A1');

      final counts = database.readQueueCounts(1, startMs: 1000, endMs: 60000);
      expect(counts['pending_prep'], 2); // 窗口内仅 A1（quantity=2）

      // 窗口无效（end <= start）时按不过滤处理，避免 KDS 空屏。
      final invalidWindow = database.readWorkflowBoard(
        shopId: 1,
        queue: 'pending_prep',
        startMs: 60000,
        endMs: 1000,
      );
      expect(invalidWindow.lines, hasLength(2));
    },
  );

  test('command fingerprint is canonical across JSON object key order', () {
    final first = CashierKdsDatabase.commandRequestFingerprint(7, {
      'command_id': 'same-id',
      'type': 'advance_item',
      'target': {'detail_id': 9, 'from_queue': 'pending_cook'},
    });
    final second = CashierKdsDatabase.commandRequestFingerprint(7, {
      'target': {'from_queue': 'pending_cook', 'detail_id': 9},
      'type': 'advance_item',
      'command_id': 'different-transport-id',
    });

    expect(first, second);
    expect(first, hasLength(64));
  });

  test(
    'legacy pending command migrates without loss and sending recovers unknown',
    () {
      database.close();
      final directory = Directory.systemTemp.createTempSync(
        'cashier-kds-command-',
      );
      final path = '${directory.path}${Platform.pathSeparator}cashier.db';
      final legacy = sqlite3.open(path);
      legacy.execute('''
      CREATE TABLE pending_commands (
        command_id TEXT PRIMARY KEY,
        shop_id INTEGER NOT NULL,
        command_type TEXT NOT NULL,
        target_json TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        result_json TEXT,
        attempt_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at_ms INTEGER NOT NULL DEFAULT 0
      )
    ''');
      legacy.execute(
        'INSERT INTO pending_commands '
        '(command_id, shop_id, command_type, target_json, payload_json, '
        'occurred_at_ms, status) VALUES (?, ?, ?, ?, ?, ?, ?)',
        [
          'legacy-command',
          7,
          'advance_item',
          '{"detail_id":9}',
          '{"command_id":"legacy-command","type":"advance_item",'
              '"target":{"detail_id":9}}',
          1000,
          'pending',
        ],
      );
      legacy.close();

      database = CashierKdsDatabase.open(path);
      final migrated = database.readPendingCommand(7, 'legacy-command')!;
      expect(migrated['status'], 'PENDING');
      expect('${migrated['request_fingerprint']}', hasLength(64));
      expect(migrated['actor_id'], 'MIGRATED');

      database.markPendingCommandSending(7, 'legacy-command', 1100);
      database.close();
      database = CashierKdsDatabase.open(path);
      final recovered = database.readPendingCommand(7, 'legacy-command')!;
      expect(recovered['status'], 'UNKNOWN');
      expect('${recovered['last_error']}', contains('restarted'));
      database.close();
      database = CashierKdsDatabase.inMemory();
      directory.deleteSync(recursive: true);
    },
  );
}
