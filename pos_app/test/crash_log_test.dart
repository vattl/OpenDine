import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel_flutter/src/core/crash_log.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('crash_log_test_');
  });

  tearDown(() async {
    await CrashLog.instance.dispose();
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('CrashLog writes INFO and ERROR entries with stack to app.log', () async {
    await CrashLog.instance.initWithRoot(tempRoot);
    expect(CrashLog.instance.isInitialized, isTrue);

    CrashLog.instance.write('INFO', '应用启动 test');
    CrashLog.instance.write(
      'ERROR',
      'Flutter error: TestCrashException',
      StackTrace.fromString('line one\nline two\nline three'),
    );

    final content = await CrashLog.instance.readRecent();
    expect(content, contains('[INFO] 应用启动 test'));
    expect(content, contains('[ERROR] Flutter error: TestCrashException'));
    expect(content, contains('line one'));
    expect(content, contains('line two'));

    final location = await CrashLog.instance.logFileLocation;
    expect(location, contains('LaofeiCashier'));
    expect(location, endsWith('app.log'));
    expect(await File(location).exists(), isTrue);
  });

  test('CrashLog readRecent caps to maxLines', () async {
    await CrashLog.instance.initWithRoot(tempRoot);
    for (var i = 0; i < 30; i++) {
      CrashLog.instance.write('INFO', 'line-$i');
    }
    await CrashLog.instance.flush();
    final content = await CrashLog.instance.readRecent(maxLines: 5);
    final lines = content.split('\n').where((l) => l.isNotEmpty).toList();
    expect(lines.length, 5);
    expect(lines.last, contains('line-29'));
    expect(lines.first, contains('line-25'));
  });

  test('CrashLog maintains breadcrumbs ring buffer up to 50 items', () async {
    await CrashLog.instance.initWithRoot(tempRoot);
    for (var i = 0; i < 60; i++) {
      CrashLog.instance.recordBreadcrumb(
        category: 'test',
        message: 'event-$i',
        data: {'seq': i},
      );
    }
    final breadcrumbs = CrashLog.instance.breadcrumbsSnapshot;
    expect(breadcrumbs.length, 50);
    expect(breadcrumbs.first.message, 'event-10');
    expect(breadcrumbs.last.message, 'event-59');
    expect(breadcrumbs.last.data?['seq'], 59);
  });

  test('CrashLog dumps last_crash_report.json and context snapshot on ERROR', () async {
    await CrashLog.instance.initWithRoot(tempRoot);
    CrashLog.instance.registerStateProvider('shop', () => {
      'shop_id': 99,
      'shop_name': '测试分店',
    });
    CrashLog.instance.recordBreadcrumb(
      category: 'order',
      message: '开台完成: A01',
      data: {'table': 'A01'},
    );
    CrashLog.instance.recordBreadcrumb(
      category: 'api',
      message: 'API失败: POST /orders (500)',
      level: 'error',
    );

    // 触发致命异常记录
    CrashLog.instance.write(
      'ERROR',
      'Platform error: Fatal Database Corruption',
      StackTrace.fromString('dummy stack 1\ndummy stack 2'),
    );

    // 验证 app.log 中是否包含完整的 CRASH CONTEXT SNAPSHOT
    final logContent = await CrashLog.instance.readRecent();
    expect(logContent, contains('=== CRASH CONTEXT SNAPSHOT ==='));
    expect(logContent, contains('Reason: Platform error: Fatal Database Corruption'));
    expect(logContent, contains('shop_id: 99'));
    expect(logContent, contains('测试分店'));
    expect(logContent, contains('开台完成: A01'));
    expect(logContent, contains('API失败: POST /orders (500)'));

    // 验证独立的 last_crash_report.json
    final report = await CrashLog.instance.readLastCrashReport();
    expect(report, isNotNull);
    expect(report!['reason'], 'Platform error: Fatal Database Corruption');
    expect(report['stack'], contains('dummy stack 1'));
    final appState = report['app_state'] as Map<String, dynamic>;
    expect((appState['shop'] as Map<String, dynamic>)['shop_name'], '测试分店');
    final breadcrumbs = report['breadcrumbs'] as List<dynamic>;
    expect(breadcrumbs.length, 2);
    expect(breadcrumbs.first['message'], '开台完成: A01');
    expect(breadcrumbs.last['message'], 'API失败: POST /orders (500)');

    final reportLocation = await CrashLog.instance.crashReportLocation;
    expect(await File(reportLocation).exists(), isTrue);
  });

  test('CrashLog detects a previous unclean session on next startup', () async {
    final logs = Directory(
      '${tempRoot.path}${Platform.pathSeparator}LaofeiCashier${Platform.pathSeparator}logs',
    );
    await logs.create(recursive: true);
    final sessionFile = File(
      '${logs.path}${Platform.pathSeparator}session_state.json',
    );
    await sessionFile.writeAsString(
      jsonEncode({
        'session_id': 'previous-session',
        'started_at': '2026-10-04T08:00:00.000',
        'pid': 4321,
        'status': 'running',
      }),
    );

    await CrashLog.instance.initWithRoot(tempRoot);

    final report = await CrashLog.instance.readLastCrashReport();
    expect(report, isNotNull);
    expect(report!['source'], 'unclean_exit');
    expect(report['reason'], contains('上次运行未正常退出'));
    expect(
      (report['diagnostics'] as Map<String, dynamic>)['previous_session_id'],
      'previous-session',
    );

    final currentSession =
        jsonDecode(await sessionFile.readAsString()) as Map<String, dynamic>;
    expect(currentSession['status'], 'running');
    expect(currentSession['session_id'], isNot('previous-session'));

    await CrashLog.instance.markCleanShutdown();
    expect(await sessionFile.exists(), isFalse);
  });

  test('CrashLog imports a pending Windows native crash report', () async {
    final logs = Directory(
      '${tempRoot.path}${Platform.pathSeparator}LaofeiCashier${Platform.pathSeparator}logs',
    );
    await logs.create(recursive: true);
    final pending = File(
      '${logs.path}${Platform.pathSeparator}pending_native_crash.json',
    );
    await pending.writeAsString(
      jsonEncode({
        'captured_at': '2026-10-04T08:30:00.000',
        'exception_code': '0xC0000005',
        'exception_address': '0x00007FF612341234',
        'process_id': 7788,
        'minidump_path':
            '${logs.path}${Platform.pathSeparator}native_crash_test.dmp',
      }),
    );

    await CrashLog.instance.initWithRoot(tempRoot);

    final report = await CrashLog.instance.readLastCrashReport();
    expect(report, isNotNull);
    expect(report!['source'], 'native_windows');
    expect(report['reason'], contains('Windows 原生进程崩溃'));
    final diagnostics = report['diagnostics'] as Map<String, dynamic>;
    expect(diagnostics['exception_code'], '0xC0000005');
    expect(diagnostics['process_id'], 7788);
    expect(await pending.exists(), isFalse);
  });
}
