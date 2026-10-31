import 'dart:io';

import 'package:path/path.dart' as p;

/// Owns the stable on-device layout and pre-migration recovery copies.
class CashierKdsStorage {
  CashierKdsStorage(Directory applicationDataRoot)
    : dataDirectory = Directory(
        p.join(applicationDataRoot.path, 'LaofeiCashier'),
      );

  final Directory dataDirectory;

  String get databasePath => p.join(dataDirectory.path, 'cashier_kds.sqlite');
  String get authorityLockPath =>
      p.join(dataDirectory.path, 'cashier_kds.lock');
  Directory get backupDirectory =>
      Directory(p.join(dataDirectory.path, 'backups'));
  Directory get configDirectory =>
      Directory(p.join(dataDirectory.path, 'config-cache'));
  Directory get certsDirectory =>
      Directory(p.join(dataDirectory.path, 'certs'));

  Future<void> prepare() async {
    await dataDirectory.create(recursive: true);
    await backupDirectory.create(recursive: true);
    await configDirectory.create(recursive: true);
    await certsDirectory.create(recursive: true);
  }

  Future<CashierKdsAuthorityLock> acquireAuthorityLock() async {
    await prepare();
    final file = File(authorityLockPath);
    RandomAccessFile? handle;
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        handle = file.openSync(mode: FileMode.append);
        handle.lockSync(FileLock.exclusive);
        return CashierKdsAuthorityLock._(handle);
      } on FileSystemException catch (error) {
        handle?.closeSync();
        handle = null;
        if (Platform.isAndroid || Platform.isIOS) {
          final fallbackHandle = file.openSync(mode: FileMode.append);
          return CashierKdsAuthorityLock._(fallbackHandle, lockFailedGracefully: true);
        }
        if (attempt < maxAttempts) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          continue;
        }
        throw CashierKdsAuthorityLockException('$error');
      } catch (error) {
        handle?.closeSync();
        throw CashierKdsAuthorityLockException('$error');
      }
    }
    throw const CashierKdsAuthorityLockException('failed to acquire authority lock');
  }

  Future<Directory?> backupBeforeOpen({
    required int nowMs,
    int retentionCount = 7,
    int maxBackupBytes = 1024 * 1024 * 1024,
  }) async {
    await prepare();
    final source = File(databasePath);
    if (!await source.exists()) return null;
    if (maxBackupBytes <= 0) {
      throw const CashierKdsBackupCapacityException('invalid backup capacity');
    }
    final retained = await _pruneBackups(retentionCount.clamp(1, 30) - 1);
    var retainedBytes = 0;
    for (final backup in retained) {
      retainedBytes += await _directorySize(backup);
    }
    var snapshotBytes = 0;
    for (final suffix in const ['', '-wal', '-shm']) {
      final part = File('$databasePath$suffix');
      if (await part.exists()) snapshotBytes += await part.length();
    }
    if (retainedBytes + snapshotBytes > maxBackupBytes) {
      throw CashierKdsBackupCapacityException(
        'backup budget exceeded: required=${retainedBytes + snapshotBytes}, '
        'limit=$maxBackupBytes',
      );
    }
    final target = Directory(p.join(backupDirectory.path, '$nowMs'));
    final staging = Directory(p.join(backupDirectory.path, '.pending-$nowMs'));
    await staging.create(recursive: true);
    try {
      for (final suffix in const ['', '-wal', '-shm']) {
        final part = File('$databasePath$suffix');
        if (await part.exists()) {
          await part.copy(p.join(staging.path, 'cashier_kds.sqlite$suffix'));
        }
      }
      await staging.rename(target.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
    return target;
  }

  Future<List<Directory>> _pruneBackups(int retentionCount) async {
    final backups = await backupDirectory
        .list()
        .where(
          (entity) =>
              entity is Directory &&
              !p.basename(entity.path).startsWith('.pending-'),
        )
        .cast<Directory>()
        .toList();
    backups.sort((left, right) => right.path.compareTo(left.path));
    final boundedRetention = retentionCount.clamp(0, 30);
    for (final expired in backups.skip(boundedRetention)) {
      await expired.delete(recursive: true);
    }
    return backups.take(boundedRetention).toList();
  }

  Future<int> _directorySize(Directory directory) async {
    var bytes = 0;
    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is File) bytes += await entity.length();
    }
    return bytes;
  }
}

class CashierKdsAuthorityLock {
  CashierKdsAuthorityLock._(this._handle, {this.lockFailedGracefully = false});

  RandomAccessFile? _handle;
  final bool lockFailedGracefully;

  void release() {
    final handle = _handle;
    if (handle == null) return;
    _handle = null;
    try {
      if (!lockFailedGracefully) {
        handle.unlockSync();
      }
    } catch (_) {
      // Ignore unlock failure during cleanup
    } finally {
      handle.closeSync();
    }
  }
}

class CashierKdsAuthorityLockException implements Exception {
  const CashierKdsAuthorityLockException(this.message);
  final String message;

  @override
  String toString() => 'CashierKdsAuthorityLockException: $message';
}

class CashierKdsBackupCapacityException implements Exception {
  const CashierKdsBackupCapacityException(this.message);
  final String message;

  @override
  String toString() => 'CashierKdsBackupCapacityException: $message';
}
