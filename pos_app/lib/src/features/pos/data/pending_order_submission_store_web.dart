// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;

import 'pending_order_submission_store.dart';

PendingOrderSubmissionStore createPlatformPendingOrderSubmissionStore() =>
    _WebPendingOrderSubmissionStore();

class _WebPendingOrderSubmissionStore implements PendingOrderSubmissionStore {
  String _key(String scope) => 'laofei.pending_order.v1.$scope';

  @override
  Future<String> resolve({
    required String scope,
    required String fingerprint,
    required String Function() generate,
  }) async {
    final raw = html.window.localStorage[_key(scope)];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
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
    html.window.localStorage[_key(scope)] = jsonEncode(value.toJson());
    return value.requestId;
  }

  @override
  Future<void> clear(String scope) async =>
      html.window.localStorage.remove(_key(scope));
}
