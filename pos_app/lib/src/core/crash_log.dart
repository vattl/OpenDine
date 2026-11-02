import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 崩溃前的行为轨迹面包屑
class CrashBreadcrumb {
  CrashBreadcrumb({
    required this.timestamp,
    required this.category,
    required this.message,
    this.level = 'info',
    this.data,
  });

  final DateTime timestamp;
  final String category;
  final String message;
  final String level;
  final Map<String, Object?>? data;

  String get formattedTime {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'category': category,
    'message': message,
    'level': level,
    if (data != null && data!.isNotEmpty) 'data': data,
  };
}

/// 本地运行/崩溃日志：全局异常捕获 + 关键事件落盘（Windows / Android 通用）。
///
/// 日志目录与 KDS 本地数据同根：
/// - Windows：`%LOCALAPPDATA%\LaofeiCashier\logs\app.log`
/// - Android：`<应用支持目录>/LaofeiCashier/logs/app.log`
///
/// 崩溃原因以 `[ERROR]` 行 + 堆栈写入，超 1MB 滚动保留最近两份。
class CrashLog {
  CrashLog._();

  static final CrashLog instance = CrashLog._();

  static const int _maxBytes = 1024 * 1024;
  static const String fileName = 'app.log';
  static const String sessionStateFileName = 'session_state.json';
  static const String pendingNativeCrashFileName = 'pending_native_crash.json';

  Directory? _logDir;
  bool _initialized = false;
  static const int _maxContext = 12;
  final List<String> _context = [];

  /// 日志目录（初始化后有效）。
  Future<Directory> get logDirectory async {
    final dir = _logDir;
    if (dir != null) return dir;
    final root = await _applicationDataRoot();
    final logs = Directory(p.join(root.path, 'LaofeiCashier', 'logs'));
    await logs.create(recursive: true);
    _logDir = logs;
    return logs;
  }

  /// 日志文件完整路径（用于界面展示）。
  Future<String> get logFileLocation async {
    final dir = await logDirectory;
    return p.join(dir.path, fileName);
  }

  /// 初始化：打开日志文件并写启动行。可在应用入口调用一次。
  Future<void> init() async {
    if (_initialized) return;
    await logDirectory;
    _initialized = true;
    _recoverPreviousRunSync();
    _writeCurrentSessionSync();
    write(
      'INFO',
      '应用启动 ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}',
    );
  }

  /// 测试/自托管根目录初始化。
  @visibleForTesting
  Future<void> initWithRoot(Directory root) async {
    if (_initialized) return;
    final logs = Directory(p.join(root.path, 'LaofeiCashier', 'logs'));
    await logs.create(recursive: true);
    _logDir = logs;
    _initialized = true;
    _recoverPreviousRunSync();
    _writeCurrentSessionSync();
  }

  bool get isInitialized => _initialized;

  /// 同步写入模式无缓冲，无需额外 flush（保留接口兼容调用方）。
  @visibleForTesting
  Future<void> flush() async {}

  /// 重置状态（测试/退出时调用）。
  @visibleForTesting
  Future<void> dispose() async {
    await markCleanShutdown();
    _logDir = null;
    _initialized = false;
    _breadcrumbs.clear();
    _context.clear();
    _stateProviders.clear();
  }

  static const int _maxBreadcrumbs = 50;
  static const String crashReportFileName = 'last_crash_report.json';

  final List<CrashBreadcrumb> _breadcrumbs = [];
  final Map<String, Object? Function()> _stateProviders = {};

  /// 注册当前运行态上下文提供器（如当前门店、操作员、KDS 状态等）。
  void registerStateProvider(String key, Object? Function() provider) {
    _stateProviders[key] = provider;
  }

  /// 注销运行态上下文提供器。
  void unregisterStateProvider(String key) {
    _stateProviders.remove(key);
  }

  /// 记录一条结构化行为面包屑 (Breadcrumb)。
  /// 保留最近 50 条，崩溃时作为排查关键上下文一并输出并落盘。
  void recordBreadcrumb({
    required String category,
    required String message,
    String level = 'info',
    Map<String, Object?>? data,
  }) {
    final breadcrumb = CrashBreadcrumb(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      level: level,
      data: data == null || data.isEmpty ? null : Map.unmodifiable(data),
    );
    _breadcrumbs.add(breadcrumb);
    if (_breadcrumbs.length > _maxBreadcrumbs) {
      _breadcrumbs.removeAt(0);
    }
    // 兼容原有的 recordOperation
    _context.add('[${breadcrumb.formattedTime}] [$category] $message');
    if (_context.length > _maxContext) _context.removeAt(0);
    write('INFO', '[$category] $message');
  }

  /// 兼容旧调用：记录一次用户关键操作。
  void recordOperation(String message) {
    recordBreadcrumb(category: 'operation', message: message);
  }

  /// 获取当前所有 Breadcrumbs 快照（已防护）。
  List<CrashBreadcrumb> get breadcrumbsSnapshot =>
      List.unmodifiable(_breadcrumbs);

  /// 收集当前已注册的运行态快照。
  Map<String, Object?> collectStateSnapshot() {
    final snapshot = <String, Object?>{
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'locale': Platform.localeName,
      'timestamp': DateTime.now().toIso8601String(),
    };
    for (final entry in _stateProviders.entries) {
      try {
        snapshot[entry.key] = entry.value();
      } catch (e) {
        snapshot[entry.key] = '<failed to get state: $e>';
      }
    }
    return snapshot;
  }

  String _buildContextSnapshot({String? reason, StackTrace? stack}) {
    final buffer = StringBuffer('\n=== CRASH CONTEXT SNAPSHOT ===\n');
    if (reason != null) buffer.writeln('Reason: $reason');
    final state = collectStateSnapshot();
    buffer.writeln('App State:');
    for (final entry in state.entries) {
      buffer.writeln('  ${entry.key}: ${entry.value}');
    }
    buffer.writeln('Recent Breadcrumbs (${_breadcrumbs.length}):');
    if (_breadcrumbs.isEmpty) {
      buffer.writeln('  (none)');
    } else {
      for (final b in _breadcrumbs) {
        final dataStr = b.data != null ? ' ${jsonEncode(b.data)}' : '';
        buffer.writeln(
          '  [${b.formattedTime}][${b.category.toUpperCase()}][${b.level}] ${b.message}$dataStr',
        );
      }
    }
    buffer.writeln('==============================\n');
    return buffer.toString();
  }

  /// 同步转储独立的 JSON 崩溃报告，供技术支持快速分析或界面单独展示。
  void _dumpCrashReportSync(
    String reason,
    StackTrace? stack, {
    String source = 'dart',
    Map<String, Object?>? diagnostics,
  }) {
    try {
      final dir = _logDir;
      if (dir == null) return;
      final report = {
        'schema_version': 2,
        'event_id': '${DateTime.now().microsecondsSinceEpoch}-${pid}',
        'timestamp': DateTime.now().toIso8601String(),
        'source': source,
        'reason': reason,
        'stack': stack?.toString(),
        'app_state': collectStateSnapshot(),
        'breadcrumbs': _breadcrumbs.map((b) => b.toJson()).toList(),
        if (diagnostics != null && diagnostics.isNotEmpty)
          'diagnostics': diagnostics,
      };
      final reportFile = File(p.join(dir.path, crashReportFileName));
      reportFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    } catch (_) {
      // 避免二次报错
    }
  }

  /// 标记本次会话已正常退出。Windows runner 也会在消息循环正常结束时兜底清理。
  Future<void> markCleanShutdown() async {
    final dir = _logDir;
    if (dir == null) return;
    try {
      final file = File(p.join(dir.path, sessionStateFileName));
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // 退出阶段不再抛出诊断异常。
    }
  }

  void _recoverPreviousRunSync() {
    final dir = _logDir;
    if (dir == null) return;

    final nativeCrash = _consumePendingNativeCrashSync(dir);
    if (!Platform.isWindows) return;
    final sessionFile = File(p.join(dir.path, sessionStateFileName));
    if (!sessionFile.existsSync()) return;

    final previous = _readJsonObjectSync(sessionFile);
    if (nativeCrash) {
      write('WARN', '检测到上次会话未清理；已有 Windows 原生崩溃转储，以原生报告为准');
      return;
    }

    final diagnostics = <String, Object?>{
      'classification': 'possible_crash_or_forced_termination',
      'note': '该信号无法区分程序崩溃、任务管理器强制结束、断电或系统重启。',
      if (previous != null) ...{
        'previous_session_id': previous['session_id'],
        'previous_started_at': previous['started_at'],
        'previous_pid': previous['pid'],
      },
    };
    const reason = '检测到上次运行未正常退出（可能为崩溃、强制结束、断电或系统重启）';
    write('ERROR', reason);
    _dumpCrashReportSync(
      reason,
      null,
      source: 'unclean_exit',
      diagnostics: diagnostics,
    );
  }

  bool _consumePendingNativeCrashSync(Directory dir) {
    final pending = File(p.join(dir.path, pendingNativeCrashFileName));
    if (!pending.existsSync()) return false;
    try {
      final details = _readJsonObjectSync(pending);
      if (details == null) {
        write('WARN', '发现无法解析的 Windows 原生崩溃标记，已保留运行日志');
        return false;
      }
      const reason = '检测到 Windows 原生进程崩溃（已生成 minidump）';
      write('ERROR', reason);
      _dumpCrashReportSync(
        reason,
        null,
        source: 'native_windows',
        diagnostics: details,
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        if (pending.existsSync()) pending.deleteSync();
      } catch (_) {
        // 下次启动再次尝试消费。
      }
    }
  }

  Map<String, Object?>? _readJsonObjectSync(File file) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } catch (_) {
      return null;
    }
  }

  void _writeCurrentSessionSync() {
    final dir = _logDir;
    if (dir == null || !Platform.isWindows) return;
    try {
      final now = DateTime.now();
      final session = <String, Object?>{
        'session_id': '${now.microsecondsSinceEpoch}-${pid}',
        'started_at': now.toIso8601String(),
        'pid': pid,
        'status': 'running',
        'platform': Platform.operatingSystem,
      };
      File(
        p.join(dir.path, sessionStateFileName),
      ).writeAsStringSync(jsonEncode(session), flush: true);
    } catch (_) {
      // 会话探针失败不影响收银主流程。
    }
  }

  /// 追加一行日志（含可选堆栈），崩溃/异常用 ERROR 级别。
  ///
  /// 统一使用同步追加写入：顺序确定、崩溃/强杀时必定落盘，
  /// 且避免多句柄并发 append 的定位竞态。
  void write(String level, String message, [StackTrace? stack]) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final ts =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
    final buffer = StringBuffer('[$ts][$level] $message\n');
    if (stack != null) {
      final lines = stack.toString().split('\n');
      for (final line in lines.take(40)) {
        buffer.write('    $line\n');
      }
    }
    final line = buffer.toString();
    try {
      final dir = _logDir;
      if (dir == null) return;
      final file = File(p.join(dir.path, fileName));
      if (level == 'ERROR') {
        final contextSnapshot = _buildContextSnapshot(
          reason: message,
          stack: stack,
        );
        file.writeAsStringSync(
          line + contextSnapshot,
          mode: FileMode.append,
          flush: true,
        );
        _dumpCrashReportSync(message, stack);
      } else {
        file.writeAsStringSync(line, mode: FileMode.append, flush: true);
      }
      if (file.lengthSync() > _maxBytes) {
        final rotated = File(p.join(dir.path, 'app.1.log'));
        if (rotated.existsSync()) rotated.deleteSync();
        file.renameSync(rotated.path);
      }
    } catch (_) {
      // 落盘失败只能静默，避免递归进全局错误处理器。
    }
  }

  /// 读取独立崩溃报告（如果存在）。
  Future<Map<String, Object?>?> readLastCrashReport() async {
    final dir = _logDir;
    if (dir == null) return null;
    final file = File(p.join(dir.path, crashReportFileName));
    if (!await file.exists()) return null;
    try {
      final content = await file.readAsString();
      return jsonDecode(content) as Map<String, Object?>?;
    } catch (_) {
      return null;
    }
  }

  /// 崩溃报告文件完整路径（用于界面展示）。
  Future<String> get crashReportLocation async {
    final dir = await logDirectory;
    return p.join(dir.path, crashReportFileName);
  }

  /// 读取最近 [maxLines] 行日志（用于界面展示）。
  Future<String> readRecent({int maxLines = 500}) async {
    final dir = _logDir;
    if (dir == null) return '（日志尚未初始化）';
    final file = File(p.join(dir.path, fileName));
    if (!await file.exists()) return '（暂无日志）';
    final lines = await file.readAsLines();
    if (lines.length <= maxLines) return lines.join('\n');
    return lines.sublist(lines.length - maxLines).join('\n');
  }

  static Future<Directory> _applicationDataRoot() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        return await getApplicationSupportDirectory();
      } catch (_) {
        // 非 Flutter 宿主/测试环境回退
        if (Platform.isAndroid) {
          return Directory(p.join(Directory.systemTemp.parent.path, 'files'));
        }
      }
    }
    final appData = Platform.environment['LOCALAPPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) return Directory(appData);
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      return Directory(p.join(home, '.local', 'share'));
    }
    return Directory.current;
  }
}

/// 安装全局崩溃钩子（应用入口调用一次）：
/// - FlutterError.onError：框架异常（落盘，保留原 handler 或默认报错）
/// - PlatformDispatcher.onError：平台/引擎异常（落盘并返回 true，阻止原生进程直接异常退出）
/// - ErrorWidget.builder：组件构建异常降级展示，防止红屏/崩溃扩散
void installGlobalErrorHandlers() {
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    CrashLog.instance.write(
      'ERROR',
      'Flutter error: ${details.exception}',
      details.stack,
    );
    if (previousOnError != null) {
      previousOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  ui.PlatformDispatcher.instance.onError = (error, stack) {
    CrashLog.instance.write('ERROR', 'Platform error: $error', stack);
    // 返回 true 告知 Flutter 引擎异常已被处理，防止 Windows/原生宿主直接终止进程
    return true;
  };

  // 界面渲染异常保护：避免出现全局致命红屏/白屏或引擎渲染挂起，并提供自愈逃生入口
  ErrorWidget.builder = (FlutterErrorDetails details) {
    CrashLog.instance.write(
      'ERROR',
      'Widget build error: ${details.exception}',
      details.stack,
    );
    return CashierCrashRecoveryWidget(details: details);
  };
}

/// 全局崩溃自愈逃生视图：提供返回上一页、返回收银主页、重试刷新等逃生通道，
/// 彻底避免收银员被死锁在拦截屏而只能后台强退应用。
class CashierCrashRecoveryWidget extends StatefulWidget {
  const CashierCrashRecoveryWidget({super.key, required this.details});

  final FlutterErrorDetails details;

  @override
  State<CashierCrashRecoveryWidget> createState() =>
      _CashierCrashRecoveryWidgetState();
}

class _CashierCrashRecoveryWidgetState
    extends State<CashierCrashRecoveryWidget> {
  bool _retrying = false;

  void _handleRetry() {
    setState(() => _retrying = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _retrying = false);
      }
    });
  }

  void _handleBack(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      _handleHome(context);
    }
  }

  void _handleHome(BuildContext context) {
    try {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Material(
      color: const Color(0xfff8f9fa),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xffd97706),
                  size: 56,
                ),
                const SizedBox(height: 16),
                const Text(
                  '界面渲染暂时遇到问题',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xff1f2937),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${widget.details.exception}',
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Color(0xff4b5563)),
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.center,
                  children: [
                    if (canPop)
                      OutlinedButton.icon(
                        key: const Key('crash-recovery-back-button'),
                        onPressed: () => _handleBack(context),
                        icon: const Icon(Icons.arrow_back),
                        label: const Text('返回上一页'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    FilledButton.icon(
                      key: const Key('crash-recovery-home-button'),
                      onPressed: () => _handleHome(context),
                      icon: const Icon(Icons.home_outlined),
                      label: const Text('返回收银主页'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        backgroundColor: const Color(0xff2563eb),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      key: const Key('crash-recovery-retry-button'),
                      onPressed: _retrying ? null : _handleRetry,
                      icon: _retrying
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('重试刷新'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
