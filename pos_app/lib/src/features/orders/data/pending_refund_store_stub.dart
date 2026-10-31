import 'pending_refund_store.dart';

PendingRefundStore createPlatformPendingRefundStore() =>
    MemoryPendingRefundStore();

class MemoryPendingRefundStore implements PendingRefundStore {
  final values = <String, PendingRefund>{};

  @override
  Future<void> clear(String orderNo) async => values.remove(orderNo);

  @override
  Future<void> clearIfMatches(String orderNo, String idempotencyKey) async {
    if (values[orderNo]?.idempotencyKey == idempotencyKey) {
      values.remove(orderNo);
    }
  }

  @override
  Future<PendingRefund?> read(String orderNo) async => values[orderNo];

  @override
  Future<void> write(PendingRefund value) async {
    values[value.orderNo] = value;
  }
}
