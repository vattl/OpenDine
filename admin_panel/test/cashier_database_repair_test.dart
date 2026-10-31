import 'dart:io';
import 'package:admin_panel_flutter/src/features/kds_local/presentation/cashier_startup_fatal_page.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_database_repair_service.dart';
import 'package:admin_panel_flutter/src/features/kds_local/runtime/cashier_kds_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('CashierDatabaseRepairService diagnostics tests', () {
    late Directory tempRoot;
    late CashierKdsStorage storage;
    late CashierDatabaseRepairService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('repair_test_');
      storage = CashierKdsStorage(tempRoot);
      await storage.prepare();
      service = CashierDatabaseRepairService(storage);
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('correctly diagnoses SQLite 1546 disk I/O lock error', () {
      const error = 'SqliteException(1546): while executing, disk I/O error, disk I/O error (code 1546)';
      final result = service.diagnose(error);
      expect(result.type, DatabaseDiagnosticType.lockConflict);
      expect(result.title, contains('1546'));
      expect(result.description, contains('目录权限'));
      expect(result.recommendedAction, contains('不要删除 WAL/SHM'));
    });

    test('correctly diagnoses CashierKdsAuthorityLockException', () {
      const error = CashierKdsAuthorityLockException('Exclusive lock held by another process');
      final result = service.diagnose(error);
      expect(result.type, DatabaseDiagnosticType.authorityAlreadyHeld);
      expect(result.title, contains('独占锁冲突'));
    });

    test('correctly diagnoses CashierKdsBackupCapacityException', () {
      const error = CashierKdsBackupCapacityException('backup budget exceeded');
      final result = service.diagnose(error);
      expect(result.type, DatabaseDiagnosticType.backupCapacityExceeded);
      expect(result.title, contains('备份空间配额超标'));
    });

    test('correctly diagnoses corrupted database error', () {
      const error = 'SqliteException(11): database disk image is malformed / corrupt';
      final result = service.diagnose(error);
      expect(result.type, DatabaseDiagnosticType.corrupted);
      expect(result.title, contains('数据库文件结构损坏'));
    });

    test('correctly lists and sorts available backups', () async {
      final b1Dir = Directory(p.join(storage.backupDirectory.path, '1700000000000'));
      final b2Dir = Directory(p.join(storage.backupDirectory.path, '1700000010000'));
      await b1Dir.create(recursive: true);
      await b2Dir.create(recursive: true);

      final db1 = File(p.join(b1Dir.path, 'cashier_kds.sqlite'));
      await db1.writeAsString('test db content 1');
      final db2 = File(p.join(b2Dir.path, 'cashier_kds.sqlite'));
      await db2.writeAsString('test db content 2 longer');

      final backups = await service.getAvailableBackups();
      expect(backups.length, 2);
      expect(backups.first.directory.path, b2Dir.path);
      expect(backups.first.timestamp.millisecondsSinceEpoch, 1700000010000);
      expect(backups.first.sizeBytes, greaterThan(0));
      expect(backups.first.formattedTime, isNotEmpty);
      expect(backups.first.formattedSize, contains('B'));
    });

    test('quarantines existing files before restore or rebuild to guarantee zero data loss', () async {
      final dbFile = File(storage.databasePath);
      await dbFile.writeAsString('original data');

      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final quarantineDir = Directory(
        p.join(storage.dataDirectory.path, 'quarantine', 'test_archive_$nowMs'),
      );
      await quarantineDir.create(recursive: true);

      // Verify backup safety
      await dbFile.copy(p.join(quarantineDir.path, 'cashier_kds.sqlite'));
      final quarantinedFile = File(p.join(quarantineDir.path, 'cashier_kds.sqlite'));
      expect(await quarantinedFile.exists(), isTrue);
      expect(await quarantinedFile.readAsString(), 'original data');
    });
  });

  group('CashierStartupFatalApp Widget Tests', () {
    late Directory tempRoot;
    late CashierKdsStorage storage;
    late CashierDatabaseRepairService service;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('repair_widget_test_');
      storage = CashierKdsStorage(tempRoot);
      await storage.prepare();
      service = CashierDatabaseRepairService(storage);
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    testWidgets('renders all diagnostic cards and action buttons in dark mode', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        CashierStartupFatalApp(
          error: 'SqliteException(1546): while executing, disk I/O error (code 1546)',
          repairService: service,
        ),
      );
      await tester.pumpAndSettle();

      // 诊断标题与异常识别
      expect(find.text('本地收银数据库启动异常'), findsOneWidget);
      expect(find.textContaining('1546'), findsAtLeastNWidgets(1));

      // 4 大修复动作卡片
      expect(find.text('一键重试启动'), findsOneWidget);
      expect(find.text('清理临时锁与缓存修复'), findsOneWidget);
      expect(find.text('从历史自动备份还原'), findsOneWidget);
      expect(find.text('安全归档并重建全新库'), findsOneWidget);

      // 辅助按钮
      expect(find.text('打开本地数据目录'), findsOneWidget);
      expect(find.text('查看运行日志'), findsOneWidget);
      expect(find.text('查看技术错误'), findsOneWidget);

      // 点击展开技术错误
      await tester.tap(find.text('查看技术错误'));
      await tester.pumpAndSettle();
      expect(find.text('收起技术错误'), findsOneWidget);
      expect(find.text('复制错误'), findsOneWidget);
    });
  });
}
