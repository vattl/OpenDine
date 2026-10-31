import 'package:kds_app/core/config/kds_screen_tag.dart';

/// Resolves dish wait time and freezes it after a line leaves a queue.
abstract final class KdsLineWaitTime {
  /// 收银端 KDS v2 的菜品级超时阈值备用常量（仅做历史兼容保留，默认不再使用兜底超时）。
  static const fallbackServingDurationMinutes = 10;

  /// 解析菜品出餐时长（分钟）。
  /// 统一以后端配置为准：
  /// 1. 优先使用门店出餐时长覆盖 serving_duration_override；
  /// 2. 其次使用菜品出餐时长 serving_duration_minutes；
  /// 3. 兼容字段 serving_duration。
  /// 若后端未配置出餐时长（无字段、null、0 或负数），返回 null，表示该菜品未设置超时阈值。
  static int? servingDurationMinutes(Map<String, dynamic> line) {
    final overrideVal = _int(line['serving_duration_override']);
    if (overrideVal != null && overrideVal > 0) {
      return overrideVal;
    }
    final rawMinutes = _int(line['serving_duration_minutes']);
    if (rawMinutes != null && rawMinutes > 0) {
      return rawMinutes;
    }
    final legacyDuration = _int(line['serving_duration']);
    if (legacyDuration != null && legacyDuration > 0) {
      return legacyDuration;
    }
    return null;
  }

  /// 判断菜品是否超时：
  /// 1. 若后端显式标记了超时（overdue_flag 或 is_overdue 为 true），直接判定为超时；
  /// 2. 统一以后端出餐时长为准，若未设置有效出餐时长（servingDurationMinutes 为 null 或 <= 0），
  ///    则不再默认超时，直接返回 false；
  /// 3. 若有有效出餐时长，则根据 waitSeconds >= durationMinutes * 60 进行判定。
  static bool isOverdue(
    Map<String, dynamic> line, {
    required int waitSeconds,
  }) {
    if (_flag(line['overdue_flag']) || _flag(line['is_overdue'])) {
      return true;
    }
    final duration = servingDurationMinutes(line);
    if (duration == null || duration <= 0) {
      return false;
    }
    return waitSeconds >= duration * 60;
  }

  static int? _int(dynamic raw) {
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  static bool _flag(dynamic raw) {
    if (raw == true) return true;
    if (raw is num) return raw != 0;
    final text = raw?.toString().trim().toLowerCase();
    return text == '1' || text == 'true';
  }

  static DateTime? parseDateTime(dynamic raw) {
    if (raw == null) return null;
    final ms = _int(raw);
    if (ms != null && ms > 0) {
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    final text = '$raw'.trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text.replaceFirst(' ', 'T'));
  }

  /// Completed, archived, or done-tab rows should not keep growing.
  static bool isFrozen(
    Map<String, dynamic> line, {
    BoardQueue? queue,
    bool doneLine = false,
  }) {
    if (doneLine || _flag(line['done_line'])) return true;
    if (queue == BoardQueue.done) return true;
    if (line['workflow_queue']?.toString() == BoardQueue.done.apiValue) {
      return true;
    }
    if (_flag(line['archived'])) return true;
    return false;
  }

  /// Completion timestamp for the current workflow stage.
  static DateTime? queueCompletedAt(
    Map<String, dynamic> line, {
    BoardQueue? queue,
  }) {
    for (final key in const [
      'queue_completed_at',
      'completed_at',
      'archived_at',
    ]) {
      final dt = parseDateTime(line[key]);
      if (dt != null) return dt;
    }

    switch (queue) {
      case BoardQueue.pendingPrep:
        return parseDateTime(line['prep_completed_at'] ?? line['prep_at']);
      case BoardQueue.pendingCook:
        return parseDateTime(
          line['cooked_at'] ?? line['cook_completed_at'] ?? line['done_at'],
        );
      case BoardQueue.readyServe:
        return parseDateTime(line['served_at'] ?? line['serve_completed_at']);
      case BoardQueue.done:
        return parseDateTime(
          line['archived_at'] ??
              line['served_at'] ??
              line['cooked_at'] ??
              line['done_at'],
        );
      case null:
        return parseDateTime(
          line['archived_at'] ??
              line['served_at'] ??
              line['cooked_at'] ??
              line['done_at'] ??
              line['prep_completed_at'] ??
              line['prep_at'],
        );
    }
  }

  /// The business wait clock starts from the dish/order time, not from the
  /// current workflow handoff time. `fifo_seq` is only a final fallback for
  /// legacy payloads that do not include order timestamps.
  static DateTime? waitStartAt(Map<String, dynamic> line) {
    return parseDateTime(
      line['order_time'] ??
          line['first_order_time'] ??
          line['created_at'] ??
          line['ticket_created_at'] ??
          line['add_dish_time'] ??
          line['fifo_seq'],
    );
  }

  static int _elapsedSince(DateTime start, DateTime end) {
    return end.difference(start).inSeconds.clamp(0, 1 << 31);
  }

  static int _liveWaitSinceStart(Map<String, dynamic> line) {
    final start = waitStartAt(line);
    if (start != null) return _elapsedSince(start, DateTime.now());
    return 0;
  }

  static int? waitStartMs(Map<String, dynamic> line) {
    return waitStartAt(line)?.millisecondsSinceEpoch;
  }

  /// Frozen wait for completed rows. Prefer the API snapshot; otherwise compute
  /// from queue completion time minus the original order time.
  static int frozenWaitSeconds(
    Map<String, dynamic> line, {
    BoardQueue? queue,
  }) {
    final completedWait = line['completed_wait_seconds'];
    if (completedWait is num && completedWait >= 0) {
      return completedWait.toInt();
    }

    final completedAt = queueCompletedAt(line, queue: queue);
    if (completedAt != null) {
      final start = waitStartAt(line);
      if (start != null) return _elapsedSince(start, completedAt);
    }

    final api = _int(line['wait_seconds']);
    if (api != null && api >= 0) return api;

    return 0;
  }

  /// Pending rows grow locally; completed rows stay frozen.
  static int resolveWaitSeconds(
    Map<String, dynamic> line, {
    BoardQueue? queue,
    bool addDishLine = false,
    bool doneLine = false,
  }) {
    if (isFrozen(line, queue: queue, doneLine: doneLine)) {
      return frozenWaitSeconds(line, queue: queue);
    }

    final live = _liveWaitSinceStart(line);
    if (live > 0) return live;

    final api = _int(line['wait_seconds']);
    if (api != null && api >= 0) return api;
    return 0;
  }

  /// Writes local completion fields during optimistic advance. The frozen wait
  /// is based on the original order time so workflow handoff never resets it.
  static Map<String, dynamic> stampQueueCompletion(
    Map<String, dynamic> line, {
    required BoardQueue queue,
    DateTime? completedAt,
  }) {
    final copy = Map<String, dynamic>.from(line);
    final at = completedAt ?? DateTime.now();
    final completedAtMs = at.millisecondsSinceEpoch;
    final start = waitStartAt(copy);
    final wait = start != null
        ? _elapsedSince(start, at)
        : resolveWaitSeconds(copy, queue: queue);

    copy['completed_wait_seconds'] = wait;
    copy['queue_completed_at'] = completedAtMs;

    switch (queue) {
      case BoardQueue.pendingPrep:
        copy['prep_completed_at'] = completedAtMs;
      case BoardQueue.pendingCook:
        copy['cooked_at'] = completedAtMs;
      case BoardQueue.readyServe:
        copy['served_at'] = completedAtMs;
      case BoardQueue.done:
        copy['archived_at'] = completedAtMs;
    }

    copy['wait_seconds'] = wait;
    copy['overdue_flag'] = false;
    return copy;
  }
}
