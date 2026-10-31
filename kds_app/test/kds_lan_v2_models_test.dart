import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';

void main() {
  test('channel line exposes cloud order id without changing command id', () {
    final line = KdsV2Line.fromJson({
      ..._canonicalLine(),
      'fulfillment_channel': 'takeout',
      'cloud_order_id': 13597,
    });

    expect(line.orderId, 5);
    expect(line.cloudOrderId, 13597);
    expect(line.slices.single.cloudOrderId, 13597);
  });

  test('line exposes cloud order no and slices forward it', () {
    final line = KdsV2Line.fromJson({
      ..._canonicalLine(),
      'order_no': 'ORD20260905052010001',
    });
    expect(line.cloudOrderNo, 'ORD20260905052010001');
    expect(line.slices.single.cloudOrderNo, 'ORD20260905052010001');
  });

  test('order detail exposes cloud order id and no for reconciliation', () {
    final detail = KdsV2OrderDetail.fromJson({
      'order_id': 207,
      'order_no': 'ORD20260824225744942',
      'cloud_order_id': 13909,
      'table_number': '33',
      'fulfillment_type': 'dine_in',
      'order_remark': '',
      'detail_id': 760,
      'dish_id': 17,
      'dish_name': '油边王',
      'specification': '',
      'unit': '份',
      'quantity': 1,
      'refunded_quantity': 0,
      'remaining_quantity': 1,
      'status': 'active',
      'removed': false,
      'remark': '',
    });

    expect(detail.orderId, 207);
    expect(detail.cloudOrderId, 13909);
    expect(detail.cloudOrderNo, 'ORD20260824225744942');
  });

  test('bootstrap top-level permissions override config permissions', () {
    final bootstrap = KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 0,
      'shop_id': 9,
      'permissions': {
        'visible_queues': ['pending_cook', 'done'],
        'allowed_commands': ['advance_item'],
      },
      'config': {
        'visible_queues': ['pending_prep'],
        'allowed_commands': ['archive_clear'],
      },
      'queues': const {},
      'fixed_catalog': const [],
    });

    expect(bootstrap.config['visible_queues'], ['pending_cook', 'done']);
    expect(bootstrap.config['allowed_commands'], ['advance_item']);
  });

  test('command response rejects missing acknowledgement fields', () {
    expect(
      () => KdsV2CommandResult.fromJson({
        'data': {
          'command_id': '',
          'event_seq': 1,
          'patches': const [],
          'queue_counts': const {},
        }
      }),
      throwsFormatException,
    );
    expect(
      () => KdsV2CommandResult.fromJson({
        'data': {
          'command_id': 'cmd-1',
          'event_seq': -1,
          'patches': const [],
          'queue_counts': const {},
        }
      }),
      throwsFormatException,
    );
  });

  test('command resolution parses applied stable result', () {
    final resolution = KdsV2CommandResolution.fromJson({
      'data': {
        'protocol_version': 2,
        'command_id': 'cmd-1',
        'status': 'APPLIED',
        'result': {
          'command_id': 'cmd-1',
          'duplicate': false,
          'event_seq': 9,
          'patches': const [],
          'queue_counts': const {},
        },
      },
    });

    expect(resolution.status, KdsV2CommandResolutionStatus.applied);
    expect(resolution.result?.commandId, 'cmd-1');
    expect(resolution.result?.eventSeq, 9);
  });

  test('command resolution rejects applied status without stable result', () {
    expect(
      () => KdsV2CommandResolution.fromJson({
        'protocol_version': 2,
        'command_id': 'cmd-1',
        'status': 'APPLIED',
      }),
      throwsFormatException,
    );
  });

  test('bootstrap requires protocol v2 and parses authoritative state', () {
    final bootstrap = KdsV2Bootstrap.fromJson({
      'data': {
        'protocol_version': 2,
        'event_seq': 7,
        'device': {'shop_id': 9},
        'queues': {
          'pending_cook': [
            {
              ..._canonicalLine(),
              'line_quantity': 2,
              'cook_remaining': 2,
              'ready_remaining': 2,
              'local_revision': 4,
            }
          ],
        },
        'queue_counts': {'pending_cook': 2},
        'stats': {'today_orders': 9},
        'fixed_catalog': [
          {
            'dish_id': 3,
            'dish_name': '烤羊排',
            'unit': '份',
            'sequence': 2,
            'category_id': 8,
            'category_name': '烧烤',
            'category_sequence': 1,
          }
        ],
        'order_details': [
          {
            'order_id': 101,
            'order_no': 'L202608130001',
            'table_number': '18',
            'fulfillment_type': 'dine_in',
            'order_remark': '不要香菜',
            'detail_id': 301,
            'dish_id': 3,
            'dish_name': '烤羊排',
            'specification': '中辣',
            'unit': '份',
            'quantity': 3,
            'refunded_quantity': 1,
            'remaining_quantity': 2,
            'status': 'partially_refunded',
            'removed': false,
            'remark': '不要香菜',
          }
        ],
        'config': {'sla_minutes': 12},
      }
    });

    expect(bootstrap.eventSeq, 7);
    expect(bootstrap.shopId, 9);
    expect(bootstrap.lines.single.mergeKey, '3:dine_in');
    expect(bootstrap.queueCounts['pending_cook'], 2);
    expect(bootstrap.catalog.single.dishName, '烤羊排');
    expect(bootstrap.catalog.single.categoryId, 8);
    expect(bootstrap.catalog.single.categoryName, '烧烤');
    expect(bootstrap.catalog.single.categorySequence, 1);
    expect(bootstrap.orderDetails.single.detailId, 301);
    expect(bootstrap.orderDetails.single.remainingQuantity, 2);
  });

  test('bootstrap skips invalid lines instead of failing the whole snapshot',
      () {
    final bootstrap = KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 7,
      'queues': {
        'pending_cook': [
          _canonicalLine(),
          // 云端套餐头/未映射行：dish_id=0，单行无效不应拖垮整盘看板
          {..._canonicalLine(), 'detail_id': 999, 'dish_id': 0},
        ],
      },
      'queue_counts': const <String, int>{},
    });

    expect(bootstrap.lines.length, 1);
    expect(bootstrap.rejectedLineCount, 1);
    expect(bootstrap.lines.single.dishId, _canonicalLine()['dish_id']);
  });

  test('envelope skips invalid patches but applies the valid ones', () {
    final envelope = KdsV2Envelope.fromJson({
      'protocol_version': 2,
      'event_seq': 8,
      'event_id': 'evt-8',
      'type': 'order_updated',
      'patches': [
        _canonicalLine(),
        {..._canonicalLine(), 'detail_id': 998, 'dish_id': 0},
      ],
      'queue_counts': const <String, int>{},
    });

    expect(envelope.patches.length, 1);
    expect(envelope.rejectedLineCount, 1);
    expect(envelope.patches.single.detailId, _canonicalLine()['detail_id']);
  });

  test('event and command response parse complete order projections', () {
    final detail = {
      'order_id': 101,
      'order_no': 'L202608130001',
      'table_number': '18',
      'fulfillment_type': 'dine_in',
      'order_remark': '',
      'detail_id': 301,
      'dish_id': 88,
      'dish_name': '烤羊排',
      'specification': '',
      'unit': '份',
      'quantity': 3,
      'refunded_quantity': 3,
      'remaining_quantity': 0,
      'status': 'refunded',
      'removed': true,
      'remark': '',
    };
    final envelope = KdsV2Envelope.fromJson({
      'protocol_version': 2,
      'event_seq': 2,
      'event_id': 'refund-2',
      'type': 'refund_item',
      'patches': const [
        {'detail_id': 301, 'removed': true}
      ],
      'order_details': [detail],
      'queue_counts': const {'pending_cook': 0},
    });
    final result = KdsV2CommandResult.fromJson({
      'command_id': 'cmd-2',
      'event_seq': 2,
      'patches': const [
        {'detail_id': 301, 'removed': true}
      ],
      'order_details': [detail],
      'queue_counts': const {'pending_cook': 0},
    });

    expect(envelope.orderDetails.single.status, 'refunded');
    expect(result.orderDetails.single.removed, isTrue);
    expect(result.asEnvelope().orderDetails.single.detailId, 301);
  });

  test('protocol versions other than 2 are rejected without fallback', () {
    expect(
      () => KdsV2Bootstrap.fromJson({
        'data': {'protocol_version': 1, 'event_seq': 1, 'queues': {}}
      }),
      throwsFormatException,
    );
  });

  test('event envelopes reject malformed sequence identity and collections',
      () {
    for (final json in [
      {
        'protocol_version': 2,
        'event_id': 'e1',
        'type': 'order_created',
        'patches': const [],
        'queue_counts': const {},
      },
      {
        'protocol_version': 2,
        'event_seq': 1,
        'event_id': '',
        'type': 'order_created',
        'patches': const [],
        'queue_counts': const {},
      },
      {
        'protocol_version': 2,
        'event_seq': 1,
        'event_id': 'e1',
        'type': '',
        'patches': const {},
        'queue_counts': const [],
      },
    ]) {
      expect(() => KdsV2Envelope.fromJson(json), throwsFormatException);
    }
  });

  test('removed patch accepts a minimal authoritative tombstone', () {
    final envelope = KdsV2Envelope.fromJson({
      'protocol_version': 2,
      'event_seq': 2,
      'event_id': 'removed-2',
      'type': 'refund_item',
      'patches': const [
        {'detail_id': 11, 'removed': true}
      ],
      'queue_counts': const {'pending_cook': 0},
    });

    expect(envelope.patches.single.removed, isTrue);
    expect(envelope.patches.single.line, isNull);
  });

  test('command serialization follows the locked v2 envelope', () {
    final command = KdsV2Command(
      commandId: 'cmd-1',
      type: KdsV2CommandType.lackItem,
      target: const KdsV2CommandTarget(
        orderId: 5,
        detailId: 11,
        detailIds: [11, 12],
        fromQueue: 'pending_cook',
      ),
      quantity: 2,
      expectedRevision: 4,
      remark: '缺货',
      setSoldOut: true,
    );

    expect(command.toJson(), {
      'command_id': 'cmd-1',
      'type': 'lack_item',
      'target': {
        'order_id': 5,
        'detail_id': 11,
        'detail_ids': [11, 12],
        'from_queue': 'pending_cook',
      },
      'quantity': 2,
      'expected_revision': 4,
      'payload': {'remark': '缺货', 'set_sold_out': true},
    });
  });

  test('merged advance carries FIFO detail ids and per-line revisions', () {
    final command = KdsV2Command(
      commandId: 'merged-1',
      type: KdsV2CommandType.advanceItem,
      target: const KdsV2CommandTarget(
        detailIds: [11, 12],
        fromQueue: 'pending_cook',
      ),
      quantity: 5,
      expectedRevisions: const {11: 4, 12: 7},
    );
    expect(command.toJson()['target'], {
      'detail_ids': [11, 12],
      'from_queue': 'pending_cook',
    });
    expect(command.toJson()['payload'], {
      'expected_revisions': {'11': 4, '12': 7},
    });
    expect(command.toJson(), isNot(contains('expected_revision')));
  });

  test('order command serializes the authoritative order revision', () {
    final command = KdsV2Command(
      commandId: 'order-1',
      type: KdsV2CommandType.completeOrder,
      target: const KdsV2CommandTarget(orderId: 5),
      expectedRevision: 42,
    );

    expect(command.toJson(), {
      'command_id': 'order-1',
      'type': 'complete_order',
      'target': {'order_id': 5},
      'expected_revision': 42,
    });
  });

  test('bootstrap deduplicates the same full detail across queue buckets', () {
    final snapshot = {
      ..._canonicalLine(),
      'detail_id': 44,
      'order_id': 4,
      'dish_id': 8,
      'dish_name': '鸡翅',
      'local_revision': 3,
      'line_quantity': 2,
      'prep_remaining': 1,
      'cook_remaining': 2,
      'ready_remaining': 2,
      'done_quantity': 0,
    };
    final bootstrap = KdsV2Bootstrap.fromJson({
      'protocol_version': 2,
      'event_seq': 3,
      'queues': {
        'pending_prep': [snapshot],
        'pending_cook': [snapshot],
      },
    });
    expect(bootstrap.lines, hasLength(1));
    expect(bootstrap.lines.single.slices, hasLength(2));
  });

  test('all completed quantity projects only to done using the formula', () {
    final detail = KdsV2Line.fromJson({
      ..._canonicalLine(),
      'detail_id': 3,
      'order_id': 1,
      'dish_id': 2,
      'dish_name': '鸡翅',
      'line_quantity': 4,
      'local_revision': 5,
      'prep_remaining': 0,
      'cook_remaining': 0,
      'ready_remaining': 0,
      'done_quantity': 0,
    });
    expect(detail.slices.map((slice) => (slice.queue, slice.quantity)),
        [('done', 4)]);
  });

  test('malformed cumulative quantities are rejected', () {
    expect(
      () => KdsV2Line.fromJson({
        ..._canonicalLine(),
        'detail_id': 3,
        'order_id': 1,
        'dish_id': 2,
        'dish_name': '鸡翅',
        'line_quantity': 4,
        'local_revision': 5,
        'prep_remaining': 3,
        'cook_remaining': 2,
        'ready_remaining': 4,
        'refunded_quantity': 0,
      }),
      throwsFormatException,
    );
  });

  test('cashier line patch canonical fields win over legacy aliases', () {
    final line = KdsV2Line.fromJson({
      ..._canonicalLine(),
      'detail_id': 31,
      'order_id': 7,
      'dish_id': 9,
      'dish_name': '牛肉串',
      'line_quantity': 2,
      'prep_remaining': 0,
      'cook_remaining': 2,
      'ready_remaining': 2,
      'local_revision': 13,
      'row_version': 12,
      'revision': 11,
      'workflow_queue': 'pending_cook',
      'queue': 'pending_prep',
      'fulfillment_bucket': 'pickup',
      'fulfillment_type': 'dine_in',
    });

    expect(line.revision, 13);
    expect(line.queue, 'pending_cook');
    expect(line.fulfillmentBucket, 'pickup');
    expect(line.mergeKey, '9:pickup');
  });

  test('cashier line patch safe aliases preserve queue and fulfillment', () {
    final pickup = KdsV2Line.fromLegacyJson({
      'detail_id': 32,
      'order_id': 7,
      'dish_id': 9,
      'dish_name': '牛肉串',
      'quantity': 1,
      'row_version': 6,
      'queue_status': 'ready_serve',
      'fulfillment_type': 'self_pickup',
    });
    final takeout = KdsV2Line.fromLegacyJson({
      'detail_id': 33,
      'order_id': 8,
      'dish_id': 9,
      'dish_name': '牛肉串',
      'quantity': 1,
      'revision': 5,
      'queue': 'pending_cook',
      'dineInOrTakeOut': '外卖',
    });

    expect(pickup.revision, 6);
    expect(pickup.queue, 'ready_serve');
    expect(pickup.fulfillmentBucket, 'pickup');
    expect(takeout.revision, 5);
    expect(takeout.fulfillmentBucket, 'takeout');
    expect(pickup.mergeKey, isNot(takeout.mergeKey));
  });

  test('line channel prefers fulfillment_channel and falls back to bucket', () {
    Map<String, dynamic> json({String? channel}) => {
          'detail_id': 41,
          'order_id': 9,
          'dish_id': 9,
          'dish_name': '牛肉串',
          'line_quantity': 1,
          'refunded_quantity': 0,
          'prep_remaining': 0,
          'cook_remaining': 1,
          'ready_remaining': 1,
          'local_revision': 1,
          'order_revision': 1,
          'workflow_queue': 'pending_cook',
          'fulfillment_bucket': 'takeout',
          if (channel != null) 'fulfillment_channel': channel,
          'table_number': 'A01',
          'order_no': 'O-9',
          'specification': null,
          'unit': '份',
          'remark': null,
          'created_at_ms': 1720000000000,
          'held': false,
          'rushed': false,
          'lacked': false,
          'removed': false,
        };

    // 细分渠道覆盖 bucket
    expect(KdsV2Line.fromJson(json(channel: 'pickup')).channel, 'pickup');
    // 缺省回退 bucket
    expect(KdsV2Line.fromJson(json()).channel, 'takeout');
    // 非法值回退 bucket
    expect(KdsV2Line.fromJson(json(channel: 'unknown')).channel, 'takeout');
  });

  test('order detail parses optional order_rushed (v2.2)', () {
    Map<String, dynamic> json({bool? rushed}) => {
          'order_id': 1001,
          'order_no': 'O-1001',
          'table_number': 'A01',
          'fulfillment_type': 'dine_in',
          'order_remark': '',
          'detail_id': 9001,
          'dish_id': 88,
          'dish_name': '油边王',
          'specification': '',
          'unit': '串',
          'quantity': 2,
          'refunded_quantity': 0,
          'remaining_quantity': 2,
          'status': 'active',
          'removed': false,
          if (rushed != null) 'order_rushed': rushed,
          'remark': '',
        };

    expect(KdsV2OrderDetail.fromJson(json(rushed: true)).orderRushed, isTrue);
    expect(KdsV2OrderDetail.fromJson(json(rushed: false)).orderRushed, isFalse);
    // 旧收银端不返回该字段时默认 false
    expect(KdsV2OrderDetail.fromJson(json()).orderRushed, isFalse);
  });

  test('order detail accepts the full fulfillment type enum', () {
    for (final type in const [
      'dine_in',
      'takeout',
      'delivery',
      'pickup',
      'pack',
    ]) {
      final detail = KdsV2OrderDetail.fromJson({
        'order_id': 1001,
        'order_no': 'O-1001',
        'table_number': 'A01',
        'fulfillment_type': type,
        'order_remark': '',
        'detail_id': 9001,
        'dish_id': 88,
        'dish_name': '油边王',
        'specification': '',
        'unit': '串',
        'quantity': 2,
        'refunded_quantity': 0,
        'remaining_quantity': 2,
        'status': 'active',
        'removed': false,
        'remark': '',
      });
      expect(detail.fulfillmentType, type);
    }
  });

  test('all LAN fulfillment canonical values remain distinct', () {
    for (final bucket in const [
      'dine_in',
      'takeout',
      'pickup',
      'pack',
      'delivery',
    ]) {
      final line = KdsV2Line.fromJson({
        ..._canonicalLine(),
        'detail_id': bucket.hashCode & 0x7fffffff,
        'order_id': 1,
        'dish_id': 2,
        'dish_name': '鸡翅',
        'fulfillment_bucket': bucket,
      });
      expect(line.fulfillmentBucket, bucket);
      expect(line.mergeKey, '2:$bucket');
    }
    for (final alias in const {
      'takeaway': 'takeout',
      'self_pickup': 'pickup',
    }.entries) {
      final line = KdsV2Line.fromLegacyJson({
        'detail_id': alias.key.hashCode & 0x7fffffff,
        'order_id': 1,
        'dish_id': 2,
        'dish_name': '鸡翅',
        'quantity': 1,
        'workflow_queue': 'pending_cook',
        'fulfillment_bucket': alias.key,
        'local_revision': 1,
      });
      expect(line.fulfillmentBucket, alias.value);
    }
  });

  test('latest full line patch parses in bootstrap and command response', () {
    final patch = <String, dynamic>{
      'detail_id': 71,
      'order_id': 17,
      'dish_id': 3,
      'dish_name': '烤羊排',
      'line_quantity': 4,
      'refunded_quantity': 1,
      'prep_remaining': 1,
      'cook_remaining': 2,
      'ready_remaining': 3,
      'local_revision': 9,
      'order_revision': 12,
      'workflow_queue': 'pending_prep',
      'fulfillment_bucket': 'delivery',
      'table_number': null,
      'order_no': 'W-17',
      'specification': '微辣',
      'unit': '份',
      'remark': '先出',
      'created_at_ms': 1720000000000,
      'held': false,
      'rushed': true,
      'lacked': false,
      'removed': false,
    };
    final bootstrap = KdsV2Bootstrap.fromJson({
      'data': {
        'protocol_version': 2,
        'event_seq': 20,
        'shop_id': 2,
        'queues': {
          'pending_prep': [patch]
        },
        'queue_counts': {'pending_prep': 1},
        'stats': {'today_orders': 2},
        'fixed_catalog': [
          {'dish_id': 3, 'dish_name': '烤羊排', 'unit': '份', 'sequence': 0}
        ],
        'config': {
          'allowed_commands': ['advance_item'],
          'visible_queues': ['pending_prep']
        },
        'config_version': 4,
      }
    });
    final command = KdsV2CommandResult.fromJson({
      'data': {
        'command_id': 'cmd-22',
        'duplicate': false,
        'event_seq': 21,
        'patches': [patch],
        'queue_counts': {'pending_prep': 1},
        'order_summary': {
          'order_id': 17,
          'order_revision': 12,
          'status': 'preparing',
        },
      }
    });

    expect(bootstrap.configVersion, 4);
    expect(bootstrap.config['visible_queues'], ['pending_prep']);
    expect(bootstrap.catalog.single.dishName, '烤羊排');
    expect(bootstrap.lines.single.revision, 9);
    expect(bootstrap.lines.single.fulfillmentBucket, 'delivery');
    expect(bootstrap.lines.single.waitSecondsAt(1720000121000), 121);
    expect(command.patches.single.line?.raw['specification'], '微辣');
    expect(command.orderSummary?['order_revision'], 12);
  });

  test('canonical line patch rejects missing or malformed required fields', () {
    final cases = <Map<String, dynamic>>[
      {..._canonicalLine()}..remove('order_no'),
      {..._canonicalLine(), 'detail_id': 0},
      {..._canonicalLine(), 'dish_name': ''},
      {..._canonicalLine(), 'local_revision': 0},
      {..._canonicalLine(), 'created_at_ms': 0},
      {..._canonicalLine(), 'held': 0},
      {..._canonicalLine(), 'fulfillment_bucket': 'takeaway'},
      {..._canonicalLine(), 'prep_remaining': '1'},
    ];

    for (final malformed in cases) {
      expect(() => KdsV2Line.fromJson(malformed), throwsFormatException);
    }
  });
}

Map<String, dynamic> _canonicalLine() => {
      'detail_id': 11,
      'order_id': 5,
      'dish_id': 3,
      'dish_name': '烤羊排',
      'line_quantity': 1,
      'refunded_quantity': 0,
      'prep_remaining': 0,
      'cook_remaining': 1,
      'ready_remaining': 1,
      'local_revision': 1,
      'order_revision': 1,
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
