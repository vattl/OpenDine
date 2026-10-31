/// Builds query parameters for the existing business report endpoints.
///
/// The cashier selects business dates only. The server resolves each date to
/// the authenticated shop's `[D settle_time, D+1 settle_time)` window.
String formatBusinessReportDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

Map<String, Object?> dailyBusinessReportQuery(
  DateTime businessDate, {
  bool? detail,
}) => {
      'date': formatBusinessReportDate(businessDate),
      if (detail != null) 'detail': detail,
    };

Map<String, Object?> weeklyBusinessReportQuery(
  DateTime startBusinessDate,
  DateTime endBusinessDate,
) => {
      'startDate': formatBusinessReportDate(startBusinessDate),
      'endDate': formatBusinessReportDate(endBusinessDate),
    };

Map<String, Object?> monthlyBusinessReportQuery(DateTime businessMonth) => {
      'year': businessMonth.year,
      'month': businessMonth.month,
    };
