import 'package:flutter_test/flutter_test.dart';
import 'package:admin_panel_flutter/src/features/reports/data/business_report_query.dart';

void main() {
  test('日报只传营业日，不在客户端计算时间窗口', () {
    final query = dailyBusinessReportQuery(DateTime(2026, 10, 2, 23, 30));

    expect(query, {'date': '2026-10-02'});
    expect(query.containsKey('startTime'), isFalse);
    expect(query.containsKey('endTime'), isFalse);
    expect(query.containsKey('settleTime'), isFalse);
  });

  test('周报只传首尾营业日', () {
    final query = weeklyBusinessReportQuery(
      DateTime(2026, 9, 28),
      DateTime(2026, 10, 4),
    );

    expect(query, {
      'startDate': '2026-09-28',
      'endDate': '2026-10-04',
    });
  });

  test('月报复用现有年月参数', () {
    expect(monthlyBusinessReportQuery(DateTime(2026, 2, 18)), {
      'year': 2026,
      'month': 2,
    });
  });
}
