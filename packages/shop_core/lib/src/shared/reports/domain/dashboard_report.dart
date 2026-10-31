import '../../catalog/domain/catalog_models.dart';

class DashboardReport {
  const DashboardReport({
    required this.revenue,
    required this.todayOrderCount,
    required this.successRechargeTotal,
    required this.pendingTakeoutCount,
  });

  final DashboardRevenue revenue;
  final int todayOrderCount;
  final double successRechargeTotal;
  final int pendingTakeoutCount;

  double get businessRevenueNet => revenue.businessRevenueNet;

  factory DashboardReport.fromJson(Map<String, Object?> json) {
    final businessDay = _map(
      json['businessDay'] ?? json['business_day'] ?? json,
    );
    return DashboardReport(
      revenue: DashboardRevenue(
        settAmount: _double(
          businessDay['sett_amount'] ??
              businessDay['settAmount'] ??
              businessDay['totalSettAmount'],
        ),
        discountAmount: _double(
          businessDay['discount_amount'] ??
              businessDay['discountAmount'] ??
              businessDay['totalDiscountAmount'],
        ),
        serviceFee: _double(
          businessDay['service_fee'] ?? businessDay['serviceFee'],
        ),
        refundAmount: _double(
          businessDay['refund_amount'] ??
              businessDay['refundAmount'] ??
              businessDay['totalRefundAmount'],
        ),
        payAmountGift: _double(
          businessDay['pay_amount_gift'] ?? businessDay['payAmountGift'],
        ),
      ),
      todayOrderCount: _int(
        businessDay['todayPaidOrderCount'] ??
            businessDay['todayOrderCount'] ??
            businessDay['orderCount'] ??
            json['todayCount'],
      ),
      successRechargeTotal: _double(
        businessDay['successRechargeTotal'] ??
            businessDay['memberRechargeSuccessAmount'] ??
            json['successRechargeTotal'],
      ),
      pendingTakeoutCount: _int(
        businessDay['pendingTakeoutCount'] ?? json['pendingTakeoutCount'],
      ),
    );
  }
}

Map<String, Object?> _map(Object? value) {
  return value is Map ? value.cast<String, Object?>() : <String, Object?>{};
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
