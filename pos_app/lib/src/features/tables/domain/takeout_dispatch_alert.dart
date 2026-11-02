class TakeoutDispatchAlert {
  const TakeoutDispatchAlert({
    required this.alertType,
    required this.orderId,
    required this.shopId,
    this.eventType = 'takeout_dispatch_alert',
    this.orderNo = '',
    this.message = '',
  });

  final String eventType;
  final String alertType;
  final int orderId;
  final int shopId;
  final String orderNo;
  final String message;

  bool get isOrderMissing => alertType == 'order_missing';
  bool get isDispatchChanged => eventType == 'takeout_dispatch_changed';

  static TakeoutDispatchAlert? tryParse(Object? value) {
    if (value is! Map) return null;
    final eventType = '${value['type']}'.trim().toLowerCase();
    if (!const {
      'takeout_dispatch_alert',
      'takeout_dispatch_changed',
    }.contains(eventType))
      return null;
    final orderId = _int(value['orderId'] ?? value['order_id']);
    final shopId = _int(value['shopId'] ?? value['shop_id']);
    final alertType = '${value['alertType'] ?? value['alert_type'] ?? ''}'
        .trim()
        .toLowerCase();
    if (orderId <= 0 ||
        shopId <= 0 ||
        (eventType == 'takeout_dispatch_alert' && alertType.isEmpty)) {
      return null;
    }
    return TakeoutDispatchAlert(
      eventType: eventType,
      alertType: alertType,
      orderId: orderId,
      shopId: shopId,
      orderNo: '${value['orderNo'] ?? value['order_no'] ?? ''}'.trim(),
      message: '${value['message'] ?? ''}'.trim(),
    );
  }
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
