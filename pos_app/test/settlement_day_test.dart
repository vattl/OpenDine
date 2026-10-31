import 'package:admin_panel_flutter/src/core/settlement_day.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settlement day contract', () {
    test('uses the window end date instead of the cross-day window start', () {
      expect(
        settlementDateFromApiWindowEnd('2026-09-10T04:00:00+08:00'),
        '2026-09-10',
      );
    });

    test('falls back to the most recently completed 04:00 settlement', () {
      expect(
        formatSettlementDate(mostRecentCompletedSettlementDate(
          now: DateTime(2026, 9, 10, 3, 59),
        )),
        '2026-09-09',
      );
      expect(
        formatSettlementDate(mostRecentCompletedSettlementDate(
          now: DateTime(2026, 9, 10, 4),
        )),
        '2026-09-10',
      );
    });
  });
}
