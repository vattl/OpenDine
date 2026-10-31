import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CashierKdsDatabase database;

  setUp(() => database = CashierKdsDatabase.inMemory());
  tearDown(() => database.close());

  Map<String, Object?> event({
    required String id,
    required int cursor,
    required int version,
    required int quantity,
    required int remaining,
  }) => {
    'eventId': id,
    'cursor': cursor,
    'eventType': 'ORDER_UPDATED',
    'occurredAtMs': 1000 + cursor,
    'projection': {
      'orderId': 9001,
      'orderNo': 'MP9001',
      'shopId': 1,
      'projectionVersion': version,
      'state': 'READY',
      'sourceChannel': 'MINI_PROGRAM',
      'fulfillmentType': 'DINE_IN',
      'tableNumber': 'A08',
      'numberOfDiners': 2,
      'createdAtMs': 1000,
      'lines': [
        {
          'detailId': 9101,
          'dishId': 101,
          'dishName': '测试菜品',
          'quantity': quantity,
          'refundedQuantity': quantity - remaining,
          'remainingQuantity': remaining,
          'lineStatus': remaining == 0 ? 'REFUNDED' : 'NORMAL',
          'lineType': 'NORMAL',
        },
      ],
    },
  };

  test(
    'cloud line without a valid dishId is skipped and never reaches board',
    () {
      final base = event(
        id: 'e0',
        cursor: 1,
        version: 1,
        quantity: 2,
        remaining: 2,
      );
      final projection = (base['projection'] as Map).cast<String, Object?>();
      // 套餐头/第三方未映射行：dishId 为 0，不应进入厨房状态池
      (projection['lines'] as List).add({
        'detailId': 9102,
        'dishId': 0,
        'dishName': '超值双人套餐',
        'quantity': 1,
        'refundedQuantity': 0,
        'remainingQuantity': 1,
        'lineStatus': 'NORMAL',
        'lineType': 'COMBO_HEADER',
      });
      database.applyCloudDeliveryEvent(base);

      for (final queue in const [
        'pending_prep',
        'pending_cook',
        'ready_serve',
        'done',
      ]) {
        final lines = database.readWorkflowBoard(shopId: 1, queue: queue).lines;
        expect(lines.every((line) => line.dishId > 0), isTrue);
      }
      final board = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines;
      expect(board.length, 1);
      expect(board.single.dishId, 101);
    },
  );

  test('cloud delivery is idempotent and preserves local kitchen progress', () {
    final first = database.applyCloudDeliveryEvent(
      event(id: 'e1', cursor: 1, version: 1, quantity: 3, remaining: 3),
    );
    final duplicate = database.applyCloudDeliveryEvent(
      event(id: 'e1', cursor: 1, version: 1, quantity: 3, remaining: 3),
    );
    expect(duplicate.duplicate, isTrue);

    final initial = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: initial.detailId,
      fromQueue: 'pending_prep',
      quantity: 1,
      operationId: 'advance-1',
      expectedRevision: initial.localRevision,
      occurredAtMs: 1200,
    );

    final updated = database.applyCloudDeliveryEvent(
      event(id: 'e2', cursor: 2, version: 2, quantity: 4, remaining: 4),
    );
    expect(updated.orderId, first.orderId);
    final afterAdd = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    expect(afterAdd.lineQuantity, 4);
    expect(afterAdd.prepRemaining, 3);

    database.applyCloudDeliveryEvent(
      event(id: 'e3', cursor: 3, version: 3, quantity: 4, remaining: 2),
    );
    final afterRefund = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    expect(afterRefund.prepRemaining, 2);
    expect(afterRefund.refundedQuantity, 2);
  });

  test('completed first-round line stays done after add-dishes projection', () {
    database.applyCloudDeliveryEvent(
      event(id: 'e1', cursor: 1, version: 1, quantity: 1, remaining: 1),
    );
    var current = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: current.detailId,
      fromQueue: 'pending_prep',
      quantity: 1,
      operationId: 'complete-first-prep',
      expectedRevision: current.localRevision,
      occurredAtMs: 1300,
    );
    current = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_cook')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: current.detailId,
      fromQueue: 'pending_cook',
      quantity: 1,
      operationId: 'complete-first-cook',
      expectedRevision: current.localRevision,
      occurredAtMs: 1400,
    );
    current = database
        .readWorkflowBoard(shopId: 1, queue: 'ready_serve')
        .lines
        .single;
    database.advanceLine(
      shopId: 1,
      detailId: current.detailId,
      fromQueue: 'ready_serve',
      quantity: 1,
      operationId: 'complete-first-serve',
      expectedRevision: current.localRevision,
      occurredAtMs: 1500,
    );

    final addDishes = event(
      id: 'e2',
      cursor: 2,
      version: 2,
      quantity: 1,
      remaining: 1,
    );
    final projection = (addDishes['projection'] as Map).cast<String, Object?>();
    final lines = projection['lines'] as List;
    (lines.single as Map)['workflowQueue'] = 'pending_prep';
    lines.add({
      'detailId': 9102,
      'dishId': 102,
      'dishName': '加菜菜品',
      'quantity': 1,
      'refundedQuantity': 0,
      'remainingQuantity': 1,
      'lineStatus': 'NORMAL',
      'lineType': 'NORMAL',
      'workflowQueue': 'pending_prep',
    });

    database.applyCloudDeliveryEvent(addDishes);

    final activeDishIds = <int>{
      for (final queue in const ['pending_prep', 'pending_cook', 'ready_serve'])
        for (final line
            in database.readWorkflowBoard(shopId: 1, queue: queue).lines)
          line.dishId,
    };
    expect(activeDishIds, {102});
    final done = database.readWorkflowBoard(shopId: 1, queue: 'done').lines;
    expect(done.map((line) => line.dishId), contains(101));
  });

  test(
    'bootstrap is atomic, restores equal versions and removes stale orders',
    () {
      final firstEvent = event(
        id: 'e1',
        cursor: 1,
        version: 1,
        quantity: 2,
        remaining: 2,
      );
      database.applyCloudDeliveryEvent(firstEvent);
      final projection = (firstEvent['projection'] as Map)
          .cast<String, Object?>();

      database.applyCloudBootstrap(
        shopId: 1,
        baseCursor: 1,
        orders: [projection],
      );
      expect(
        database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
        hasLength(1),
      );

      final removals = database.applyCloudBootstrap(
        shopId: 1,
        baseCursor: 1,
        orders: const [],
      );
      expect(
        database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
        isEmpty,
      );
      expect(removals.single.eventSeq, greaterThan(0));
      final change = database
          .readChanges(
            shopId: 1,
            afterSeq: removals.single.eventSeq - 1,
            limit: 1,
          )
          .single;
      expect(change.type, 'order_voided');
      expect(change.patches.single['prep_remaining'], 0);
    },
  );

  test('bootstrap safely ignores empty or corrupted projections', () {
    final firstEvent = event(
      id: 'e1',
      cursor: 1,
      version: 1,
      quantity: 2,
      remaining: 2,
    );
    final validProjection = (firstEvent['projection'] as Map)
        .cast<String, Object?>();

    // Should not throw even if corrupted/empty projections are received
    final receipts = database.applyCloudBootstrap(
      shopId: 1,
      baseCursor: 1,
      orders: [
        <String, Object?>{},
        {'orderId': 0},
        validProjection,
        {'orderId': -1, 'orderNo': 'INVALID'},
      ],
    );
    expect(receipts, isNotEmpty);
    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
      hasLength(1),
    );
  });

  test('ORDER_RUSHED marks the whole order as rushed', () {
    database.applyCloudDeliveryEvent(
      event(id: 'e1', cursor: 1, version: 1, quantity: 2, remaining: 2),
    );
    final rushed = event(
      id: 'e2',
      cursor: 2,
      version: 2,
      quantity: 2,
      remaining: 2,
    );
    rushed['eventType'] = 'ORDER_RUSHED';
    database.applyCloudDeliveryEvent(rushed);

    final projection = database
        .readOrderDetailsProjection(shopId: 1, orderIds: const [1])
        .single;
    expect(projection['order_rushed'], isTrue);
    final change = database.readChanges(shopId: 1, afterSeq: 0).last;
    expect(change.type, 'order_rushed');
    // 加急不影响的菜品制作进度
    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
      hasLength(1),
    );
  });

  test('ORDER_CANCELLED without projection state archives the order', () {
    database.applyCloudDeliveryEvent(
      event(id: 'e1', cursor: 1, version: 1, quantity: 2, remaining: 2),
    );
    final cancelled = event(
      id: 'e2',
      cursor: 2,
      version: 2,
      quantity: 2,
      remaining: 2,
    );
    cancelled['eventType'] = 'ORDER_CANCELLED';
    (cancelled['projection'] as Map).remove('state');
    database.applyCloudDeliveryEvent(cancelled);

    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
      isEmpty,
    );
    final projection = database.readOrderDetailsProjection(
      shopId: 1,
      orderIds: const [1],
    );
    expect(projection, isNotEmpty);
  });

  test('CANCELLED line status voids the line and records a full refund', () {
    database.applyCloudDeliveryEvent(
      event(id: 'e1', cursor: 1, version: 1, quantity: 2, remaining: 2),
    );
    final voided = event(
      id: 'e2',
      cursor: 2,
      version: 2,
      quantity: 2,
      remaining: 0,
    );
    final line = ((voided['projection'] as Map)['lines'] as List).single as Map;
    line['lineStatus'] = 'CANCELLED';
    line['refundedQuantity'] = 0;
    database.applyCloudDeliveryEvent(voided);

    expect(
      database.readWorkflowBoard(shopId: 1, queue: 'pending_prep').lines,
      isEmpty,
    );
    final projection = database
        .readOrderDetailsProjection(shopId: 1, orderIds: const [1])
        .single;
    expect(projection['refunded_quantity'], 2);
    expect(projection['status'], 'refunded');
    expect(projection['removed'], isTrue);
  });

  test('combo line type and id are honored on insert', () {
    final comboEvent = event(
      id: 'e1',
      cursor: 1,
      version: 1,
      quantity: 1,
      remaining: 1,
    );
    final line =
        ((comboEvent['projection'] as Map)['lines'] as List).single as Map;
    line['lineType'] = 'COMBO_COMPONENT';
    line['comboId'] = 501;
    database.applyCloudDeliveryEvent(comboEvent);

    final projection = database
        .readOrderDetailsProjection(shopId: 1, orderIds: const [1])
        .single;
    expect(projection['is_combo'], isTrue);
    expect(projection['combo_id'], 501);
  });

  // 复现 2026-08-19 生产事故：云端出生订单全额退菜后上报 4090
  // "aggregate prerequisite has not arrived" 并无限重试卡死。
  test(
    'full refund on a cloud-born order syncs with formal aggregate and ids',
    () {
      database.applyCloudDeliveryEvent(
        event(id: 'e1', cursor: 1, version: 1, quantity: 2, remaining: 2),
      );
      final line = database
          .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
          .lines
          .single;

      // 全额退菜：patch removed=true，不得因此丢失订单上下文。
      database.executeKdsCommand(
        LocalKdsCommand(
          commandId: 'refund-all-1',
          type: LocalKdsCommandType.refundItem,
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

      final outbox = database.readPendingCloudEvents().single;
      expect(outbox.eventType, 'kds_state_changed');
      // 云端出生订单必须使用云端正式 aggregate（本地从未发送 order_created）。
      expect(outbox.aggregateKey, 'order:9001');
      final payload = outbox.payload;
      // 必须是携带完整订单身份的全量快照，而不是无订单上下文的补丁。
      expect(payload.containsKey('orders'), isTrue);
      expect(payload.containsKey('patches'), isFalse);
      expect(payload['order_id'], 9001);
      expect(payload.containsKey('local_order_id'), isFalse);
      final order = (payload['orders'] as List).single as Map;
      expect(order['order_id'], 9001);
      final payloadLine = (payload['lines'] as List).single as Map;
      expect(payloadLine['order_id'], 9001);
      expect(payloadLine['detail_id'], 9101);
      expect(payloadLine['refunded_quantity'], 2);
    },
  );

  test('partially mapped cloud-born order keeps formal order id per line', () {
    database.applyCloudDeliveryEvent(
      event(id: 'e1', cursor: 1, version: 1, quantity: 2, remaining: 2),
    );
    // 模拟云端出生订单存在本地未映射行（如本地加菜）：抹掉行映射。
    database.debugClearLineCloudMapping(1);
    final line = database
        .readWorkflowBoard(shopId: 1, queue: 'pending_prep')
        .lines
        .single;
    database.executeKdsCommand(
      LocalKdsCommand(
        commandId: 'rush-mapped-order',
        type: LocalKdsCommandType.rushItem,
        shopId: 1,
        target: LocalKdsCommandTarget(detailId: line.detailId),
        expectedRevision: line.localRevision,
        occurredAtMs: 2000,
      ),
    );

    final payload = database.readPendingCloudEvents().single.payload;
    // 订单级仍是正式 id；未映射行携带本地 id + local_detail_id 别名，
    // 等待云端在 ACK 的 detail_mappings 中返回正式映射。
    expect(payload['order_id'], 9001);
    expect(payload.containsKey('local_order_id'), isFalse);
    final payloadLine = (payload['lines'] as List).single as Map;
    expect(payloadLine['order_id'], 9001);
    expect(payloadLine['detail_id'], line.detailId);
    expect(payloadLine['local_detail_id'], line.detailId);
  });

  test(
    'cloud projection with snake_case and alias line fields is properly ingested',
    () {
      final rawEvent = {
        'eventId': 'snake-e1',
        'cursor': 100,
        'eventType': 'ORDER_UPDATED',
        'occurredAtMs': 3000,
        'projection': {
          'orderId': 9002,
          'orderNo': 'MP9002',
          'shopId': 1,
          'projectionVersion': 1,
          'state': 'READY',
          'lines': [
            {
              'detail_id': 9201,
              'goods_id': 201,
              'goods_name': '下划线加菜',
              'quantity': 3,
              'remaining_quantity': 3,
              'specs': '微辣',
              'unit_name': '把',
            },
          ],
        },
      };
      final receipt = database.applyCloudDeliveryEvent(rawEvent);
      expect(receipt.orderId, greaterThan(0));

      final details = database.readOrderDetailsProjection(
        shopId: 1,
        orderIds: [receipt.orderId],
      );
      expect(details.length, 1);
      expect(details.first['dish_id'], 201);
      expect(details.first['dish_name'], '下划线加菜');
      expect(details.first['specification'], '微辣');
      expect(details.first['unit'], '把');
      expect(details.first['quantity'], 3);
      expect(details.first['remaining_quantity'], 3);

      final patches = database.readOrderPatches(receipt.orderId);
      expect(patches.length, 1);
      expect(patches.first['dish_id'], 201);
      expect(patches.first['dish_name'], '下划线加菜');
    },
  );
}
