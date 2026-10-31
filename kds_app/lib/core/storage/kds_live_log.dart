import 'dart:async';

/// 内存环形缓冲，供 UI 实时展示（与文件日志并行）
class KdsLiveLogEntry {
  KdsLiveLogEntry({
    required this.time,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final String level;
  final String message;

  bool get isWs => message.contains('[WS]');
}

class KdsLiveLog {
  KdsLiveLog._();

  static const maxEntries = 800;

  static final List<KdsLiveLogEntry> buffer = [];
  static final _controller = StreamController<KdsLiveLogEntry>.broadcast();

  static Stream<KdsLiveLogEntry> get stream => _controller.stream;
  static int get length => buffer.length;

  static void append(String level, String message) {
    final entry = KdsLiveLogEntry(
      time: DateTime.now(),
      level: level,
      message: message,
    );
    buffer.add(entry);
    while (buffer.length > maxEntries) {
      buffer.removeAt(0);
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
  }

  static void clear() {
    buffer.clear();
    if (!_controller.isClosed) {
      _controller.add(
        KdsLiveLogEntry(
          time: DateTime.now(),
          level: 'I',
          message: '[LOG] buffer cleared',
        ),
      );
    }
  }
}
