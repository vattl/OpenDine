import 'pending_refund_store_stub.dart'
    if (dart.library.io) 'pending_refund_store_io.dart'
    if (dart.library.html) 'pending_refund_store_web.dart'
    as platform;

class PendingRefund {
  const PendingRefund({
    required this.orderNo,
    required this.amountMinor,
    required this.reason,
    required this.baselineRefundMinor,
    required this.idempotencyKey,
  });

  final String orderNo;
  final int amountMinor;
  final String reason;
  final int baselineRefundMinor;
  final String idempotencyKey;

  Map<String, Object?> toJson() => {
    'order_no': orderNo,
    'amount_minor': amountMinor,
    'reason': reason,
    'baseline_refund_minor': baselineRefundMinor,
    'idempotency_key': idempotencyKey,
  };

  factory PendingRefund.fromJson(Map<String, Object?> json) => PendingRefund(
    orderNo: json['order_no']?.toString() ?? '',
    amountMinor: _integer(json['amount_minor']),
    reason: json['reason']?.toString() ?? '',
    baselineRefundMinor: _integer(json['baseline_refund_minor']),
    idempotencyKey: json['idempotency_key']?.toString() ?? '',
  );

  static int _integer(Object? value) =>
      value is num ? value.round() : int.tryParse('$value') ?? 0;
}

abstract interface class PendingRefundStore {
  Future<PendingRefund?> read(String orderNo);

  Future<void> write(PendingRefund value);

  Future<void> clear(String orderNo);

  Future<void> clearIfMatches(String orderNo, String idempotencyKey);
}

PendingRefundStore createPendingRefundStore() =>
    platform.createPlatformPendingRefundStore();
