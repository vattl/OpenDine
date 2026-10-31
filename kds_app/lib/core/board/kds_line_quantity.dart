import 'package:kds_app/core/config/kds_screen_tag.dart';

/// 按 OpenAPI KdsOverviewLine 解析当前队列展示数量
class KdsLineQuantity {
  KdsLineQuantity._();

  static int? _nonNegativeInt(dynamic raw) {
    int? v;
    if (raw is num) {
      v = raw.toInt();
    } else if (raw is String) {
      v = int.tryParse(raw.trim());
    }
    if (v == null) return null;
    return v >= 0 ? v : null;
  }

  static int forQueue(Map<String, dynamic> line, BoardQueue queue) {
    switch (queue) {
      case BoardQueue.pendingPrep:
        if (line.containsKey('prep_remaining')) {
          final v = _nonNegativeInt(line['prep_remaining']);
          if (v != null) return v;
        }
        final display = _nonNegativeInt(line['quantity']);
        if (display != null) return display;
        return _calcPrepRemaining(line);
      case BoardQueue.pendingCook:
        if (line.containsKey('cook_remaining')) {
          final v = _nonNegativeInt(line['cook_remaining']);
          if (v != null) return v;
        }
        final display = _nonNegativeInt(line['quantity']);
        if (display != null) return display;
        return _calcCookRemaining(line);
      case BoardQueue.readyServe:
        if (line.containsKey('remaining_quantity')) {
          final v = _nonNegativeInt(line['remaining_quantity']);
          if (v != null) return v;
        }
        return _nonNegativeInt(line['quantity']) ?? 0;
      case BoardQueue.done:
        return _nonNegativeInt(line['quantity']) ??
            _nonNegativeInt(line['line_quantity']) ??
            0;
    }
  }

  static int forGroup(
    Map<String, dynamic> group,
    List<Map<String, dynamic>> lines,
    BoardQueue queue,
  ) {
    int sumLines() {
      if (lines.isEmpty) return 0;
      return lines.fold<int>(0, (sum, line) => sum + forQueue(line, queue));
    }

    if (queue == BoardQueue.readyServe) {
      final rem = _nonNegativeInt(group['remaining_quantity']);
      if (rem != null) return rem;
      final groupQty = _nonNegativeInt(group['quantity']);
      if (groupQty != null && groupQty > 0) return groupQty;
      return sumLines();
    }

    final groupQty = _nonNegativeInt(group['quantity']);
    if (groupQty != null && groupQty > 0) return groupQty;

    final fromLines = sumLines();
    if (fromLines > 0) return fromLines;

    if (groupQty != null) return groupQty;
    return 0;
  }

  static int _calcPrepRemaining(Map<String, dynamic> line) {
    final lineQty = _nonNegativeInt(line['line_quantity']) ??
        _nonNegativeInt(line['quantity']) ??
        0;
    final prep = _nonNegativeInt(line['prep_quantity']) ?? 0;
    final rem = lineQty - prep;
    return rem > 0 ? rem : 0;
  }

  static int _calcCookRemaining(Map<String, dynamic> line) {
    final lineQty = orderLineTotal(line);
    final cooked = _nonNegativeInt(line['cooked_quantity']) ?? 0;
    final rem = lineQty - cooked;
    return rem > 0 ? rem : 0;
  }

  /// 明细行总份数（优先 line_quantity）
  static int orderLineTotal(Map<String, dynamic> line) {
    final lineQty = _nonNegativeInt(line['line_quantity']);
    if (lineQty != null && lineQty > 0) return lineQty;
    return _nonNegativeInt(line['quantity']) ?? 0;
  }

  /// 当前队列下本步已推进份数（配菜/制作/传菜）
  static int orderLineCompleted(Map<String, dynamic> line, BoardQueue queue) {
    switch (queue) {
      case BoardQueue.pendingPrep:
        return _nonNegativeInt(line['prep_quantity']) ?? 0;
      case BoardQueue.pendingCook:
        return _nonNegativeInt(line['cooked_quantity']) ?? 0;
      case BoardQueue.readyServe:
        return _nonNegativeInt(line['served_quantity']) ?? 0;
      case BoardQueue.done:
        return orderLineTotal(line);
    }
  }
}
