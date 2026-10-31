import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/board/kds_line_wait_time.dart';
import 'package:kds_app/core/config/kds_screen_tag.dart';

void main() {
  group('KdsLineWaitTime', () {
    test('uses each dish serving duration as the overdue threshold', () {
      final line = {'serving_duration_minutes': 3};

      expect(KdsLineWaitTime.servingDurationMinutes(line), 3);
      expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 179), isFalse);
      expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 180), isTrue);
    });

    test('uses serving_duration_override with precedence over serving_duration_minutes', () {
      final line = {
        'serving_duration_override': 5,
        'serving_duration_minutes': 15,
      };

      expect(KdsLineWaitTime.servingDurationMinutes(line), 5);
      expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 299), isFalse);
      expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 300), isTrue);
    });

    test('uses serving_duration_override alone when present', () {
      final line = {'serving_duration_override': 4};

      expect(KdsLineWaitTime.servingDurationMinutes(line), 4);
      expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 239), isFalse);
      expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 240), isTrue);
    });

    test('falls back to serving_duration_minutes when serving_duration_override is invalid or null', () {
      for (final invalid in [null, 0, -2, 'invalid', '']) {
        final line = <String, dynamic>{
          if (invalid != null) 'serving_duration_override': invalid,
          'serving_duration_minutes': 8,
        };
        expect(KdsLineWaitTime.servingDurationMinutes(line), 8);
        expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 479), isFalse);
        expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 480), isTrue);
      }
    });

    test('supports string and num formats for serving duration', () {
      final line1 = {'serving_duration_override': '6'};
      expect(KdsLineWaitTime.servingDurationMinutes(line1), 6);
      expect(KdsLineWaitTime.isOverdue(line1, waitSeconds: 360), isTrue);

      final line2 = {'serving_duration_minutes': '7'};
      expect(KdsLineWaitTime.servingDurationMinutes(line2), 7);

      final line3 = {'serving_duration': 9};
      expect(KdsLineWaitTime.servingDurationMinutes(line3), 9);
      expect(KdsLineWaitTime.isOverdue(line3, waitSeconds: 540), isTrue);
    });

    test('does not overdue by default when serving duration is missing or invalid', () {
      for (final value in [null, 0, -1, 'invalid', '']) {
        final line = <String, dynamic>{
          if (value != null) 'serving_duration_minutes': value,
        };
        expect(KdsLineWaitTime.servingDurationMinutes(line), isNull);
        // 不再默认超时：未配置出餐时长时，即使等待时间极长也绝不超时
        expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 999999), isFalse);
      }

      for (final invalid in [null, 0, -1, 'invalid', '']) {
        final line = <String, dynamic>{
          if (invalid != null) 'serving_duration_override': invalid,
          'serving_duration_minutes': 0,
        };
        expect(KdsLineWaitTime.servingDurationMinutes(line), isNull);
        expect(KdsLineWaitTime.isOverdue(line, waitSeconds: 999999), isFalse);
      }
    });

    test('respects overdue_flag and is_overdue regardless of duration', () {
      expect(KdsLineWaitTime.isOverdue({'overdue_flag': true}, waitSeconds: 0), isTrue);
      expect(KdsLineWaitTime.isOverdue({'is_overdue': 1}, waitSeconds: 0), isTrue);
      expect(KdsLineWaitTime.isOverdue({'overdue_flag': 'true'}, waitSeconds: 0), isTrue);
      expect(KdsLineWaitTime.isOverdue({'overdue_flag': false}, waitSeconds: 0), isFalse);
    });

    test('frozen line uses completed_wait_seconds without live growth', () {
      final line = {
        'done_line': 1,
        'wait_seconds': 120,
        'completed_wait_seconds': 300,
        'fifo_seq': DateTime.now().millisecondsSinceEpoch - 600000,
      };
      expect(
        KdsLineWaitTime.resolveWaitSeconds(line, queue: BoardQueue.pendingCook),
        300,
      );
      expect(KdsLineWaitTime.isFrozen(line, queue: BoardQueue.pendingCook),
          isTrue);
    });

    test('done tab queue freezes wait even without done_line', () {
      final line = {
        'wait_seconds': 180,
        'fifo_seq': DateTime.now().millisecondsSinceEpoch - 900000,
      };
      expect(
        KdsLineWaitTime.resolveWaitSeconds(line, queue: BoardQueue.done),
        180,
      );
    });

    test('completed_at minus fifo_seq yields frozen wait', () {
      final start = DateTime.utc(2026, 6, 8, 10, 0);
      final done = DateTime.utc(2026, 6, 8, 10, 5);
      final line = {
        'fifo_seq': start.millisecondsSinceEpoch,
        'cooked_at': done.millisecondsSinceEpoch,
      };
      expect(
        KdsLineWaitTime.frozenWaitSeconds(line, queue: BoardQueue.pendingCook),
        300,
      );
    });

    test('order_time wins over fifo_seq for live wait start', () {
      final orderTime = DateTime.now().subtract(const Duration(minutes: 20));
      final handoffTime = DateTime.now().subtract(const Duration(minutes: 1));
      final line = {
        'order_time': orderTime.millisecondsSinceEpoch,
        'fifo_seq': handoffTime.millisecondsSinceEpoch,
      };

      expect(
        KdsLineWaitTime.resolveWaitSeconds(line, queue: BoardQueue.pendingCook),
        greaterThanOrEqualTo(19 * 60),
      );
      expect(
        KdsLineWaitTime.waitStartMs(line),
        orderTime.millisecondsSinceEpoch,
      );
    });

    test('stampQueueCompletion writes stage timestamp and frozen wait', () {
      final line = {
        'fifo_seq': DateTime.utc(2026, 6, 8, 10, 0).millisecondsSinceEpoch,
        'wait_seconds': 240,
      };
      final stamped = KdsLineWaitTime.stampQueueCompletion(
        line,
        queue: BoardQueue.pendingCook,
        completedAt: DateTime.utc(2026, 6, 8, 10, 4),
      );
      expect(
        stamped['cooked_at'],
        DateTime.utc(2026, 6, 8, 10, 4).millisecondsSinceEpoch,
      );
      expect(
        stamped['queue_completed_at'],
        DateTime.utc(2026, 6, 8, 10, 4).millisecondsSinceEpoch,
      );
      expect(stamped['completed_wait_seconds'], 240);
      expect(stamped['wait_seconds'], 240);
      expect(stamped['overdue_flag'], false);
    });

    test('stampQueueCompletion freezes wait from order_time not handoff time',
        () {
      final line = {
        'order_time': DateTime.utc(2026, 6, 8, 10, 0).millisecondsSinceEpoch,
        'fifo_seq': DateTime.utc(2026, 6, 8, 10, 19).millisecondsSinceEpoch,
      };
      final stamped = KdsLineWaitTime.stampQueueCompletion(
        line,
        queue: BoardQueue.pendingCook,
        completedAt: DateTime.utc(2026, 6, 8, 10, 20),
      );

      expect(stamped['completed_wait_seconds'], 20 * 60);
      expect(stamped['wait_seconds'], 20 * 60);
    });
  });
}
