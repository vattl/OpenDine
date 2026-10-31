import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/core/lan_v2/kds_v2_reducer.dart';

void main() {
  test('patches replace complete snapshots and remove lines', () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'pending_cook': [
          _line(quantity: 1, revision: 1),
        ]
      },
    }));
    final updated = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'evt-2',
        'type': 'line_changed',
        'patches': [
          _line(quantity: 3, revision: 2),
        ],
        'queue_counts': {'pending_cook': 3},
      }),
    );
    expect(updated.lines.single.quantity, 3);
    expect(updated.lines.single.revision, 2);

    final removed = KdsV2Reducer.applyEnvelope(
      updated,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 3,
        'event_id': 'evt-3',
        'type': 'line_removed',
        'patches': [
          {..._line(quantity: 3, revision: 3), 'removed': true}
        ],
        'queue_counts': {'pending_cook': 0},
      }),
    );
    expect(removed.lines, isEmpty);
  });

  test('minimal removed patch deletes the authoritative line', () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'pending_cook': [_line(quantity: 1, revision: 1)]
      },
    }));
    final removed = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'removed-2',
        'type': 'line_removed',
        'patches': const [
          {'detail_id': 11, 'removed': true}
        ],
        'queue_counts': const {'pending_cook': 0},
      }),
    );

    expect(removed.lines, isEmpty);
  });

  test('removed operational line keeps the complete read-only order detail',
      () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'pending_cook': [_line(quantity: 1, revision: 1)]
      },
      'order_details': [_orderDetail(status: 'active', removed: false)],
    }));
    final updated = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'refund-2',
        'type': 'refund_item',
        'patches': const [
          {'detail_id': 11, 'removed': true}
        ],
        'order_details': [
          _orderDetail(status: 'refunded', removed: true),
        ],
        'queue_counts': const {'pending_cook': 0},
      }),
    );

    expect(updated.lines, isEmpty);
    expect(updated.orderDetails.single.status, 'refunded');
    expect(updated.orderDetails.single.removed, isTrue);
  });

  test('one authoritative detail snapshot exposes simultaneous queue slices',
      () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'pending_prep': [
          {
            ..._line(quantity: 2, revision: 1),
            'line_quantity': 2,
            'prep_remaining': 2,
            'cook_remaining': 2,
            'ready_remaining': 2,
            'done_quantity': 0,
          }
        ]
      },
    }));

    expect(initial.lines, hasLength(1));
    expect(
        initial.lines.single.slices
            .map((slice) => (slice.queue, slice.quantity)),
        [('pending_prep', 2)]);

    final progressed = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'partial-2',
        'type': 'detail_changed',
        'patches': [
          {
            ..._line(quantity: 2, revision: 2),
            'line_quantity': 2,
            'prep_remaining': 1,
            'cook_remaining': 2,
            'ready_remaining': 2,
            'done_quantity': 0,
          }
        ],
        'queue_counts': const {'pending_prep': 1, 'pending_cook': 1},
      }),
    );

    expect(progressed.lines, hasLength(1));
    expect(
        progressed.lines.single.slices
            .map((slice) => (slice.queue, slice.quantity)),
        [('pending_prep', 1), ('pending_cook', 1)]);
  });

  test('completion event stamps missing completed_at_ms from event time', () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'ready_serve': [_line(quantity: 1, revision: 1)]
      },
    }));
    final completed = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'served-2',
        'type': 'advance_item',
        'occurred_at_ms': 1786608120000,
        'patches': [
          {
            ..._line(quantity: 1, revision: 2),
            'cook_remaining': 0,
            'ready_remaining': 0,
          }
        ],
        'queue_counts': const {'done': 1},
      }),
    );

    expect(completed.lines.single.raw['completed_at_ms'], 1786608120000);
  });

  test('later completion refreshes a stale completed_at_ms for done sorting',
      () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'done': [
          {
            ..._line(quantity: 2, revision: 1),
            'cook_remaining': 1,
            'ready_remaining': 1,
            'completed_at_ms': 1786608000000,
          }
        ]
      },
    }));

    final completed = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'served-3',
        'type': 'advance_item',
        'occurred_at_ms': 1786608120000,
        'patches': [
          {
            ..._line(quantity: 2, revision: 2),
            'cook_remaining': 0,
            'ready_remaining': 0,
            // 模拟旧服务端 patch 复用了第一次完成的时间。
            'completed_at_ms': 1786608000000,
          }
        ],
        'queue_counts': const {},
      }),
    );

    expect(completed.lines.single.raw['completed_at_ms'], 1786608120000);
  });

  test('removed keeps fully-completed lines as persistent done history', () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'done': [_doneLine(quantity: 2, revision: 1)]
      },
    }));
    final removed = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'evt-2',
        'type': 'order_closed',
        'patches': [
          {..._doneLine(quantity: 2, revision: 2), 'removed': true}
        ],
        'queue_counts': const {},
      }),
    );
    // 结账/清理的 removed 事件不得删除已完成菜品：保留并标记 removed。
    expect(removed.lines, hasLength(1));
    expect(removed.lines.single.raw['removed'], true);
    expect(removed.lines.single.slices.single.queue, 'done');
    expect(removed.lines.single.slices.single.quantity, 2);
  });

  test('removed still deletes lines with active quantities', () {
    final initial = KdsV2State.fromBootstrap(KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 1,
      'queues': {
        'pending_cook': [_line(quantity: 1, revision: 1)]
      },
    }));
    final removed = KdsV2Reducer.applyEnvelope(
      initial,
      KdsV2Envelope.fromJson({
        'protocol_version': 2,
        'event_seq': 2,
        'event_id': 'evt-2',
        'type': 'line_removed',
        'patches': [
          {..._line(quantity: 1, revision: 2), 'removed': true}
        ],
        'queue_counts': const {},
      }),
    );
    // 退菜/作废（仍有活动数量）仍按协议删除。
    expect(removed.lines, isEmpty);
  });
}

Map<String, dynamic> _doneLine({required int quantity, required int revision}) => {
      ..._line(quantity: quantity, revision: revision),
      'prep_remaining': 0,
      'cook_remaining': 0,
      'ready_remaining': 0,
      'workflow_queue': 'done',
    };

Map<String, dynamic> _line({required int quantity, required int revision}) => {
      'detail_id': 11,
      'order_id': 5,
      'dish_id': 3,
      'dish_name': '烤羊排',
      'line_quantity': quantity,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': quantity,
      'ready_remaining': quantity,
      'local_revision': revision,
      'order_revision': revision,
      'workflow_queue': 'pending_cook',
      'fulfillment_bucket': 'dine_in',
      'table_number': 'A1',
      'order_no': 'O-5',
      'specification': null,
      'unit': '份',
      'remark': null,
      'created_at_ms': 1720000000000,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
    };

Map<String, dynamic> _orderDetail({
  required String status,
  required bool removed,
}) =>
    {
      'order_id': 5,
      'order_no': 'O-5',
      'table_number': 'A1',
      'fulfillment_type': 'dine_in',
      'order_remark': '',
      'detail_id': 11,
      'dish_id': 3,
      'dish_name': '烤羊排',
      'specification': '',
      'unit': '份',
      'quantity': 1,
      'refunded_quantity': removed ? 1 : 0,
      'remaining_quantity': removed ? 0 : 1,
      'status': status,
      'removed': removed,
      'remark': '',
    };
