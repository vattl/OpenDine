import '../domain/takeout_dispatch_alert.dart';

abstract interface class TakeoutDispatchAlertSource {
  Stream<TakeoutDispatchAlert> get alerts;

  void start();

  Future<void> close();
}

class NoopTakeoutDispatchAlertSource implements TakeoutDispatchAlertSource {
  const NoopTakeoutDispatchAlertSource();

  @override
  Stream<TakeoutDispatchAlert> get alerts => const Stream.empty();

  @override
  void start() {}

  @override
  Future<void> close() async {}
}
