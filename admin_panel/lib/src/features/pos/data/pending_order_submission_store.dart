import 'pending_order_submission_store_stub.dart'
    if (dart.library.io) 'pending_order_submission_store_io.dart'
    if (dart.library.html) 'pending_order_submission_store_web.dart'
    as platform;

class PendingOrderSubmission {
  const PendingOrderSubmission({
    required this.scope,
    required this.fingerprint,
    required this.requestId,
  });

  final String scope;
  final String fingerprint;
  final String requestId;

  Map<String, Object?> toJson() => {
    'scope': scope,
    'fingerprint': fingerprint,
    'request_id': requestId,
  };

  factory PendingOrderSubmission.fromJson(Map<String, Object?> json) =>
      PendingOrderSubmission(
        scope: '${json['scope'] ?? ''}',
        fingerprint: '${json['fingerprint'] ?? ''}',
        requestId: '${json['request_id'] ?? ''}',
      );
}

abstract interface class PendingOrderSubmissionStore {
  Future<String> resolve({
    required String scope,
    required String fingerprint,
    required String Function() generate,
  });

  Future<void> clear(String scope);
}

class MemoryPendingOrderSubmissionStore implements PendingOrderSubmissionStore {
  final Map<String, PendingOrderSubmission> _values = {};

  @override
  Future<String> resolve({
    required String scope,
    required String fingerprint,
    required String Function() generate,
  }) async {
    final existing = _values[scope];
    if (existing != null && existing.fingerprint == fingerprint) {
      return existing.requestId;
    }
    final requestId = generate();
    _values[scope] = PendingOrderSubmission(
      scope: scope,
      fingerprint: fingerprint,
      requestId: requestId,
    );
    return requestId;
  }

  @override
  Future<void> clear(String scope) async => _values.remove(scope);
}

PendingOrderSubmissionStore createPendingOrderSubmissionStore() =>
    platform.createPlatformPendingOrderSubmissionStore();
