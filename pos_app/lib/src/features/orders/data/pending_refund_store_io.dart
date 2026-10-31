import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'pending_refund_store.dart';

PendingRefundStore createPlatformPendingRefundStore() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return _MemoryPendingRefundStore();
  }
  return _FilePendingRefundStore(_storageDirectory());
}

Directory _storageDirectory() {
  Directory root;
  if (Platform.isAndroid) {
    root = Directory(p.join(Directory.systemTemp.parent.path, 'files'));
  } else {
    final appData = Platform.environment['LOCALAPPDATA']?.trim();
    final home = Platform.environment['HOME']?.trim();
    root = appData != null && appData.isNotEmpty
        ? Directory(appData)
        : home != null && home.isNotEmpty
        ? Directory(p.join(home, '.local', 'share'))
        : Directory.current;
  }
  return Directory(p.join(root.path, 'LaofeiCashier', 'pending_refunds'));
}

class _FilePendingRefundStore implements PendingRefundStore {
  _FilePendingRefundStore(this.directory);

  final Directory directory;

  File _file(String orderNo) {
    final safeName = orderNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(directory.path, '$safeName.json'));
  }

  Future<T> _withOrderLock<T>(
    String orderNo,
    Future<T> Function() action,
  ) async {
    await directory.create(recursive: true);
    final lockFile = File('${_file(orderNo).path}.lock');
    final handle = await lockFile.open(mode: FileMode.append);
    await handle.lock(FileLock.exclusive);
    try {
      return await action();
    } finally {
      await handle.unlock();
      await handle.close();
    }
  }

  Future<PendingRefund?> _readUnlocked(String orderNo) async {
    final file = _file(orderNo);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return PendingRefund.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clear(String orderNo) async {
    await _withOrderLock(orderNo, () async {
      final file = _file(orderNo);
      if (await file.exists()) await file.delete();
    });
  }

  @override
  Future<void> clearIfMatches(String orderNo, String idempotencyKey) async {
    await _withOrderLock(orderNo, () async {
      final current = await _readUnlocked(orderNo);
      if (current?.idempotencyKey != idempotencyKey) return;
      final file = _file(orderNo);
      if (await file.exists()) await file.delete();
    });
  }

  @override
  Future<PendingRefund?> read(String orderNo) async {
    return _withOrderLock(orderNo, () => _readUnlocked(orderNo));
  }

  @override
  Future<void> write(PendingRefund value) async {
    await _withOrderLock(value.orderNo, () async {
      final file = _file(value.orderNo);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
  }
}

class _MemoryPendingRefundStore implements PendingRefundStore {
  final values = <String, PendingRefund>{};

  @override
  Future<void> clear(String orderNo) async => values.remove(orderNo);

  @override
  Future<void> clearIfMatches(String orderNo, String idempotencyKey) async {
    if (values[orderNo]?.idempotencyKey == idempotencyKey) {
      values.remove(orderNo);
    }
  }

  @override
  Future<PendingRefund?> read(String orderNo) async => values[orderNo];

  @override
  Future<void> write(PendingRefund value) async {
    values[value.orderNo] = value;
  }
}
