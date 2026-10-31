import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/admin_order.dart';
import '../domain/order_query.dart';
import 'order_repository.dart';
import 'pending_refund_store.dart';

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
  Future<AdminOrder> loadOrderDetailsByOrderNo(
    String orderNo, {
    required int shopId,
  }) async {
    final scoped = client.copyWith(shopId: shopId);
    final data = await scoped.get(tableStatusEndpoint, query: {'orderNo': orderNo});
    final row = _firstOrderRowByNo(data, orderNo);
    if (row == null) {
      throw ApiException('未找到订单 ' + orderNo);
    }
    final detailOrder = AdminOrder.fromJson(row);
    final goods = row['goods_list'] ?? row['goodsList'];
    final lines = goods is List
        ? goods
            .whereType<Map>()
            .map((item) => OrderLine.fromJson(item.cast<String, Object?>()))
            .toList(growable: false)
        : const <OrderLine>[];
    final withLines = lines.isEmpty
        ? detailOrder
        : detailOrder.copyWith(lines: lines);
    return withLines.copyWith(user: await _loadUserBrief(withLines));
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
    // 旧路由 /order/printContent 已迁移（后端返回 410），收银打印统一走
    // /cashier/order/printContent（权限 cashier:operate，X-Shop-Id 门店上下文）。
    return client.get(
      cashierPrintContentEndpoint,
      query: {'orderId': order.id, 'type': false},
    );
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
    String approvalToken = '',
    String account = '',
    String password = '',
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
          // 敏感操作授权：新契约「审批令牌优先、现场账号密码兜底」。
          if (approvalToken.isNotEmpty)
            'approvalToken': approvalToken
          else if (account.isNotEmpty && password.isNotEmpty)
            'authorization': {'account': account, 'password': password},
        },
      );
    } on ApiException catch (error) {
      // A competing window made this key terminal. Clearing only this explicit
      // conflict lets the cashier refresh and create a new business intent;
      // ambiguous network failures must keep their original key.
      if (error.code == 40912) {
        await refundStore.clearIfMatches(order.orderNo, intent.idempotencyKey);
      }
      rethrow;
    }
    await refundStore.clear(order.orderNo);
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
    String approvalToken = '',
    String? account,
    required String password,
    String terminalId = '',
  }) async {
    // openapi：仅 super_admin；不受订单/支付/配送状态限制；
    // 无需 X-Shop-Id（超管可按订单主键跨门店删除），外卖单同步删配送。
    // 敏感操作授权：新契约「审批令牌优先（approvalToken，120 秒单次强绑定）、
    // 现场账号密码兜底」。令牌由 /cashier/access/authorize 或扫码授权签发。
    await client.request(
      AdminEndpoint(
        method: 'DELETE',
        path: '/order/delete/${order.id}',
        permissionCode: 'order:operate',
        attachShopHeader: false,
      ),
      body: {
        if (approvalToken.isNotEmpty)
          'approvalToken': approvalToken
        else
          'authorization': {
            'account': account,
            'password': password,
          },
        if (terminalId.isNotEmpty) 'terminalId': terminalId,
      },
    );
  }

  @override
  Future<Map<String, Object?>> refundCash(
    AdminOrder order, {
    double? refundAmount,
    String reason = '',
    String approvalToken = '',
    String account = '',
    String password = '',
  }) async {
    // 人工现金退款（POST /cashier/order/refund）：已支付订单的线下现金/组合退款。
    // 默认退「现金列剩余 ∩ 剩余可退」；现金列清零时服务端拒绝。
    final data = await client.post(
      cashierOrderRefundEndpoint,
      headers: {
        'X-Client-Request-Id': _newRefundIdempotencyKey(
          order.orderNo,
          ((refundAmount ?? 0) * 100).round(),
          'manual-cash:$reason',
        ),
      },
      body: {
        'order_no': order.orderNo,
        if (refundAmount != null && refundAmount > 0)
          'refundAmount': refundAmount,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
        // 敏感操作授权：审批令牌优先、现场账号密码兜底。
        if (approvalToken.isNotEmpty)
          'approvalToken': approvalToken
        else if (account.isNotEmpty && password.isNotEmpty)
          'authorization': {'account': account, 'password': password},
      },
    );
    return data is Map ? data.cast<String, Object?>() : const <String, Object?>{};
  }

  @override
  Future<void> changeOrderMerchantId(int orderId) async {
    await client.post(orderChangeIdEndpoint, body: {'id': orderId});
  }

  @override
  Future<MerchantOrdersResult> fetchMerchantOrders({
    String merchantId = '1',
    String? date,
    String transacStatus = 'success',
    int page = 1,
    int pageSize = 500,
  }) async {
    final data = await client.get(
      merchantOrdersEndpoint,
      query: {
        'merchant_id': merchantId,
        if (date != null && date.trim().isNotEmpty) 'date': date.trim(),
        'transac_status': transacStatus,
        'page': '$page',
        'page_size': '$pageSize',
      },
    );
    final map = data is Map
        ? data.cast<String, Object?>()
        : <String, Object?>{};
    final echoedMerchantId = _string(map['merchant_id']).trim();
    return MerchantOrdersResult(
      merchantId: echoedMerchantId.isNotEmpty ? echoedMerchantId : merchantId,
      businessDay: _string(map['business_day']),
      windowStart: _string(map['window_start']),
      windowEnd: _string(map['window_end']),
      totalCount: _int(map['total_count']),
      totalRevenue: _double(map['total_revenue']),
      page: _int(map['page']),
      totalPages: _int(map['total_pages']),
      orders: objectList(map['orders'])
          .map(AdminOrder.fromJson)
          .toList(growable: false),
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
      orderReprintKitchenEndpoint,
      body: {
        'orderId': order.id,
        'order_id': order.id,
        'orderNo': order.orderNo,
        'order_no': order.orderNo,
      },
    );
    return order.copyWith(receivingStatus: order.receivingStatus);
  }
}

/// 从 /admin/table/status?orderNo= 响应中提取订单行：优先精确匹配 order_no，
/// 否则取 orderList 第一条。
Map<String, Object?>? _firstOrderRowByNo(Object? data, String orderNo) {
  if (data is! Map) return null;
  final orderList = data['orderList'] ?? data['order_list'];
  if (orderList is List) {
    Map<String, Object?>? fallback;
    for (final item in orderList.whereType<Map>()) {
      final row = item.cast<String, Object?>();
      fallback ??= row;
      final no = '${row['order_no'] ?? row['orderNo']}';
      if (no == orderNo) return row;
    }
    return fallback;
  }
  return null;
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

String _string(Object? value) => value == null ? '' : '$value';

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}
