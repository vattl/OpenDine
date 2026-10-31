import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'pending_external_checkout_store.dart';

PendingExternalCheckoutStore createPlatformPendingExternalCheckoutStore() {
  if (Platform.environment.containsKey('FLUTTER_TEST')) {
    return _MemoryPendingExternalCheckoutStore();
  }
  return _FilePendingExternalCheckoutStore(_storageDirectory());
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
  return Directory(p.join(root.path, 'LaofeiCashier', 'pending_payments'));
}

class _FilePendingExternalCheckoutStore
    implements PendingExternalCheckoutStore {
  _FilePendingExternalCheckoutStore(this.directory);

  final Directory directory;

  File _file(String orderNo) {
    final safeName = orderNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return File(p.join(directory.path, '$safeName.json'));
  }

  @override
  Future<void> clear(String orderNo) async {
    final file = _file(orderNo);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<PendingExternalCheckout?> read(String orderNo) async {
    final file = _file(orderNo);
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return PendingExternalCheckout.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(PendingExternalCheckout value) async {
    final file = _file(value.orderNo);
    await directory.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}

class _MemoryPendingExternalCheckoutStore
    implements PendingExternalCheckoutStore {
  final _values = <String, PendingExternalCheckout>{};

  @override
  Future<void> clear(String orderNo) async => _values.remove(orderNo);

  @override
  Future<PendingExternalCheckout?> read(String orderNo) async =>
      _values[orderNo];

  @override
  Future<void> write(PendingExternalCheckout value) async =>
      _values[value.orderNo] = value;
}
