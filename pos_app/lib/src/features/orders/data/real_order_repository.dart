import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../cashier_settings/domain/receipt_preview_models.dart';
import '../domain/admin_order.dart';
import '../domain/order_query.dart';
import 'order_repository.dart';
import 'pending_refund_store.dart';
import '../../../core/cashier_operation_audit.dart';

class RealOrderRepository implements OrderRepository {
  RealOrderRepository(this.client, {PendingRefundStore? refundStore})
    : refundStore = refundStore ?? createPendingRefundStore();

  final AdminApiClient client;
  final PendingRefundStore refundStore;

  @override
  Future<PagedOrders> listOrders(
    OrderQuery query, {
    required int shopId,
  }) async {
    final scoped = client.copyWith(shopId: shopId);
    final data = await scoped.post(
      orderListEndpoint,
      body: query.toRequestBody(),
    );
    var todayCount = totalFrom(data, 0);
    try {
      final today = await scoped.get(orderTodayCountEndpoint);
      todayCount = _int(today);
    } catch (_) {
      todayCount = todayCount == 0 ? objectList(data).length : todayCount;
    }
    final rows = objectList(
      data,
    ).map(AdminOrder.fromJson).toList(growable: false);
    return PagedOrders(
      orders: rows,
      total: totalFrom(data, rows.length),
      todayCount: todayCount,
    );
  }

  @override
  Future<AdminOrder> loadOrderDetails(AdminOrder order) async {
    if (order.id <= 0) return order;
    final data = await client.get(orderDetailEndpoint, query: {'id': order.id});
    final map = data is Map
        ? data.cast<String, Object?>()
        : <String, Object?>{};
    final detailOrder = map['order'] is Map
        ? AdminOrder.fromJson((map['order'] as Map).cast<String, Object?>())
        : order;
    final lines = objectList(
      data,
    ).map(OrderLine.fromJson).toList(growable: false);
    final withLines = lines.isEmpty
        ? detailOrder
        : detailOrder.copyWith(lines: lines);
    return withLines.copyWith(user: await _loadUserBrief(withLines));
  }

  Future<OrderUserBrief?> _loadUserBrief(AdminOrder order) async {
    final key = order.openid.isNotEmpty ? order.openid : order.payOpenid;
    if (key.isEmpty) return order.user;
    try {
      final data = await client.post(
        getUserInfoEndpoint,
        body: {'pageNum': 1, 'pageSize': 1, 'query': key},
      );
      final rows = objectList(data);
      if (rows.isEmpty) return order.user;
      return OrderUserBrief.fromJson(rows.first);
    } catch (_) {
      return order.user;
    }
  }

  @override
  Future<PagedOrders> loadPhoneHistory(String phone, {required int shopId}) {
    return listOrders(
      OrderQuery(pageNum: 1, pageSize: 20, keyword: phone),
      shopId: shopId,
    );
  }

  @override
  Future<Object?> printReceipt(AdminOrder order) {
    return client.post(
      cashierPrintDispatchEndpoint,
      body: {
        if (order.id > 0) 'order_id': order.id,
        if (order.orderNo.isNotEmpty) 'order_no': order.orderNo,
        'scenario': 'checkout',
        'is_reprint': true,
      },
    );
  }

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'ORDER',
    int? orderId,
    String? orderNo,
    String paperSize = '58mm',
  }) async {
    final response = await client.request(
      settingsPrintingPreviewPostEndpoint,
      body: {
        'scenario': scenario,
        if (orderId != null && orderId > 0) 'orderId': orderId,
        if (orderNo != null && orderNo.isNotEmpty) 'orderNo': orderNo,
        'paperSize': paperSize,
      },
    );
    final map = _asMap(response);
    final dataMap = map['data'] is Map ? _asMap(map['data']) : map;
    return PrintPreviewResult.fromJson(dataMap);
  }

  @override
  Future<Object?> repushKdsTicket(AdminOrder order) {
    return client.post(kdsTicketRepushEndpoint, body: {'order_id': order.id});
  }

  @override
  Future<Object?> loadTakeoutDelivery(AdminOrder order) {
    return client.get(
      takeoutDeliveryDetailEndpoint,
      query: {'orderId': order.id},
    );
  }

  @override
  Future<void> refundLine(OrderLine line) async {
    await client.post(orderDetailDeleteMenuEndpoint, body: {'id': line.id});
  }

  @override
  Future<void> updateLineQuantity(OrderLine line, int quantity) async {
    await client.post(
      orderDetailUpdateQuantityEndpoint,
      body: {'id': line.id, 'quantity': quantity},
    );
  }

  @override
  Future<void> refundWechat(
    AdminOrder order, {
    required double amount,
    required String reason,
  }) async {
    final amountMinor = (amount * 100).round();
    final baselineMinor = (order.refundAmount * 100).round();
    final normalizedReason = reason.trim();
    var pending = await refundStore.read(order.orderNo);
    if (pending != null &&
        (pending.amountMinor != amountMinor ||
            pending.reason != normalizedReason)) {
      throw StateError('该订单已有退款请求处理中，请等待退款状态更新后再操作');
    }
    final intent =
        pending ??
        PendingRefund(
          orderNo: order.orderNo,
          amountMinor: amountMinor,
          reason: normalizedReason,
          baselineRefundMinor: baselineMinor,
          idempotencyKey: _newRefundIdempotencyKey(
            order.orderNo,
            amountMinor,
            normalizedReason,
          ),
        );
    if (pending == null) {
      await refundStore.write(intent);
    }
    try {
      await client.post(
        orderRefundEndpoint,
        body: {
          'orderNo': order.orderNo,
          'order_no': order.orderNo,
          'transaction_id': order.transactionId,
          'refundAmount': amount.toStringAsFixed(2),
          'idempotency_key': intent.idempotencyKey,
          if (normalizedReason.isNotEmpty) 'reason': normalizedReason,
        },
      );
    } on ApiException catch (error) {
      // A competing window made this key terminal. Clearing only this explicit
      // conflict lets the cashier refresh and create a new business intent;
      // ambiguous network failures must keep their original key.
      if (error.code == 40912) {
        await refundStore.clearIfMatches(order.orderNo, intent.idempotencyKey);
      }
      CashierOperationAuditStore.instance.record(CashierOperationAuditDraft(
        module: 'order',
        action: 'refund',
        result: 'failed',
        targetType: 'order',
        targetId: order.orderNo,
        amountFen: amountMinor,
        errorCode: '${error.code}',
        errorMsg: '$error',
        detail: {'reason': normalizedReason},
      ));
      rethrow;
    }
    await refundStore.clear(order.orderNo);
    CashierOperationAuditStore.instance.record(CashierOperationAuditDraft(
      module: 'order',
      action: 'refund',
      result: 'success',
      targetType: 'order',
      targetId: order.orderNo,
      amountFen: amountMinor,
      detail: {'reason': normalizedReason, 'transaction_id': order.transactionId},
    ));
  }

  String _newRefundIdempotencyKey(
    String orderNo,
    int amountMinor,
    String reason,
  ) {
    final source = [
      orderNo,
      amountMinor,
      reason,
      DateTime.now().microsecondsSinceEpoch,
    ].join('|');
    return sha256.convert(utf8.encode(source)).toString();
  }

  @override
  Future<void> deleteOrder(
    AdminOrder order, {
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    await client.request(
      AdminEndpoint(
        method: 'DELETE',
        path: '/order/delete/${order.id}',
        permissionCode: 'order:delete',
      ),
      body: _sensitiveField(approvalToken, account, password),
    );
  }

  @override
  Future<AdminOrder> refundNormalLines(AdminOrder order) async {
    final normalLineIds = order.lines
        .where((line) => line.refundable)
        .map((line) => line.id)
        .toList();
    if (normalLineIds.isEmpty) return order;
    for (final id in normalLineIds) {
      await client.post(orderDetailDeleteMenuEndpoint, body: {'id': id});
    }
    return order.copyWith(
      lines: [
        for (final line in order.lines)
          line.copyWith(lineStatus: refundLineStatus(line)),
      ],
    );
  }

  @override
  Future<AdminOrder> reprintKitchenTicket(AdminOrder order) async {
    await client.post(
      cashierPrintDispatchEndpoint,
      body: {
        if (order.id > 0) 'order_id': order.id,
        if (order.orderNo.isNotEmpty) 'order_no': order.orderNo,
        'scenario': 'kitchen',
        'is_reprint': true,
      },
    );
    return order.copyWith(receivingStatus: order.receivingStatus);
  }
}

/// 敏感操作凭据：优先携带一次性审批令牌（/cashier/access/authorize 签发），
/// 未提供令牌时回退到旧式 authorization（账号 + 密码）现场授权。
Map<String, Object?> _sensitiveField(
  String? approvalToken,
  String? account,
  String? password,
) {
  if (approvalToken != null && approvalToken.isNotEmpty) {
    return {'approvalToken': approvalToken};
  }
  final normalizedAccount = account?.trim() ?? '';
  if (normalizedAccount.isEmpty || password == null || password.isEmpty) {
    throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
  }
  return {
    'authorization': {'account': normalizedAccount, 'password': password},
  };
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is Map) {
    for (final key in const ['todayCount', 'count', 'data']) {
      final parsed = _int(value[key]);
      if (parsed != 0) return parsed;
    }
  }
  return int.tryParse('$value') ?? 0;
}

Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}
