import 'pending_external_checkout_store.dart';

PendingExternalCheckoutStore createPlatformPendingExternalCheckoutStore() =>
    _MemoryPendingExternalCheckoutStore();

class _MemoryPendingExternalCheckoutStore
    implements PendingExternalCheckoutStore {
  final _values = <String, PendingExternalCheckout>{};

  @override
  Future<void> clear(String orderNo) async => _values.remove(orderNo);

  @override
  Future<PendingExternalCheckout?> read(String orderNo) async =>
      _values[orderNo];

  @override
  Future<void> write(PendingExternalCheckout value) async =>
      _values[value.orderNo] = value;
}
