import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../tables/domain/dining_table.dart';
import '../domain/pos_models.dart';
import 'pos_repository.dart';

class RealPosRepository
    implements
        PosRepository,
        PosCashCheckoutRepository,
        PosPickupOrderRepository,
        PosOrderKdsRebuildRepository,
        PosOfflineCollectionRepository,
        PosBalanceCheckoutRepository,
        PosCombinedCheckoutRepository,
        PosOrderPrintRepository {
  const RealPosRepository(this.client);

  final AdminApiClient client;

  Future<PosWorkspace> loadFulfillmentCheckoutWorkspace(
    FulfillmentOrderDetail detail,
  ) async {
    final fulfillment = detail.order;
    final paymentConfiguration = await _loadCashierPaymentMethods(
      orderNo: fulfillment.orderNo,
    );
    final label = fulfillment.type == FulfillmentType.takeout
        ? '外卖 ${fulfillment.displayCode}'
        : '自提 ${fulfillment.displayCode}';
    final table = DiningTable(
      id: fulfillment.id,
      number: label,
      status: TableStatus.pending,
      people: 1,
      amount: fulfillment.amount,
      openedAt: fulfillment.createdAt,
      receivingStatus: fulfillment.receivingStatus,
    );
    final order = PosOrder(
      id: fulfillment.id,
      orderNo: fulfillment.orderNo,
      tableNumber: fulfillment.tableNumber,
      diners: 1,
      total: fulfillment.amount.toDouble(),
      grossAmount: fulfillment.amount.toDouble(),
      createdAt: fulfillment.createdAt,
      receivingStatus: fulfillment.receivingStatus,
      lines: detail.lines
          .map(
            (line) => PosOrderLine(
              id: 0,
              name: line.name,
              quantity: line.quantity,
              total: line.totalPrice.toDouble(),
              specification: line.specification,
              refunded: false,
            ),
          )
          .toList(growable: false),
    );
    return PosWorkspace(
      table: table,
      categories: const [],
      dishes: const [],
      currentOrder: order,
      paymentMethods: paymentConfiguration.methods,
      paymentConfigurationAvailable: paymentConfiguration.available,
    );
  }

  @override
  Future<PosSubmissionResult> loadOrderForLocalKds(int orderId) async {
    if (orderId <= 0) {
      throw const ApiException('重建本地 KDS 失败：云端订单 ID 无效');
    }
    final data = await client.get(cashierOrderKdsDetailsEndpoint(orderId));
    final result = PosSubmissionResult.fromKdsRebuildJson(data);
    if (!result.isReadyForLocalKds || !result.hasFormalOrderDetails) {
      throw const ApiException('重建本地 KDS 失败：云端未返回有效订单明细');
    }
    return result;
  }

  @override
  Future<PosWorkspace> loadWorkspace(DiningTable table) async {
    final requests = <Future<Object?>>[
      _bestEffort(client.get(categoryListAllEndpoint)),
      client.post(
        dishListEndpoint,
        body: const {'pageNum': 1, 'pageSize': 100, 'query': ''},
      ),
      if (table.isOccupied)
        client.get(tableStatusEndpoint, query: {'number': table.number}),
    ];
    final responses = await Future.wait<Object?>(requests);
    final dishPayload = _map(responses[1]);
    final dishRows = objectList(dishPayload);
    final categoryRows = <Map<String, Object?>>[
      ..._namedList(_map(responses[0]), const [
        'categoryList',
        'category_list',
        'list',
      ]),
      ..._namedList(dishPayload, const [
        'categoryList',
        'category_list',
        'categories',
        'typeList',
        'type_list',
      ]),
      ..._embeddedCategoryRows(dishRows),
    ];
    final categories = _uniqueCategories(categoryRows);
    final categoryCodes = <int, String>{
      for (final category in categories)
        if (category.id > 0 && category.code.isNotEmpty)
          category.id: category.code,
    };
    final dishes = dishRows
        .map(PosDish.fromJson)
        .map((dish) {
          if (dish.categoryCode.isNotEmpty) return dish;
          final code = categoryCodes[dish.categoryId];
          return code == null ? dish : dish.withCategoryCode(code);
        })
        .toList(growable: false);
    final statusMap = table.isOccupied && responses.length > 2
        ? _map(responses[2])
        : const <String, Object?>{};
    final tableRows = _namedList(statusMap, const ['tableList', 'table_list']);
    final orderRows = _namedList(statusMap, const ['orderList', 'order_list']);
    final resolvedTable = tableRows.isEmpty
        ? table
        : DiningTable.fromJson(tableRows.first);
    PosOrder? order;
    if (orderRows.isNotEmpty) {
      final orderJson = Map<String, Object?>.from(orderRows.first);
      final memberPhone = _string(
        orderJson['member_phone'] ?? orderJson['memberPhone'],
      ).trim();
      final account = await _resolveMemberAccount(orderJson);
      if (account != null) {
        if (memberPhone.isEmpty && account.phone.isNotEmpty) {
          orderJson['member_phone'] = account.phone;
        }
        orderJson['member_openid'] = account.openid;
        if (account.balance != null) {
          orderJson['member_balance'] = account.balance;
        }
      }
      order = PosOrder.fromJson(orderJson);
    }
    if (order != null && order.lines.isEmpty && order.id > 0) {
      try {
        final detail = await client.get(
          orderDetailEndpoint,
          query: {'id': order.id},
        );
        final lines = objectList(
          detail,
        ).map(PosOrderLine.fromJson).toList(growable: false);
        if (lines.isNotEmpty) order = order.copyWith(lines: lines);
      } catch (_) {
        // The table snapshot remains usable when detail loading is unavailable.
      }
    }
    final paymentConfiguration = await _loadCashierPaymentMethods(
      orderNo: order?.orderNo ?? '',
    );
    return PosWorkspace(
      table: resolvedTable,
      categories: categories,
      dishes: dishes,
      currentOrder: order,
      paymentMethods: paymentConfiguration.methods,
      paymentConfigurationAvailable: paymentConfiguration.available,
    );
  }

  Future<({List<PosPaymentMethod> methods, bool available})>
  _loadCashierPaymentMethods({required String orderNo}) async {
    try {
      final paymentData = _map(
        await client.get(
          publicPaymentCapabilitiesEndpoint,
          query: {if (orderNo.trim().isNotEmpty) 'order_no': orderNo.trim()},
        ),
      );
      final clients = _map(paymentData['clients']);
      final cashier = _map(clients['cashier']);
      if (cashier.containsKey('effectiveChannels') ||
          cashier.containsKey('effectiveEnabled')) {
        final enabled = _enabledFlag(cashier['effectiveEnabled']);
        final channels = _map(cashier['effectiveChannels']);
        final methods = <PosPaymentMethod>[
          const PosPaymentMethod(
            id: 0,
            code: 'cash',
            name: '现金',
            sortOrder: 0,
            enabled: true,
          ),
          if (enabled && _enabledFlag(channels['wechat']))
            const PosPaymentMethod(
              id: 0,
              code: 'offline_wechat_qr',
              name: '微信支付',
              sortOrder: 10,
              enabled: true,
            ),
          if (enabled && _enabledFlag(channels['alipay']))
            const PosPaymentMethod(
              id: 0,
              code: 'offline_alipay_qr',
              name: '支付宝',
              sortOrder: 20,
              enabled: true,
            ),
          if (enabled && _enabledFlag(channels['balance']))
            const PosPaymentMethod(
              id: 0,
              code: 'online_balance',
              name: '余额支付',
              sortOrder: 30,
              enabled: true,
            ),
          if (enabled && _enabledFlag(channels['combined']))
            const PosPaymentMethod(
              id: 0,
              code: 'online_combined',
              name: '组合支付',
              sortOrder: 40,
              enabled: true,
            ),
        ];
        return (
          methods: List<PosPaymentMethod>.unmodifiable(methods),
          available: true,
        );
      }
      final methods =
          _paymentMethodRows(cashier['paymentMethods'])
              .map(PosPaymentMethod.fromJson)
              .where((method) => method.enabled && method.kind != null)
              .toList(growable: false)
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      final uniqueMethods = <PosPaymentChannelKind, PosPaymentMethod>{};
      for (final method in methods) {
        uniqueMethods.putIfAbsent(method.kind!, () => method);
      }
      return (
        methods: uniqueMethods.values.toList(growable: false),
        available: true,
      );
    } catch (_) {
      // Payment configuration is security-sensitive: never invent a channel.
      return (methods: const <PosPaymentMethod>[], available: false);
    }
  }

  Future<({String openid, String phone, double? balance})?>
  _resolveMemberAccount(Map<String, Object?> orderJson) async {
    final openid = _string(
      orderJson['openid'] ??
          orderJson['openId'] ??
          orderJson['pay_openid'] ??
          orderJson['payOpenid'],
    ).trim();
    if (openid.isEmpty) return null;
    try {
      final data = await client.post(
        getUserInfoEndpoint,
        body: {'pageNum': 1, 'pageSize': 1, 'query': openid},
      );
      for (final user in objectList(data)) {
        final userOpenid = _string(user['openid'] ?? user['openId']).trim();
        if (userOpenid != openid) continue;
        final phone = _string(
          user['phone'] ?? user['phone_number'] ?? user['phoneNumber'],
        ).trim();
        final rawBalance = user['balance'] ?? user['member_balance'];
        final balance = rawBalance is num
            ? rawBalance.toDouble()
            : double.tryParse('$rawBalance');
        return (openid: openid, phone: phone, balance: balance);
      }
    } catch (_) {
      // Older deployments may not expose member lookup to cashier accounts.
    }
    return null;
  }

  @override
  Future<PosSubmissionResult> submitOrder({
    required String tableNumber,
    required int diners,
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  }) async {
    _validateOrderLines(lines);
    final requestId = _clientRequestId(
      'quick-order',
      supplied: clientRequestId,
    );
    final data = await client.post(
      cashierQuickOrderEndpoint,
      headers: {'X-Client-Request-Id': requestId},
      body: {
        'tableNumber': tableNumber,
        'dineInOrTakeOut': '堂食',
        'number_of_diners': diners,
        'goods_list': _submissionLines(lines),
        if (remark.trim().isNotEmpty) 'remark': remark.trim(),
      },
    );
    return _submissionResult(data);
  }

  @override
  Future<PosSubmissionResult> submitPickupOrder({
    required String remark,
    required List<PosCartLine> lines,
    String? clientRequestId,
  }) async {
    _validateOrderLines(lines);
    final data = await client.post(
      cashierQuickOrderEndpoint,
      headers: {
        'X-Client-Request-Id': _clientRequestId(
          'pickup-order',
          supplied: clientRequestId,
        ),
      },
      body: {
        'tableNumber': '打包',
        'number_of_diners': 1,
        'dineInOrTakeOut': '打包',
        'goods_list': _submissionLines(lines),
        if (remark.trim().isNotEmpty) 'remark': remark.trim(),
      },
    );
    return _submissionResult(data);
  }

  @override
  Future<void> addDishes({
    required String orderNo,
    required String tableNumber,
    required List<PosCartLine> lines,
  }) async {
    _validateOrderLines(lines);
    await client.post(
      cashierAddDishesEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('add-dishes')},
      body: {
        'order_no': orderNo,
        'table_number': tableNumber,
        'goods_list': lines.map((line) => line.requestBody()).toList(),
      },
    );
  }

  @override
  Future<void> refundDish({
    required String orderNo,
    required int detailId,
    required int quantity,
    PosRefundStockAction stockAction = PosRefundStockAction.restore,
    String reason = '',
    String remark = '',
    String approvalToken = '',
    String account = '',
    String password = '',
    int expectedVersion = -1,
  }) async {
    await client.post(
      cashierRefundDishEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('refund-dish')},
      body: {
        'order_no': orderNo,
        'detail_id': detailId,
        'quantity': quantity,
        'stock_action': stockAction.wireValue,
        if (reason.isNotEmpty) 'reason': reason,
        if (remark.isNotEmpty) 'remark': remark,
        if (expectedVersion >= 0) 'expectedVersion': expectedVersion,
        // 敏感操作授权：新契约「审批令牌优先、现场账号密码兜底」。
        if (approvalToken.isNotEmpty)
          'approvalToken': approvalToken
        else if (account.isNotEmpty && password.isNotEmpty)
          'authorization': {'account': account, 'password': password},
      },
    );
  }

  @override
  Future<void> giftDish({
    required String orderNo,
    required int detailId,
  }) async {
    await client.post(
      cashierUpdatePriceEndpoint,
      body: {'order_no': orderNo, 'detail_id': detailId, 'total_price': 0},
    );
  }

  @override
  Future<void> discountOrder({
    required String orderNo,
    double? discountAmount,
    double? payRate,
    bool? wipeZero,
    required String reason,
    String approvalToken = '',
    String account = '',
    String password = '',
    int expectedVersion = -1,
  }) async {
    await client.post(
      cashierDiscountEndpoint,
      body: {
        'orderNo': orderNo,
        'reason': reason.trim(),
        // 三选一：后端按 discountAmount > payRate > wipeZero 优先级解析。
        if (discountAmount != null && discountAmount > 0) 'discountAmount': discountAmount,
        if (payRate != null && payRate > 0) 'payRate': payRate,
        if (wipeZero == true) 'wipeZero': true,
        if (expectedVersion >= 0) 'expectedVersion': expectedVersion,
        // 敏感操作授权：新契约「审批令牌优先、现场账号密码兜底」。
        if (approvalToken.isNotEmpty)
          'approvalToken': approvalToken
        else if (account.isNotEmpty && password.isNotEmpty)
          'authorization': {'account': account, 'password': password},
      },
    );
  }

  @override
  Future<void> checkout({
    required String orderNo,
    required String paymentMethod,
    double? cashAmount,
    String collectionSessionId = '',
  }) async {
    final result = await client.post(
      cashierCheckoutEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('checkout')},
      body: {
        'order_no': orderNo,
        'payment_method': paymentMethod,
        if (cashAmount != null) 'cash_amount': cashAmount,
        if (collectionSessionId.isNotEmpty)
          'collection_session_id': collectionSessionId,
      },
    );
    final paymentKind = PosPaymentChannelKind.normalize(paymentMethod);
    if (paymentKind == PosPaymentChannelKind.wechat ||
        paymentKind == PosPaymentChannelKind.alipay) {
      try {
        _ensureOfflineCheckoutCompleted(
          result,
          orderNo: orderNo,
          expectedChannelCode: paymentKind!.canonicalCode,
        );
      } on _IncompleteCheckoutProofException {
        if (!await _isOrderSettled(orderNo)) rethrow;
      }
    }
  }

  @override
  Future<void> checkoutCash({
    required String orderNo,
    required String paymentMethod,
    required PosCashSettlement settlement,
  }) async {
    await client.post(
      cashierCheckoutEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('checkout-cash')},
      body: {
        'order_no': orderNo,
        'payment_method': paymentMethod,
        'cash_amount': settlement.cashReceived,
        'checkout_cash_tender': settlement.cashTender,
        'checkout_change_amount': settlement.changeAmount,
        if (settlement.changeChannel != null)
          'checkout_change_channel': settlement.changeChannel!.apiValue,
      },
    );
  }

  @override
  Future<void> unCheckout({
    required String orderNo,
    required String reason,
  }) async {
    if (orderNo.trim().isEmpty) {
      throw const ApiException('反结账失败：缺少订单号');
    }
    await client.post(
      cashierOrderUnCheckoutEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('uncheckout')},
      body: {
        'order_no': orderNo.trim(),
        'reason': reason.trim(),
      },
    );
  }

  @override
  Future<PosOfflineCollectionQr> createOfflineCollectionQr({
    required String channel,
    required String orderNo,
    required String sessionId,
    required int amountMinor,
  }) async {
    final normalizedChannel = channel.trim().toLowerCase();
    final data = await client.post(
      offlineCollectTempQrcodeEndpoint,
      body: {
        'channel': normalizedChannel,
        'order_no': orderNo,
        'session_id': sessionId,
        'amount_fen': amountMinor,
      },
    );
    final qr = PosOfflineCollectionQr.fromJson(_map(data));
    if (qr.channel != normalizedChannel) {
      throw const FormatException('收款码渠道不匹配，请勿继续收款');
    }
    if (client.shopId == null || qr.shopId != client.shopId) {
      throw const FormatException('收款码门店不匹配，请勿继续收款');
    }
    return qr;
  }

  @override
  Future<void> confirmOfflineCollection({
    required String channel,
    required String orderNo,
    required String sessionId,
    required int amountMinor,
  }) async {
    await client.post(
      offlineCollectConfirmEndpoint,
      body: {
        'channel': channel.trim().toLowerCase(),
        'order_no': orderNo,
        'session_id': sessionId,
        'amount_fen': amountMinor,
      },
    );
  }

  @override
  Future<void> cancelOfflineCollection({
    required String channel,
    required String orderNo,
    required String sessionId,
  }) async {
    await client.post(
      offlineCollectCancelEndpoint,
      body: {
        'channel': channel.trim().toLowerCase(),
        'order_no': orderNo,
        'session_id': sessionId,
      },
    );
  }

  @override
  Future<bool> checkOrderSettled(String orderNo) => _isOrderSettled(orderNo);

  @override
  Future<void> checkoutByBalance({
    required String orderNo,
    required String openid,
    required String memberPhone,
  }) async {
    await client.post(
      cashierCheckoutEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('checkout-balance')},
      body: {
        'order_no': orderNo,
        'payment_method': PosPaymentChannelKind.balance.canonicalCode,
        'openid': openid.trim(),
        'member_phone': memberPhone.trim(),
      },
    );
  }

  @override
  Future<void> checkoutCombined({
    required String orderNo,
    required PosCheckoutSettlement settlement,
    String memberOpenid = '',
    String memberPhone = '',
    String collectionSessionId = '',
  }) async {
    if (settlement.positiveChannelCount < 2) {
      throw ArgumentError.value(
        settlement.positiveChannelCount,
        'settlement',
        'Combined checkout requires at least two positive channels',
      );
    }
    final result = await client.post(
      cashierCheckoutEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('checkout-combined')},
      body: {
        'order_no': orderNo,
        'payment_method': PosPaymentChannelKind.combined.canonicalCode,
        'pay_amount_wechat': _minorToYuan(settlement.wechatMinor),
        'pay_amount_alipay': _minorToYuan(settlement.alipayMinor),
        'pay_amount_balance': _minorToYuan(settlement.balanceMinor),
        'pay_amount_cash': _minorToYuan(settlement.cashMinor),
        'checkout_cash_tender': _minorToYuan(settlement.cashTenderMinor),
        'checkout_change_amount': _minorToYuan(settlement.changeAmountMinor),
        if (collectionSessionId.isNotEmpty)
          'collection_session_id': collectionSessionId,
        if (settlement.balanceMinor > 0) 'openid': memberOpenid.trim(),
        if (settlement.balanceMinor > 0 && memberPhone.trim().isNotEmpty)
          'member_phone': memberPhone.trim(),
        if (settlement.changeChannel != null)
          'checkout_change_channel': settlement.changeChannel!.apiValue,
      },
    );
    if (settlement.wechatMinor > 0 || settlement.alipayMinor > 0) {
      try {
        _ensureOfflineCheckoutCompleted(
          result,
          orderNo: orderNo,
          expectedChannelCode: PosPaymentChannelKind.combined.canonicalCode,
        );
      } on _IncompleteCheckoutProofException {
        if (!await _isOrderSettled(orderNo)) rethrow;
      }
    }
  }

  Future<bool> _isOrderSettled(String orderNo) async {
    try {
      final data = _map(
        await client.get(tableStatusEndpoint, query: {'orderNo': orderNo}),
      );
      for (final order in _namedList(data, const ['orderList', 'order_list'])) {
        final responseOrderNo = _string(
          order['order_no'] ?? order['orderNo'],
        ).trim();
        final status = _string(
          order['transac_status'] ?? order['transacStatus'],
        ).trim().toLowerCase();
        if (responseOrderNo == orderNo && status == 'success') return true;
      }
    } catch (_) {
      // Keep the payment pending when authoritative reconciliation is unavailable.
    }
    return false;
  }

  @override
  Future<PosPrintResult> printCheckoutReceipt({
    required int orderId,
    String? orderNo,
  }) async {
    final data = await client.get(
      cashierPrintContentEndpoint,
      query: {'orderId': orderId, 'type': false},
    );
    return PosPrintResult.fromJson(_map(data));
  }

  @override
  Future<void> printServeTicket({
    required int orderId,
    int? detailId,
    int? quantity,
    List<Map<String, Object?>>? lines,
  }) async {
    await client.post(
      kdsServeTicketPrintEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('print-serve')},
      body: {
        'order_id': orderId,
        if (detailId != null) 'detail_id': detailId,
        if (quantity != null) 'quantity': quantity,
        if (lines != null && lines.isNotEmpty) 'lines': lines,
      },
    );
  }

  @override
  Future<void> openTable(String tableNumber) async {
    final idempotencyKey = _tableIdempotencyKey('open');
    await client.post(
      cashierTableOpenEndpoint,
      headers: {'Idempotency-Key': idempotencyKey},
      body: {'tableNumber': tableNumber, 'idempotencyKey': idempotencyKey},
    );
  }

  @override
  Future<void> mergeTables({
    required String sourceTableNumber,
    required String targetTableNumber,
  }) async {
    final idempotencyKey = _tableIdempotencyKey('merge');
    await client.post(
      cashierTableMergeEndpoint,
      headers: {'Idempotency-Key': idempotencyKey},
      body: {
        'sourceTableNumber': sourceTableNumber,
        'targetTableNumber': targetTableNumber,
        'idempotencyKey': idempotencyKey,
      },
    );
  }

  @override
  Future<void> transferTable({
    required String orderNo,
    required String targetTableNumber,
  }) async {
    final idempotencyKey = _tableIdempotencyKey('transfer');
    await client.post(
      cashierTableTransferEndpoint,
      headers: {'Idempotency-Key': idempotencyKey},
      body: {
        'orderNo': orderNo,
        'targetTableNumber': targetTableNumber,
        'idempotencyKey': idempotencyKey,
      },
    );
  }

  @override
  Future<void> clearTable(String tableNumber) async {
    final idempotencyKey = _tableIdempotencyKey('clear');
    await client.post(
      cashierTableClearEndpoint,
      headers: {'Idempotency-Key': idempotencyKey},
      body: {'tableNumber': tableNumber, 'idempotencyKey': idempotencyKey},
    );
  }

  @override
  Future<void> hangOrder({
    required String orderNo,
    String reason = '',
  }) async {
    await client.post(
      cashierOrderHangEndpoint,
      body: {
        'order_no': orderNo,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
  }

  @override
  Future<void> unhangOrder({required String orderNo}) async {
    await client.post(
      cashierOrderUnhangEndpoint,
      body: {'order_no': orderNo},
    );
  }

  @override
  Future<HangListResult> loadHangList() async {
    final data = await client.get(cashierOrderHangListEndpoint);
    return HangListResult.fromJson(data);
  }

  @override
  Future<void> updateOrderDiners({
    required String orderNo,
    required int diners,
  }) async {
    await client.post(
      cashierOrderUpdateDinersEndpoint,
      body: {'orderNo': orderNo, 'number_of_diners': diners},
    );
  }

  @override
  Future<TableCheckoutResult> checkoutTable({
    required String tableNumber,
    String paymentMethod = 'cash',
    double? cashAmount,
    String? idempotencyKey,
  }) async {
    final key = (idempotencyKey == null || idempotencyKey.isEmpty)
        ? _tableIdempotencyKey('checkout')
        : idempotencyKey;
    final data = await client.post(
      cashierTableCheckoutEndpoint,
      headers: {'Idempotency-Key': key},
      body: {
        'tableNumber': tableNumber,
        'paymentMethod': paymentMethod,
        if (cashAmount != null) 'cashAmount': cashAmount,
        'idempotencyKey': key,
      },
    );
    return TableCheckoutResult.fromJson(
      data is Map ? data.cast<String, Object?>() : const <String, Object?>{},
    );
  }

  @override
  Future<TableStatusMap> loadTableStatusMap() async {
    final data = await client.get(cashierTableStatusMapEndpoint);
    return TableStatusMap.fromJson(
      data is Map ? data.cast<String, Object?>() : const <String, Object?>{},
    );
  }
}

void _validateOrderLines(List<PosCartLine> lines) {
  if (lines.isEmpty) {
    throw const ApiException('下单失败：请至少选择一道菜品');
  }
  for (final line in lines) {
    final total = line.total;
    if (line.dish.id <= 0) {
      throw ApiException('下单失败：菜品“${line.dish.name}”缺少有效菜品编号，请刷新菜单后重试');
    }
    if (line.quantity <= 0 || !total.isFinite || total <= 0) {
      throw ApiException('下单失败：菜品“${line.dish.name}”价格异常，请刷新菜单后重试');
    }
  }
}

PosSubmissionResult _submissionResult(Object? data) {
  final result = PosSubmissionResult.fromJson(data);
  if (result.isReadyForLocalKds) return result;
  final map = data is Map ? data.cast<Object?, Object?>() : const {};
  final message = '${map['msg'] ?? map['message'] ?? map['error'] ?? ''}'
      .trim();
  if (result.id > 0 && result.orderNo.trim().isNotEmpty) {
    throw const ApiException('下单失败：订单尚未完成云端事务，禁止写入本地 KDS');
  }
  throw ApiException(
    message.isEmpty ? '下单失败：接口未返回有效订单，请勿重复提交并联系管理员检查订单' : message,
  );
}

List<Map<String, Object?>> _submissionLines(List<PosCartLine> lines) => [
  for (final entry in lines.indexed)
    entry.$2.requestBody(clientLineId: 'line-${entry.$1 + 1}'),
];

int _tableOperationSequence = 0;
int _cashierRequestSequence = 0;

String _clientRequestId(String action, {String? supplied}) {
  final provided = supplied?.trim() ?? '';
  if (provided.isNotEmpty) return provided;
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return 'cashier-$action-$timestamp-${_cashierRequestSequence++}';
}

String _tableIdempotencyKey(String action) {
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  return 'cashier-table-$action-$timestamp-${_tableOperationSequence++}';
}

Map<String, Object?> _map(Object? value) {
  return value is Map
      ? value.cast<String, Object?>()
      : const <String, Object?>{};
}

void _ensureOfflineCheckoutCompleted(
  Object? value, {
  required String orderNo,
  required String expectedChannelCode,
}) {
  final result = _map(value);
  final status = _string(
    result['transac_status'] ??
        result['transacStatus'] ??
        result['payment_status'] ??
        result['paymentStatus'] ??
        result['status'],
  ).toLowerCase();
  final responseOrderNo = _string(result['order_no'] ?? result['orderNo']);
  if (responseOrderNo.isNotEmpty && responseOrderNo != orderNo) {
    throw ApiException('结账接口返回了其他订单（$responseOrderNo），当前扫码款未确认结账');
  }

  final channelCode = _string(
    result['payment_channel_code'] ?? result['paymentChannelCode'],
  ).toLowerCase();
  if (channelCode.isNotEmpty && channelCode != expectedChannelCode) {
    throw const ApiException('结账接口未确认本次收款码渠道，扫码款继续保留为待入账，请勿重复收款');
  }
  if (channelCode.isEmpty) {
    final paymentMethod = result['payment_method'] ?? result['paymentMethod'];
    final responseKind = PosPaymentChannelKind.normalize(paymentMethod);
    final expectedKind = PosPaymentChannelKind.normalize(expectedChannelCode);
    if (responseKind != null && responseKind != expectedKind) {
      throw const ApiException('结账接口未确认本次收款码渠道，扫码款继续保留为待入账，请勿重复收款');
    }
  }

  const completedStatuses = {'success', 'settled', 'paid', 'completed'};
  if (status.isNotEmpty && !completedStatuses.contains(status)) {
    throw const _IncompleteCheckoutProofException(
      '收款码到账已确认，但订单尚未完成结账，请直接重试入账，切勿重复收款',
    );
  }
  if (responseOrderNo.isEmpty) {
    throw const _IncompleteCheckoutProofException(
      '结账接口未返回已结订单号，扫码款继续保留为待入账，请勿重复收款',
    );
  }
  if (channelCode.isEmpty &&
      PosPaymentChannelKind.normalize(
            result['payment_method'] ?? result['paymentMethod'],
          ) ==
          null) {
    throw const _IncompleteCheckoutProofException(
      '结账接口未确认本次收款码渠道，扫码款继续保留为待入账，请勿重复收款',
    );
  }
}

class _IncompleteCheckoutProofException extends ApiException {
  const _IncompleteCheckoutProofException(super.message);
}

String _string(Object? value) => value == null ? '' : '$value';

List<Map<String, Object?>> _namedList(
  Map<String, Object?> map,
  List<String> keys,
) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList(growable: false);
    }
  }
  return const [];
}

Future<Object?> _bestEffort(Future<Object?> request) async {
  try {
    return await request;
  } catch (_) {
    return const <String, Object?>{};
  }
}

List<Map<String, Object?>> _embeddedCategoryRows(
  List<Map<String, Object?>> dishes,
) {
  final result = <Map<String, Object?>>[];
  for (final dish in dishes) {
    final nested = dish['type'] ?? dish['category'];
    if (nested is Map) {
      result.add(nested.cast<String, Object?>());
      continue;
    }
    final id = dish['typeId'] ?? dish['type_id'] ?? dish['category_id'];
    final label =
        dish['typeName'] ?? dish['type_name'] ?? dish['category_name'];
    if (id != null && label != null) {
      result.add({
        'id': id,
        'label': label,
        'cid': dish['cid'] ?? id,
        'sorting': dish['category_sorting'] ?? 0,
      });
    }
  }
  return result;
}

List<Map<String, Object?>> _paymentMethodRows(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }
  if (value is Map) {
    return value.values
        .whereType<List>()
        .expand((items) => items)
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }
  return const [];
}

bool _enabledFlag(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return switch ('$value'.trim().toLowerCase()) {
    'true' || '1' || 'yes' || 'enabled' => true,
    _ => false,
  };
}

num _minorToYuan(int amountMinor) {
  if (amountMinor.isNegative) {
    throw ArgumentError.value(
      amountMinor,
      'amountMinor',
      'Payment amounts cannot be negative',
    );
  }
  return amountMinor % 100 == 0 ? amountMinor ~/ 100 : amountMinor / 100;
}

List<PosCategory> _uniqueCategories(List<Map<String, Object?>> rows) {
  final categories = <String, PosCategory>{};
  for (final row in rows) {
    final category = PosCategory.fromJson(row);
    if (category.id <= 0 && category.code.isEmpty) continue;
    final key = category.id > 0 ? 'id:${category.id}' : 'cid:${category.code}';
    categories[key] = category;
  }
  final result = categories.values.toList();
  result.sort((a, b) => a.sorting.compareTo(b.sorting));
  return result;
}
