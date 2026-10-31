import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:kds_app/core/storage/kds_live_log.dart';
import 'package:kds_app/core/util/kds_log_redaction.dart';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';

/// 文件滚动日志（保留 7 天）；Web 端仅控制台 + 实时日志面板。
class KdsFileLogger {
  KdsFileLogger._();

  static Logger? _logger;
  static File? _currentFile;
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      info('KdsFileLogger initialized (web)');
      return;
    }
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/kds_logs');
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }
    await _pruneOldLogs(logDir);
    final name = _todayFileName();
    _currentFile = File('${logDir.path}/$name');
    _logger = Logger(
      filter: ProductionFilter(),
      printer: SimplePrinter(printTime: true),
      output: MultiOutput([
        ConsoleOutput(),
        FileOutput(file: _currentFile!),
      ]),
    );
    _initialized = true;
    info('KdsFileLogger initialized');
  }

  static void debug(String message) => _log(Level.debug, message);
  static void info(String message) => _log(Level.info, message);
  static void warn(String message) => _log(Level.warning, message);
  static void error(String message, [Object? err, StackTrace? stack]) {
    _log(Level.error, err == null ? message : '$message: $err');
    if (stack != null) {
      _log(Level.error, stack.toString());
    }
  }

  static void _log(Level level, String message) {
    final safe = redactSensitiveLog(message);
    KdsLiveLog.append(_levelTag(level), safe);
    if (!_initialized || kIsWeb) {
      // ignore: avoid_print
      print('[KDS] $safe');
      return;
    }
    _logger?.log(level, safe);
  }

  static String _levelTag(Level level) {
    if (level == Level.debug) return 'D';
    if (level == Level.warning) return 'W';
    if (level == Level.error) return 'E';
    return 'I';
  }

  static Future<File?> getLatestLogFile() async {
    if (kIsWeb) return null;
    if (_currentFile != null && await _currentFile!.exists()) {
      return _currentFile;
    }
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/kds_logs');
    if (!await logDir.exists()) return null;
    final files = await logDir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .cast<File>()
        .toList();
    if (files.isEmpty) return null;
    files.sort((a, b) => b.path.compareTo(a.path));
    return files.first;
  }

  static Future<List<File>> listLogFiles() async {
    if (kIsWeb) return const [];
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/kds_logs');
    if (!await logDir.exists()) return [];
    final files = await logDir
        .list()
        .where((e) => e is File && e.path.endsWith('.log'))
        .cast<File>()
        .toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  static String _todayFileName() {
    final now = DateTime.now();
    final d =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return 'kds_$d.log';
  }

  static Future<void> _pruneOldLogs(Directory logDir) async {
    final cutoff = DateTime.now().subtract(const Duration(days: 7));
    await for (final entity in logDir.list()) {
      if (entity is! File || !entity.path.endsWith('.log')) continue;
      final stat = await entity.stat();
      if (stat.modified.isBefore(cutoff)) {
        await entity.delete();
      }
    }
  }
}

class FileOutput extends LogOutput {
  FileOutput({required this.file});

  final File file;

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      file.writeAsStringSync('$line\n', mode: FileMode.append);
    }
  }
}
