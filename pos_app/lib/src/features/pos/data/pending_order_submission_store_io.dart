import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'pending_order_submission_store.dart';

PendingOrderSubmissionStore createPlatformPendingOrderSubmissionStore() =>
    Platform.environment.containsKey('FLUTTER_TEST')
    ? MemoryPendingOrderSubmissionStore()
    : _FilePendingOrderSubmissionStore();

class _FilePendingOrderSubmissionStore implements PendingOrderSubmissionStore {
  Directory get _directory {
    final appData = Platform.environment['LOCALAPPDATA']?.trim();
    final root = Platform.isAndroid
        ? Directory(p.join(Directory.systemTemp.parent.path, 'files'))
        : appData != null && appData.isNotEmpty
        ? Directory(appData)
        : Directory.current;
    return Directory(p.join(root.path, 'LaofeiCashier', 'pending_orders'));
  }

  File _file(String scope) => File(
    p.join(
      _directory.path,
      '${scope.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.json',
    ),
  );

  @override
  Future<String> resolve({
    required String scope,
    required String fingerprint,
    required String Function() generate,
  }) async {
    final file = _file(scope);
    if (await file.exists()) {
      try {
        final decoded = jsonDecode(await file.readAsString());
        final existing = PendingOrderSubmission.fromJson(
          (decoded as Map).map((key, value) => MapEntry('$key', value)),
        );
        if (existing.fingerprint == fingerprint &&
            existing.requestId.isNotEmpty) {
          return existing.requestId;
        }
      } catch (_) {}
    }
    final value = PendingOrderSubmission(
      scope: scope,
      fingerprint: fingerprint,
      requestId: generate(),
    );
    await _directory.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
    return value.requestId;
  }

  @override
  Future<void> clear(String scope) async {
    final file = _file(scope);
    if (await file.exists()) await file.delete();
  }
}
