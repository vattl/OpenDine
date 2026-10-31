import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/lan_v2/kds_v2_models.dart';
import 'package:kds_app/features/board_v2/kds_v2_board_provider.dart';

void main() {
  test('detail commands use their canonical order as the queue boundary', () {
    final command = KdsV2Command(
      commandId: 'cmd-detail-1',
      type: KdsV2CommandType.advanceItem,
      target: const KdsV2CommandTarget(detailId: 11),
      expectedRevision: 1,
    );
    final line = KdsV2Line.fromJson({
      'detail_id': 11,
      'order_id': 77,
      'dish_id': 1,
      'dish_name': 'test',
      'line_quantity': 1,
      'refunded_quantity': 0,
      'prep_remaining': 1,
      'cook_remaining': 1,
      'ready_remaining': 1,
      'local_revision': 1,
      'order_revision': 1,
      'fulfillment_bucket': 'dine_in',
      'workflow_queue': 'pending_prep',
      'table_number': '1',
      'order_no': 'ORDER-77',
      'specification': '',
      'unit': '份',
      'remark': '',
      'created_at_ms': 1,
      'held': false,
      'rushed': false,
      'lacked': false,
      'removed': false,
    });

    expect(kdsAggregateKeyForCommand(command, [line]), 'order:77');
  });
}
