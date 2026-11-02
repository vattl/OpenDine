// ignore_for_file: deprecated_member_use

import 'dart:convert';
import 'dart:html' as html;

import 'pending_external_checkout_store.dart';

PendingExternalCheckoutStore createPlatformPendingExternalCheckoutStore() =>
    _WebPendingExternalCheckoutStore();

class _WebPendingExternalCheckoutStore
    implements PendingExternalCheckoutStore {
  static String _key(String orderNo) =>
      'laofei.pending_external_checkout.v2.$orderNo';

  @override
  Future<void> clear(String orderNo) async =>
      html.window.localStorage.remove(_key(orderNo));

  @override
  Future<PendingExternalCheckout?> read(String orderNo) async {
    final raw = html.window.localStorage[_key(orderNo)];
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
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
    html.window.localStorage[_key(value.orderNo)] = jsonEncode(value.toJson());
  }
}
