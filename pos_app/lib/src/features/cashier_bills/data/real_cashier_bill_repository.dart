import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../cashier_settings/domain/receipt_preview_models.dart';
import '../domain/cashier_bill.dart';
import 'cashier_bill_repository.dart';

class RealCashierBillRepository implements CashierBillRepository {
  const RealCashierBillRepository(this.client);

  final AdminApiClient client;

  @override
  Future<CashierBillSummary> loadSummary() async {
    try {
      final response = await client.get(reportDashboardEndpoint);
      if (response is Map) {
        final map = _asMap(response);
        final businessDay =
            _namedMap(map, 'businessDay') ??
            _namedMap(map, 'business_day') ??
            map;
        final rev = _money(
          businessDay['todayRevenue'] ??
              businessDay['businessRevenueNet'] ??
              businessDay['sett_amount'],
        );
        final cnt = _int(
          businessDay['todayPaidOrderCount'] ??
              businessDay['todayOrderCount'] ??
              businessDay['orderCount'],
        );
        final disc = _money(
          businessDay['totalDiscountAmount'] ?? businessDay['discount_amount'],
        );
        final avg = cnt > 0 ? rev / cnt : 0.0;
        if (rev > 0 || cnt > 0 || disc > 0) {
          return CashierBillSummary(
            todayRevenue: rev,
            orderCount: cnt,
            avgOrderPrice: avg,
            totalDiscount: disc,
          );
        }
      }
    } catch (_) {}

    final todayData = await client.get(
      cashierOrderTodayEndpoint,
      query: {if (client.shopId != null) 'shopId': client.shopId},
    );
    final all = _rows(
      todayData,
    ).map(CashierBill.fromJson).toList(growable: false);
    return _calculateSummary(all);
  }

  @override
  Future<CashierBillResult> loadBills(CashierBillQuery query) async {
    final hasSearchTerms = query.tableNumber.trim().isNotEmpty ||
        query.keyword.trim().isNotEmpty ||
        query.cashierId != null;
    if (hasSearchTerms) return _search(query);

    final queryParams = <String, Object?>{
      if (client.shopId != null) 'shopId': client.shopId,
      if (query.status.apiValue != null)
        'transac_status': query.status.apiValue,
      if (query.hasCustomTimeRange) ...{
        'startTime': _formatDateOnly(query.startTime!),
        'endTime': _formatDateOnly(query.endTime!),
      },
    };

    final Object? data;
    try {
      data = await client.get(
        cashierOrderTodayEndpoint,
        query: queryParams,
      );
    } on ApiException catch (e) {
      if (e.message.contains('admin:super') || e.message.contains('无权限')) {
        throw const ApiException('查询该时间段账单需要超级管理员权限(admin:super)');
      }
      rethrow;
    }
    final all = _rows(data).map(CashierBill.fromJson).toList(growable: false);
    final filtered = all
        .where((b) => _matchesQuery(b, query))
        .toList(growable: false);
    final summary = _calculateSummary(filtered.isNotEmpty ? filtered : all);
    final start = (query.pageNum - 1) * query.pageSize;
    final visible = start >= filtered.length
        ? const <CashierBill>[]
        : filtered.sublist(
            start,
            (start + query.pageSize).clamp(0, filtered.length).toInt(),
          );
    return CashierBillResult(
      bills: visible,
      total: filtered.length,
      summary: summary,
    );
  }

  bool _matchesQuery(CashierBill bill, CashierBillQuery query) {
    if (query.status != CashierBillStatus.all && bill.status != query.status) {
      return false;
    }
    if (query.orderType != CashierOrderType.all &&
        !query.orderType.matches(bill.orderType)) {
      return false;
    }
    if (query.tableNumber.trim().isNotEmpty &&
        !bill.tableNumber.toLowerCase().contains(
          query.tableNumber.trim().toLowerCase(),
        )) {
      return false;
    }
    if (query.keyword.trim().isNotEmpty) {
      final kw = query.keyword.trim().toLowerCase();
      final matchOrderNo = bill.orderNo.toLowerCase().contains(kw);
      final matchTable = bill.tableNumber.toLowerCase().contains(kw);
      final matchMember =
          bill.memberName.toLowerCase().contains(kw) ||
          bill.memberPhone.contains(kw);
      if (!matchOrderNo && !matchTable && !matchMember) return false;
    }
    return true;
  }

  Future<CashierBillResult> _search(CashierBillQuery query) async {
    if (query.status == CashierBillStatus.all &&
        query.orderType == CashierOrderType.all &&
        query.keyword.trim().isEmpty) {
      final data = await _searchPage(query, query.pageNum, query.pageSize);
      final bills = _rows(
        data,
      ).map(CashierBill.fromJson).toList(growable: false);
      return CashierBillResult(
        bills: bills,
        total: _total(data, bills.length),
        summary: _calculateSummary(bills),
      );
    }

    const remotePageSize = 100;
    final all = <CashierBill>[];
    var remotePage = 1;
    var remoteTotal = 0;
    while (remotePage <= 100) {
      final data = await _searchPage(query, remotePage, remotePageSize);
      final page = _rows(
        data,
      ).map(CashierBill.fromJson).toList(growable: false);
      remoteTotal = _total(data, all.length + page.length);
      all.addAll(page);
      if (page.isEmpty ||
          all.length >= remoteTotal ||
          page.length < remotePageSize) {
        break;
      }
      remotePage++;
    }
    final filtered = all
        .where((bill) => _matchesQuery(bill, query))
        .toList(growable: false);
    final start = (query.pageNum - 1) * query.pageSize;
    final visible = start >= filtered.length
        ? const <CashierBill>[]
        : filtered.sublist(
            start,
            (start + query.pageSize).clamp(0, filtered.length).toInt(),
          );
    return CashierBillResult(
      bills: visible,
      total: filtered.length,
      summary: _calculateSummary(filtered),
    );
  }

  Future<Object?> _searchPage(
    CashierBillQuery query,
    int pageNum,
    int pageSize,
  ) {
    DateTime? resolvedStart = query.startTime;
    DateTime? resolvedEnd = query.endTime;
    if (resolvedStart == null && resolvedEnd == null) {
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      switch (query.datePreset) {
        case CashierDatePreset.today:
          resolvedStart = todayStart;
          resolvedEnd = todayEnd;
          break;
        case CashierDatePreset.yesterday:
          resolvedStart = todayStart.subtract(const Duration(days: 1));
          resolvedEnd = DateTime(now.year, now.month, now.day - 1, 23, 59, 59);
          break;
        case CashierDatePreset.last7Days:
          resolvedStart = todayStart.subtract(const Duration(days: 6));
          resolvedEnd = todayEnd;
          break;
        case CashierDatePreset.custom:
          break;
      }
    }

    return client.get(
      cashierOrderSearchEndpoint,
      query: {
        if (client.shopId != null) 'shopId': client.shopId,
        if (query.tableNumber.trim().isNotEmpty)
          'tableNumber': query.tableNumber.trim(),
        if (query.keyword.trim().isNotEmpty) 'keyword': query.keyword.trim(),
        if (query.orderType.apiValue != null) ...{
          'dineInOrTakeOut': query.orderType.apiValue,
          'orderType': query.orderType.apiValue,
        },
        if (query.status.apiValue != null)
          'transac_status': query.status.apiValue,
        if (resolvedStart != null) 'startTime': _formatDateOnly(resolvedStart),
        if (resolvedEnd != null) 'endTime': _formatDateOnly(resolvedEnd),
        if (query.cashierId != null) 'cashierId': query.cashierId,
        'pageNum': pageNum,
        'pageSize': pageSize,
      },
    );
  }

  @override
  Future<CashierBill> loadBillDetail(CashierBill bill) async {
    if (bill.id <= 0) return bill;
    final data = await client.get(orderDetailEndpoint, query: {'id': bill.id});
    final order = _namedMap(data, 'order');
    final lines = _rows(
      data,
    ).map(CashierBillLine.fromJson).toList(growable: false);
    if (order == null) {
      return CashierBill.fromJson(_billFallback(bill), lines: lines);
    }
    var parsedBill = CashierBill.fromJson(order, lines: lines);

    // 若订单未返回手机号但有 openid，通过用户接口反查补齐手机号与基础资料
    final openid = parsedBill.openid.isNotEmpty
        ? parsedBill.openid
        : parsedBill.payOpenid;
    if (parsedBill.memberPhone.isEmpty && openid.isNotEmpty) {
      try {
        final userData = await client.post(
          getUserInfoEndpoint,
          body: {'query': openid, 'pageNum': 1, 'pageSize': 1},
        );
        final userList = _rows(userData);
        if (userList.isNotEmpty) {
          final userMap = userList.first;
          final userName = _text(userMap['name'] ?? userMap['nickname']);
          final userPhone = _text(userMap['phone']);
          final userBalance = _money(userMap['balance']);
          final userId = _int(userMap['id']);
          parsedBill = parsedBill.copyWith(
            memberName: parsedBill.memberName.isNotEmpty
                ? parsedBill.memberName
                : userName,
            memberPhone: userPhone,
            memberBalance: userBalance,
            memberId: userId > 0 ? userId : null,
          );
        }
      } catch (_) {
        // 静默容错，不阻断详情加载
      }
    }
    return parsedBill;
  }

  @override
  Future<void> refundOrder({
    required String orderNo,
    String? transactionId,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    if (orderNo.trim().isEmpty &&
        (transactionId == null || transactionId.trim().isEmpty)) {
      throw ArgumentError('退款需要有效订单号或微信支付交易单号');
    }
    await client.post(
      orderRefundEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('refund')},
      body: {
        if (orderNo.trim().isNotEmpty) 'orderNo': orderNo.trim(),
        if (transactionId != null && transactionId.trim().isNotEmpty)
          'transaction_id': transactionId.trim(),
        if (refundAmount != null && refundAmount > 0)
          'refundAmount': refundAmount.toStringAsFixed(2),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        ..._sensitiveField(approvalToken, account, password),
      },
    );
  }

  @override
  Future<void> manualRefund({
    required String orderNo,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      throw ArgumentError('人工退款需要有效订单号');
    }
    await client.post(
      cashierManualRefundEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('manual-refund')},
      body: {
        'order_no': normalizedOrderNo,
        if (refundAmount != null && refundAmount > 0)
          'refund_amount': refundAmount.toStringAsFixed(2),
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        ..._sensitiveField(approvalToken, account, password),
      },
    );
  }

  String _clientRequestId(String action) {
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    return 'cashier-$action-$timestamp';
  }

  @override
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
    String? approvalToken,
  }) async {
    final normalizedReason = reason.trim();
    if (orderNo.trim().isEmpty) {
      throw ArgumentError('撤销结账需要有效订单号');
    }
    if (normalizedReason.isEmpty) {
      throw ArgumentError('请填写撤销结账原因');
    }
    await client.post(
      cashierOrderUnCheckoutEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('uncheckout')},
      body: {
        'order_no': orderNo.trim(),
        'reason': normalizedReason,
        if (approvalToken != null && approvalToken.isNotEmpty)
          'approvalToken': approvalToken,
      },
    );
  }

  @override
  Future<void> printKitchen({
    required String orderNo,
    List<String> categoryIds = const [],
  }) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      throw ArgumentError('后厨补打需要有效订单号');
    }
    final cidList = categoryIds.map((e) => int.tryParse(e) ?? e).toList();
    await client.post(
      cashierPrintDispatchEndpoint,
      body: {
        'order_no': normalizedOrderNo,
        'scenario': 'kitchen',
        'is_reprint': true,
        if (cidList.isNotEmpty) 'cid_list': cidList,
      },
    );
  }

  @override
  Future<void> printReceipt({
    required String orderNo,
    int? orderId,
    String scenario = 'checkout',
  }) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty && (orderId == null || orderId <= 0)) {
      throw ArgumentError('打印小票需要有效订单号或订单ID');
    }
    final normalizedScenario = scenario.trim().toLowerCase();
    if (normalizedScenario.isEmpty) {
      throw ArgumentError('打印小票需要有效的出票场景');
    }
    await client.post(
      cashierPrintDispatchEndpoint,
      body: {
        if (normalizedOrderNo.isNotEmpty) 'order_no': normalizedOrderNo,
        if (orderId != null && orderId > 0) 'order_id': orderId,
        'scenario': normalizedScenario,
        'is_reprint': true,
      },
    );
  }

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'CHECKOUT',
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
  Future<void> deleteBill(
    CashierBill bill, {
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    if (bill.id <= 0) {
      throw ArgumentError('删除账单需要有效的订单 ID');
    }
    await client.request(
      AdminEndpoint(
        method: 'DELETE',
        path: '/order/delete/${bill.id}',
        permissionCode: 'order:delete',
      ),
      body: _sensitiveField(approvalToken, account, password),
    );
  }

  @override
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {
    final account = username.trim();
    await client.post(
      adminLoginEndpoint,
      body: {'workNo': account, 'userName': account, 'password': password},
    );
  }

  @override
  Future<CashierInvoiceResult> createInvoiceQrcode({
    required String orderNo,
    String? tableNumber,
    double? invoiceAmount,
    double? taxRate,
  }) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      throw ArgumentError('生成发票二维码需要有效订单号');
    }
    final body = <String, Object?>{
      'orderNo': normalizedOrderNo,
      if (tableNumber != null && tableNumber.isNotEmpty)
        'tableNumber': tableNumber.trim(),
      if (invoiceAmount != null && invoiceAmount > 0)
        'invoiceAmount': invoiceAmount,
      if (taxRate != null) 'taxRate': taxRate,
    };
    final response = await client.post(orderInvoiceQrcodeEndpoint, body: body);
    if (response is Map) {
      final data = response['data'] is Map ? response['data'] as Map : response;
      return CashierInvoiceResult.fromJson(data.cast<String, Object?>());
    }
    throw const ApiException('生成电子发票失败：响应数据格式错误');
  }

  @override
  Future<CashierInvoiceDetails> loadInvoiceStatus(String orderNo) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      return const CashierInvoiceDetails(
        orderNo: '',
        hasInvoice: false,
        invoiceStatus: 'NONE',
        invoiceAmount: 0.0,
      );
    }
    final endpoint = orderInvoiceStatusEndpoint.withPathParams(
      {'orderNo': normalizedOrderNo},
    );
    try {
      final response = await client.get(endpoint);
      if (response is Map) {
        final data = response['data'] is Map ? response['data'] as Map : response;
        return CashierInvoiceDetails.fromJson(data.cast<String, Object?>());
      }
    } catch (_) {}
    return CashierInvoiceDetails(
      orderNo: normalizedOrderNo,
      hasInvoice: false,
      invoiceStatus: 'NONE',
      invoiceAmount: 0.0,
    );
  }

  @override
  Future<CashierAuditTimeline> loadAuditTimeline(String orderNo) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      return CashierAuditTimeline(orderNo: orderNo, events: const []);
    }
    final endpoint = orderAuditTimelineEndpoint.withPathParams(
      {'orderNo': normalizedOrderNo},
    );
    try {
      final response = await client.get(endpoint);
      if (response is Map) {
        final data = response['data'] is Map ? response['data'] as Map : response;
        return CashierAuditTimeline.fromJson(data.cast<String, Object?>());
      }
    } catch (_) {}
    return CashierAuditTimeline(orderNo: normalizedOrderNo, events: const []);
  }
}

CashierBillSummary _calculateSummary(List<CashierBill> bills) {
  if (bills.isEmpty) return const CashierBillSummary();
  double revenue = 0.0;
  double discount = 0.0;
  int paidCount = 0;
  for (final bill in bills) {
    if (bill.status == CashierBillStatus.success) {
      revenue += bill.paidAmount > 0 ? bill.paidAmount : bill.payableAmount;
      paidCount++;
    }
    discount += bill.discountAmount;
  }
  final count = bills.length;
  final avgPrice = paidCount > 0
      ? revenue / paidCount
      : (count > 0 ? revenue / count : 0.0);
  return CashierBillSummary(
    todayRevenue: revenue,
    orderCount: count,
    avgOrderPrice: avgPrice,
    totalDiscount: discount,
  );
}

Map<String, Object?> _billFallback(CashierBill bill) => {
  'id': bill.id,
  'order_no': bill.orderNo,
  'table_number': bill.tableNumber,
  'transac_status': bill.status.apiValue,
  'sett_amount': bill.goodsAmount,
  'discount_amount': bill.discountAmount,
  'service_fee': bill.serviceFee,
  'refund_amount': bill.refundAmount,
  'pay_amount_gift': bill.giftAmount,
};

List<Map<String, Object?>> _rows(Object? value) {
  final direct = objectList(value);
  if (direct.isNotEmpty) return direct;
  if (value is Map) {
    for (final key in const ['data', 'result', 'page', 'payload']) {
      final nested = _rows(value[key]);
      if (nested.isNotEmpty) return nested;
    }
  }
  return const [];
}

Map<String, Object?>? _namedMap(Object? value, String name) {
  if (value is! Map) return null;
  final direct = value[name];
  if (direct is Map) return direct.cast<String, Object?>();
  for (final key in const ['data', 'result', 'payload']) {
    final nested = _namedMap(value[key], name);
    if (nested != null) return nested;
  }
  return null;
}

int _total(Object? value, int fallback) {
  final direct = totalFrom(value, -1);
  if (direct >= 0) return direct;
  if (value is Map) {
    for (final key in const ['data', 'result', 'page', 'payload']) {
      final nested = _total(value[key], -1);
      if (nested >= 0) return nested;
    }
  }
  return fallback;
}

String _formatDateOnly(DateTime value) {
  final y = value.year.toString().padLeft(4, '0');
  final m = value.month.toString().padLeft(2, '0');
  final d = value.day.toString().padLeft(2, '0');
  return '$y/$m/$d';
}


Map<String, Object?> _asMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}

double _money(Object? value) {
  if (value is num) return value.toDouble();
  if (value == null) return 0.0;
  return double.tryParse('$value'.replaceAll(',', '')) ?? 0.0;
}

int _int(Object? value) {
  if (value is num) return value.toInt();
  if (value == null) return 0;
  return int.tryParse('$value') ?? 0;
}

String _text(Object? value) => value == null ? '' : '$value'.trim();

Map<String, String> _sensitiveAuthorization(String? account, String? password) {
  final normalizedAccount = account?.trim() ?? '';
  if (normalizedAccount.isEmpty || password == null || password.isEmpty) {
    throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
  }
  return {'account': normalizedAccount, 'password': password};
}

/// 敏感操作凭据：优先携带一次性审批令牌，未提供时回退账号 + 密码现场授权。
Map<String, Object?> _sensitiveField(
  String? approvalToken,
  String? account,
  String? password,
) {
  if (approvalToken != null && approvalToken.isNotEmpty) {
    return {'approvalToken': approvalToken};
  }
  return {'authorization': _sensitiveAuthorization(account, password)};
}
