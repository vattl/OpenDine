class HangOrderSummary {
  const HangOrderSummary({
    required this.orderId,
    required this.orderNo,
    required this.tableNumber,
    required this.numberOfDiners,
    required this.settAmount,
    required this.hangMinutes,
    this.hangTime,
    this.hangReason,
    this.hangAdminId,
  });

  final int orderId;
  final String orderNo;
  final String tableNumber;
  final int numberOfDiners;
  final double settAmount;
  final int hangMinutes;
  final String? hangTime;
  final String? hangReason;
  final int? hangAdminId;

  factory HangOrderSummary.fromJson(Map<String, dynamic> json) {
    return HangOrderSummary(
      orderId: _asInt(json['order_id'] ?? json['orderId'] ?? json['id']),
      orderNo: (json['order_no'] ?? json['orderNo'] ?? '').toString(),
      tableNumber: (json['table_number'] ?? json['tableNumber'] ?? '').toString(),
      numberOfDiners: _asInt(
        json['number_of_diners'] ??
            json['numberOfDiners'] ??
            json['diners'] ??
            json['people'] ??
            1,
      ),
      settAmount: _asDouble(
        json['sett_amount'] ?? json['settAmount'] ?? json['amount'],
      ),
      hangMinutes: _asInt(json['hang_minutes'] ?? json['hangMinutes']),
      hangTime: json['hang_time']?.toString() ?? json['hangTime']?.toString(),
      hangReason: json['hang_reason']?.toString() ?? json['hangReason']?.toString(),
      hangAdminId: json['hang_admin_id'] != null ? _asInt(json['hang_admin_id']) : null,
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}
