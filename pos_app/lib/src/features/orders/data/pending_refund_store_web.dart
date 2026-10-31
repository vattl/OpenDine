// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'pending_refund_store.dart';

PendingRefundStore createPlatformPendingRefundStore() =>
    _WebPendingRefundStore();

class _WebPendingRefundStore implements PendingRefundStore {
  static String _key(String orderNo) => 'laofei.pending_refund.v1.$orderNo';

  @override
  Future<void> clear(String orderNo) async =>
      html.window.sessionStorage.remove(_key(orderNo));

  @override
  Future<void> clearIfMatches(String orderNo, String idempotencyKey) async {
    final raw = html.window.sessionStorage[_key(orderNo)];
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['idempotency_key'] == idempotencyKey) {
        html.window.sessionStorage.remove(_key(orderNo));
      }
    } catch (_) {
      return;
    }
  }

  @override
  Future<PendingRefund?> read(String orderNo) async {
    final raw = html.window.sessionStorage[_key(orderNo)];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return PendingRefund.fromJson(
        decoded.map((key, value) => MapEntry('$key', value)),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(PendingRefund value) async {
    html.window.sessionStorage[_key(value.orderNo)] = jsonEncode(value.toJson());
  }
}
