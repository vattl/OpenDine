import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../pos/domain/pos_models.dart';

/// 待提交订单（弱网时本地暂存，网络恢复后重试）。
class PendingOrder {
  const PendingOrder({
    required this.clientRequestId,
    required this.tableNumber,
    required this.diners,
    required this.remark,
    required this.lines,
    required this.paymentMethod,
    required this.createdAt,
    this.retryCount = 0,
    this.nextAttemptAt,
    this.rejectionReason,
    this.rejectedAt,
  });

  factory PendingOrder.forCheckout({
    required String clientRequestId,
    required String tableNumber,
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
    required String paymentMethod,
    required DateTime createdAt,
  }) {
    return PendingOrder(
      clientRequestId: clientRequestId,
      tableNumber: tableNumber,
      diners: diners,
      remark: remark,
      lines: lines,
      paymentMethod: paymentMethod,
      createdAt: createdAt,
    );
  }

  final String clientRequestId;
  final String tableNumber;
  final int diners;
  final String remark;
  final List<PosCartLine> lines;
  final String paymentMethod;
  final DateTime createdAt;
  final int retryCount;
  final DateTime? nextAttemptAt;
  final String? rejectionReason;
  final DateTime? rejectedAt;

  bool get isRejected => rejectedAt != null;

  Map<String, Object?> toJson() => {
    'clientRequestId': clientRequestId,
    'tableNumber': tableNumber,
    'diners': diners,
    'remark': remark,
    'paymentMethod': paymentMethod,
    'createdAt': createdAt.toIso8601String(),
    'retryCount': retryCount,
    if (nextAttemptAt != null)
      'nextAttemptAt': nextAttemptAt!.toIso8601String(),
    if (rejectionReason != null) 'rejectionReason': rejectionReason,
    if (rejectedAt != null) 'rejectedAt': rejectedAt!.toIso8601String(),
    'lines': lines
        .map(
          (l) => {
            'dishId': l.dish.id,
            'dishName': l.dish.name,
            'cid': l.dish.requestCategoryCode,
            'price': l.dish.price,
            'unit': l.dish.unit,
            'quantity': l.quantity,
            'selections': l.selections,
          },
        )
        .toList(),
  };

  PendingOrder copyWithRetry({
    required DateTime now,
    required Duration delay,
  }) => PendingOrder(
    clientRequestId: clientRequestId,
    tableNumber: tableNumber,
    diners: diners,
    remark: remark,
    lines: lines,
    paymentMethod: paymentMethod,
    createdAt: createdAt,
    retryCount: retryCount + 1,
    nextAttemptAt: now.add(delay),
  );

  PendingOrder markRejected({required String reason, required DateTime now}) =>
      PendingOrder(
        clientRequestId: clientRequestId,
        tableNumber: tableNumber,
        diners: diners,
        remark: remark,
        lines: lines,
        paymentMethod: paymentMethod,
        createdAt: createdAt,
        retryCount: retryCount,
        rejectionReason: reason,
        rejectedAt: now,
      );
}

/// 购物车 + 待提交订单的本地持久化（secure_storage，重启恢复）。
class CartStorage {
  CartStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _cartKey = 'mobile.cart';
  static const _pendingKey = 'mobile.pending_orders';
  static const _rejectedKey = 'mobile.rejected_orders';

  Future<void> saveCart(List<Map<String, Object?>> lines) =>
      _storage.write(key: _cartKey, value: jsonEncode(lines));

  Future<List<Map<String, Object?>>> readCart() async {
    final raw = await _storage.read(key: _cartKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => m.cast<String, Object?>())
          .toList();
    } catch (error) {
      debugPrint('readCart failed: $error');
      return const [];
    }
  }

  Future<void> clearCart() => _storage.delete(key: _cartKey);

  Future<List<PendingOrder>> readPending() async {
    final raw = await _storage.read(key: _pendingKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = (jsonDecode(raw) as List).whereType<Map>();
      return list
          .map((m) => _pendingFromJson(m.cast<String, Object?>()))
          .toList();
    } catch (error) {
      debugPrint('readPending failed: $error');
      return const [];
    }
  }

  Future<void> savePending(List<PendingOrder> orders) => _storage.write(
    key: _pendingKey,
    value: jsonEncode(orders.map((o) => o.toJson()).toList()),
  );

  Future<List<PendingOrder>> readRejected() => _readOrders(_rejectedKey);

  Future<void> saveRejected(List<PendingOrder> orders) => _storage.write(
    key: _rejectedKey,
    value: jsonEncode(orders.map((o) => o.toJson()).toList()),
  );

  Future<List<PendingOrder>> _readOrders(String key) async {
    final raw = await _storage.read(key: key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => _pendingFromJson(m.cast<String, Object?>()))
          .toList();
    } catch (error) {
      debugPrint('read orders failed for $key: $error');
      return const [];
    }
  }

  PendingOrder _pendingFromJson(Map<String, Object?> map) {
    final linesRaw = (map['lines'] as List?) ?? const [];
    return PendingOrder(
      clientRequestId: '${map['clientRequestId']}',
      tableNumber: '${map['tableNumber']}',
      diners: (map['diners'] as num?)?.toInt() ?? 1,
      remark: '${map['remark'] ?? ''}',
      paymentMethod: '${map['paymentMethod'] ?? '现金'}',
      createdAt: DateTime.tryParse('${map['createdAt']}') ?? DateTime.now(),
      retryCount: (map['retryCount'] as num?)?.toInt() ?? 0,
      nextAttemptAt: DateTime.tryParse('${map['nextAttemptAt'] ?? ''}'),
      rejectionReason: map['rejectionReason'] == null
          ? null
          : '${map['rejectionReason']}',
      rejectedAt: DateTime.tryParse('${map['rejectedAt'] ?? ''}'),
      lines: linesRaw.whereType<Map>().map((m) {
        final line = m.cast<String, Object?>();
        final dish = PosDish(
          id: (line['dishId'] as num?)?.toInt() ?? 0,
          name: '${line['dishName']}',
          categoryId: 0,
          categoryCode: '${line['cid'] ?? ''}',
          price: (line['price'] as num?)?.toDouble() ?? 0,
          unit: '${line['unit'] ?? '份'}',
          stock: null,
          onSale: true,
          soldOut: false,
          specGroups: const [],
        );
        final selections =
            (line['selections'] as Map?)?.map((k, v) => MapEntry('$k', '$v')) ??
            const <String, String>{};
        return PosCartLine(
          dish: dish,
          selections: selections,
          quantity: (line['quantity'] as num?)?.toInt() ?? 1,
        );
      }).toList(),
    );
  }
}
