import 'package:admin_panel_flutter/src/features/kds_local/data/cashier_kds_database.dart';
import 'package:admin_panel_flutter/src/features/kds_local/domain/cashier_kds_interaction_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late CashierKdsDatabase database;

  setUp(() => database = CashierKdsDatabase.inMemory());
  tearDown(() => database.close());

  CashierKdsInteractionLogDraft log({
    required String traceId,
    int shopId = 1,
    int at = 1000,
    KdsInteractionStatus status = KdsInteractionStatus.succeeded,
    String? error,
    Map<String, Object?> metadata = const {},
  }) => CashierKdsInteractionLogDraft(
    traceId: traceId,
    shopId: shopId,
    orderId: 12,
    orderNo: 'ORDER-12',
    eventId: 'event-$traceId',
    operationId: 'operation-$traceId',
    source: KdsInteractionSide.kds,
    target: KdsInteractionSide.cashier,
    direction: KdsInteractionDirection.inbound,
    stage: KdsInteractionStage.kdsCommandReceived,
    action: 'advance_item',
    status: status,
    errorType: error == null ? null : 'network_error',
    errorSummary: error,
    metadata: metadata,
    occurredAtMs: at,
  );

  test('stores and queries one interaction chain by trace and shop', () {
    database.recordInteraction(log(traceId: 'trace-a'));
    database.recordInteraction(log(traceId: 'trace-b', shopId: 2));

    final rows = database.readInteractionLogs(
      const CashierKdsInteractionLogFilter(shopId: 1, traceId: 'trace-a'),
    );

    expect(rows, hasLength(1));
    expect(rows.single.traceId, 'trace-a');
    expect(rows.single.orderNo, 'ORDER-12');
    expect(rows.single.stage, KdsInteractionStage.kdsCommandReceived);
    expect(rows.single.status, KdsInteractionStatus.succeeded);
  });

  test('sanitizes errors and only keeps allowlisted metadata', () {
    database.recordInteraction(
      log(
        traceId: 'trace-secret',
        error: 'Bearer abc.def.ghi\n手机号 13800138000',
        metadata: const {
          'recipient_count': 2,
          'attempt_delay_ms': 5000,
          'token': 'do-not-store',
          'request_body': {'customer_phone': '13800138000'},
        },
      ),
    );

    final row = database
        .readInteractionLogs(const CashierKdsInteractionLogFilter(shopId: 1))
        .single;
    expect(row.errorSummary, isNot(contains('abc.def.ghi')));
    expect(row.errorSummary, isNot(contains('13800138000')));
    expect(row.metadata, {'recipient_count': 2, 'attempt_delay_ms': 5000});
  });

  test('filters failures and applies age and maximum retention', () {
    database.recordInteraction(log(traceId: 'old', at: 1000));
    database.recordInteraction(
      log(traceId: 'failed', at: 2000, status: KdsInteractionStatus.failed),
    );
    database.recordInteraction(log(traceId: 'latest', at: 3000));

    final failed = database.readInteractionLogs(
      const CashierKdsInteractionLogFilter(
        shopId: 1,
        statuses: {KdsInteractionStatus.failed},
      ),
    );
    expect(failed.map((row) => row.traceId), ['failed']);

    final result = database.cleanupInteractionLogRetention(
      nowMs: 4000,
      retention: const Duration(milliseconds: 2500),
      maxRows: 1,
    );
    expect(result, 2);
    expect(
      database
          .readInteractionLogs(const CashierKdsInteractionLogFilter(shopId: 1))
          .map((row) => row.traceId),
      ['latest'],
    );
  });

  test('best effort recording never throws and exposes dropped count', () {
    final stored = database.tryRecordInteraction(log(traceId: 'ok'));
    final dropped = database.tryRecordInteraction(log(traceId: '', shopId: 0));

    expect(stored, isTrue);
    expect(dropped, isFalse);
    expect(database.droppedInteractionLogCount, 1);
  });
}
