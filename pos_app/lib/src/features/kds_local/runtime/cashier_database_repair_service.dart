import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/cashier_operation_audit.dart';
import '../../../core/crash_log.dart';
import 'cashier_kds_runtime.dart';
import 'cashier_kds_storage.dart';

class DatabaseBackupInfo {
  const DatabaseBackupInfo({
    required this.directory,
    required this.timestamp,
    required this.sizeBytes,
  });

  final Directory directory;
  final DateTime timestamp;
  final int sizeBytes;

  String get formattedTime {
    final y = timestamp.year.toString().padLeft(4, '0');
    final m = timestamp.month.toString().padLeft(2, '0');
    final d = timestamp.day.toString().padLeft(2, '0');
    final hh = timestamp.hour.toString().padLeft(2, '0');
    final mm = timestamp.minute.toString().padLeft(2, '0');
    final ss = timestamp.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

enum DatabaseDiagnosticType {
  lockConflict,
  corrupted,
  backupCapacityExceeded,
  authorityAlreadyHeld,
  unknown,
}

class DatabaseDiagnosticResult {
  const DatabaseDiagnosticResult({
    required this.type,
    required this.title,
    required this.description,
    required this.recommendedAction,
  });

  final DatabaseDiagnosticType type;
  final String title;
  final String description;
  final String recommendedAction;
}

/// 数据库启动故障诊断与多级修复服务。
class CashierDatabaseRepairService {
  CashierDatabaseRepairService(this.storage);

  final CashierKdsStorage storage;

  static Future<Directory> resolveApplicationDataRoot() async {
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      try {
        final supportDir = await getApplicationSupportDirectory();
        return supportDir;
      } catch (_) {
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

  static Future<CashierDatabaseRepairService> createDefault() async {
    final root = await resolveApplicationDataRoot();
    return CashierDatabaseRepairService(CashierKdsStorage(root));
  }

  /// 智能诊断异常原因。
  DatabaseDiagnosticResult diagnose(Object error) {
    final str = error.toString().toLowerCase();
    if (error is CashierKdsAuthorityLockException || str.contains('authoritylockexception')) {
      return const DatabaseDiagnosticResult(
        type: DatabaseDiagnosticType.authorityAlreadyHeld,
        title: '收银端独占锁冲突',
        description: '检测到另一个收银端实例可能正在运行并持有了独占锁，或上次异常退出导致锁未释放。',
        recommendedAction: '若有其他收银端窗口请先关闭；或点击【清理临时锁并重试】强制重置。',
      );
    }
    if (error is CashierKdsBackupCapacityException || str.contains('backup budget exceeded')) {
      return const DatabaseDiagnosticResult(
        type: DatabaseDiagnosticType.backupCapacityExceeded,
        title: '备份空间配额超标',
        description: '自动备份目录积累的快照大小超出了安全预算上限。',
        recommendedAction: '建议点击【打开数据目录】清理历史备份，或点击【清理临时锁并重试】。',
      );
    }
    if (str.contains('1546') || str.contains('disk i/o error')) {
      return const DatabaseDiagnosticResult(
        type: DatabaseDiagnosticType.lockConflict,
        title: 'SQLite 文件 I/O 或访问异常 (Code 1546)',
        description:
            'SQLite 无法读取或修改数据库辅助文件。可能是其他收银进程、杀毒/同步软件占用、目录权限、磁盘空间或文件系统异常；不能仅按锁冲突处理。',
        recommendedAction:
            '先关闭其他收银端和同步软件后点击【重新尝试启动】。不要删除 WAL/SHM 文件；持续失败时从备份恢复或联系运维检查磁盘和目录权限。',
      );
    }
    if (str.contains('corrupt') || str.contains('malformed') || str.contains('not a database')) {
      return const DatabaseDiagnosticResult(
        type: DatabaseDiagnosticType.corrupted,
        title: '数据库文件结构损坏',
        description: '本地 SQLite 数据库出现异常或断电截断，无法完成基础查询与迁移。',
        recommendedAction: '建议优先点击【从历史备份还原】；若无可用备份可选择【安全归档并重建】。',
      );
    }
    return DatabaseDiagnosticResult(
      type: DatabaseDiagnosticType.unknown,
      title: '收银数据库未就绪',
      description: '异常信息：$error',
      recommendedAction: '请尝试【一键重试启动】。若持续失败，可尝试【从历史备份还原】。',
    );
  }

  /// 获取所有可用的历史自动备份快照。
  Future<List<DatabaseBackupInfo>> getAvailableBackups() async {
    final backupDir = storage.backupDirectory;
    if (!await backupDir.exists()) return [];

    final list = <DatabaseBackupInfo>[];
    await for (final entity in backupDir.list(followLinks: false)) {
      if (entity is Directory && !p.basename(entity.path).startsWith('.')) {
        final dbFile = File(p.join(entity.path, 'cashier_kds.sqlite'));
        if (await dbFile.exists()) {
          final folderName = p.basename(entity.path);
          final ms = int.tryParse(folderName);
          final timestamp = ms != null
              ? DateTime.fromMillisecondsSinceEpoch(ms)
              : (await entity.stat()).modified;
          var totalBytes = 0;
          await for (final f in entity.list(recursive: true)) {
            if (f is File) totalBytes += await f.length();
          }
          list.add(DatabaseBackupInfo(
            directory: entity,
            timestamp: timestamp,
            sizeBytes: totalBytes,
          ));
        }
      }
    }
    list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return list;
  }

  /// 正常重试启动。
  Future<CashierKdsRuntime> retryStartup() async {
    return CashierKdsRuntime.start(
      applicationDataRoot: storage.dataDirectory.parent,
    );
  }

  /// 仅清理应用自己的锁文件后重试；不得删除 SQLite WAL/SHM，避免在
  /// 未确认所有进程关闭时破坏未检查点的事务状态。
  Future<CashierKdsRuntime> clearStaleLocksAndRetry() async {
    // 1. 删除临时 .lock 文件
    try {
      final lockFile = File(storage.authorityLockPath);
      if (await lockFile.exists()) {
        await lockFile.delete();
      }
    } catch (_) {}

    final runtime = await retryStartup();
    CashierOperationAuditStore.instance.record(const CashierOperationAuditDraft(
      module: 'db',
      action: 'repair',
      result: 'success',
      detail: {'action': 'clear_stale_locks'},
    ));
    return runtime;
  }

  /// 从指定备份目录还原，并在操作前安全归档当前故障文件。
  Future<CashierKdsRuntime> restoreFromBackup(Directory backupDir) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final quarantineDir = Directory(
      p.join(storage.dataDirectory.path, 'quarantine', 'before_restore_$nowMs'),
    );
    await quarantineDir.create(recursive: true);

    // 1. 安全隔离当前现有文件（绝不直接删除）
    for (final suffix in const ['', '-wal', '-shm']) {
      final file = File('${storage.databasePath}$suffix');
      if (await file.exists()) {
        await file.copy(p.join(quarantineDir.path, 'cashier_kds.sqlite$suffix'));
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    // 2. 从备份快照复制恢复
    for (final suffix in const ['', '-wal', '-shm']) {
      final srcFile = File(p.join(backupDir.path, 'cashier_kds.sqlite$suffix'));
      if (await srcFile.exists()) {
        await srcFile.copy('${storage.databasePath}$suffix');
      }
    }

    // 3. 启动新恢复的数据库
    return retryStartup();
  }

  /// 安全归档当前数据库并重建全新数据库。
  Future<CashierKdsRuntime> quarantineAndRebuild() async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final quarantineDir = Directory(
      p.join(storage.dataDirectory.path, 'quarantine', 'broken_$nowMs'),
    );
    await quarantineDir.create(recursive: true);

    // 1. 移动归档现有文件
    for (final suffix in const ['', '-wal', '-shm', '.lock']) {
      final targetPath = suffix == '.lock'
          ? storage.authorityLockPath
          : '${storage.databasePath}$suffix';
      final file = File(targetPath);
      if (await file.exists()) {
        await file.copy(p.join(quarantineDir.path, p.basename(targetPath)));
        try {
          await file.delete();
        } catch (_) {}
      }
    }

    // 2. 重新初始化全新数据库
    return retryStartup();
  }

  /// 打开数据目录（Windows 资源管理器）或复制路径。
  Future<bool> openDataFolder() async {
    final path = storage.dataDirectory.path;
    if (Platform.isWindows) {
      try {
        await Process.run('explorer.exe', [path]);
        return true;
      } catch (_) {
        await Clipboard.setData(ClipboardData(text: path));
        return false;
      }
    } else {
      await Clipboard.setData(ClipboardData(text: path));
      return false;
    }
  }

  /// 读取最近日志。
  Future<String> readRecentLogs({int maxLines = 80}) async {
    try {
      final logPath = await CrashLog.instance.logFileLocation;
      final file = File(logPath);
      if (!await file.exists()) return '(暂无日志文件)';
      final lines = await file.readAsLines();
      if (lines.length <= maxLines) return lines.join('\n');
      return lines.sublist(lines.length - maxLines).join('\n');
    } catch (e) {
      return '读取日志失败: $e';
    }
  }
}
