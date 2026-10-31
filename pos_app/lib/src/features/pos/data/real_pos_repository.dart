import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../../../core/cashier_operation_audit.dart';
import '../../cashier_settings/domain/receipt_preview_models.dart';
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
        PosOrderPrintRepository,
        PosKitchenPrintRepository,
        PosReceiptPrintRepository,
        PosPrintPreviewRepository,
        PosWechatNativeCheckoutRepository,
        PosWechatMicropayCheckoutRepository,
        PosReceivableRepository {
  const RealPosRepository(this.client, {this.onKitchenOrderChanged});

  final AdminApiClient client;
  final void Function()? onKitchenOrderChanged;

  static int? _linesAmountFen(List<PosCartLine> lines) {
    if (lines.isEmpty) return null;
    return lines.fold<int>(0, (sum, line) => sum + (line.total * 100).round());
  }

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
      kdsOrderStatus: fulfillment.kdsOrderStatus,
      lines: detail.lines
          .map(
            (line) => PosOrderLine(
              id: 0,
              name: line.name,
              quantity: line.quantity,
              total: line.totalPrice.toDouble(),
              specification: line.specification,
              refunded: line.isRefunded,
              productionStatus: line.productionStatus,
              kdsStatusText: line.kdsStatusText,
              kdsItemStatus: line.kdsItemStatus,
              kdsServedQuantity: line.kdsServedQuantity,
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
      _bestEffort(client.get(customerDishListAllEndpoint)),
      if (table.isOccupied)
        client.get(tableStatusEndpoint, query: {'number': table.number}),
    ];
    final responses = await Future.wait<Object?>(requests);
    final dishPayload = _map(responses[1]);
    final customerMenuCategories = _namedList(_map(responses[2]), const [
      'allDish',
      'all_dish',
    ]);
    final customerDishRows = <Map<String, Object?>>[
      for (final category in customerMenuCategories)
        ..._namedList(category, const ['dishList', 'dish_list']),
    ];
    final comboDefinitionsByDishId = <int, Object?>{
      for (final dish in customerDishRows)
        if (_integer(dish['id'] ?? dish['dish_id']) > 0 &&
            (dish['comboDefinition'] ?? dish['combo_definition']) != null)
          _integer(dish['id'] ?? dish['dish_id']):
              dish['comboDefinition'] ?? dish['combo_definition'],
    };
    final adminDishRows = objectList(dishPayload)
        .map(
          (dish) =>
              comboDefinitionsByDishId.containsKey(
                _integer(dish['id'] ?? dish['dish_id']),
              )
              ? <String, Object?>{
                  ...dish,
                  'comboDefinition':
                      comboDefinitionsByDishId[_integer(
                        dish['id'] ?? dish['dish_id'],
                      )],
                }
              : dish,
        )
        .toList(growable: false);
    final adminDishIds = adminDishRows
        .map((dish) => _integer(dish['id'] ?? dish['dish_id']))
        .where((id) => id > 0)
        .toSet();
    final dishRows = <Map<String, Object?>>[
      ...adminDishRows,
      for (final dish in customerDishRows)
        if (!adminDishIds.contains(_integer(dish['id'] ?? dish['dish_id'])))
          dish,
    ];
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
      ...customerMenuCategories,
      ..._embeddedCategoryRows(dishRows),
    ];
    final categories = _shopCategoriesUsedByDishes(
      _uniqueCategories(categoryRows),
      dishRows,
    );
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
    final statusMap = table.isOccupied && responses.length > 3
        ? _map(responses[3])
        : const <String, Object?>{};
    final tableRows = _namedList(statusMap, const ['tableList', 'table_list']);
    final orderRows = _namedList(statusMap, const ['orderList', 'order_list']);
    final resolvedTable = tableRows.isEmpty
        ? table
        : DiningTable.fromJson(tableRows.first);
    final tableOrders = <PosOrder>[];
    for (final rawOrder in orderRows) {
      final orderJson = Map<String, Object?>.from(rawOrder);
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
      var parsedOrder = PosOrder.fromJson(orderJson);
      if (parsedOrder.id > 0) {
        final hasSnapshotLines = parsedOrder.lines.isNotEmpty;
        final lacksKds =
            hasSnapshotLines &&
            parsedOrder.lines.any(
              (line) =>
                  line.kdsStatusText.isEmpty && line.kdsItemStatus.isEmpty,
            );
        // /admin/table/status 快照不返回 kds_* 字段：明细为空或快照行缺少
        // KDS 制作状态时，用 /admin/orderDetail/list 兜底合并（v1.2.224）。
        if (!hasSnapshotLines || lacksKds) {
          try {
            final detail = await client.get(
              orderDetailEndpoint,
              query: {'id': parsedOrder.id},
            );
            final lines = objectList(
              detail,
            ).map(PosOrderLine.fromJson).toList(growable: false);
            if (lines.isNotEmpty) {
              parsedOrder = parsedOrder.copyWith(
                lines: [
                  for (final l in lines)
                    l.orderNo.isEmpty
                        ? l.copyWith(orderNo: parsedOrder.orderNo)
                        : l,
                ],
              );
            }
          } catch (_) {
            // The table snapshot remains usable when detail loading is unavailable.
          }
        }
      }
      tableOrders.add(parsedOrder);
    }
    PosOrder? order;
    if (tableOrders.isNotEmpty) {
      order = tableOrders.firstWhere(
        (o) => !o.isMergedSlaveOrder,
        orElse: () => tableOrders.first,
      );
    }
    final paymentConfiguration = await _loadCashierPaymentMethods(
      orderNo: order?.orderNo ?? '',
    );
    return PosWorkspace(
      table: resolvedTable,
      categories: categories,
      dishes: dishes,
      currentOrder: order,
      tableOrders: tableOrders,
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
      // D017：C 端 `GET /config/payment-capabilities` 精简后，渠道识别统一
      // 读取 `clients.cashier.channelStates.<渠道>.enabled`（保存开关）。
      // 收银台「微信支付/支付宝」= 收款码渠道，统一以 `wechat_qr/alipay_qr`
      // 为准；商户线上渠道 `wechat/alipay` 不配置商户不可用，不作为收银台
      // 收款来源。`effectiveChannels/effectiveEnabled` 与 `paymentMethods`
      // 为历史契约兼容分支（旧后端仍可能返回）。
      final channelStates = _map(cashier['channelStates']);
      if (channelStates.isNotEmpty) {
        return _paymentMethodsFromChannels(_enabledFlag(cashier['enabled']), {
          'wechat': _map(channelStates['wechat'])['enabled'],
          'wechat_micropay': _map(channelStates['wechat_micropay'])['enabled'] ?? _map(channelStates['wechat'])['enabled'],
          'wechat_qr': _map(channelStates['wechat_qr'])['enabled'],
          'alipay': _map(channelStates['alipay_qr'])['enabled'],
          'balance': _map(channelStates['balance'])['enabled'],
          'combined': _map(channelStates['combined'])['enabled'],
          'receivable': _map(channelStates['receivable'])['enabled'],
        });
      }
      if (cashier.containsKey('effectiveChannels') ||
          cashier.containsKey('effectiveEnabled')) {
        return _paymentMethodsFromChannels(
          _enabledFlag(cashier['effectiveEnabled']),
          _map(cashier['effectiveChannels']),
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

  ({List<PosPaymentMethod> methods, bool available})
  _paymentMethodsFromChannels(bool enabled, Map<String, Object?> channels) {
    final hasWechatQrExplicit = channels.containsKey('wechat_qr');
    final methods = <PosPaymentMethod>[
      const PosPaymentMethod(
        id: 0,
        code: 'cash',
        name: '现金',
        sortOrder: 0,
        enabled: true,
      ),
      if (enabled && (_enabledFlag(channels['wechat_micropay']) || (hasWechatQrExplicit && _enabledFlag(channels['wechat']))))
        const PosPaymentMethod(
          id: 0,
          code: 'online_wechat_micropay',
          name: '微信付款码',
          sortOrder: 8,
          enabled: true,
        ),
      if (enabled && hasWechatQrExplicit && _enabledFlag(channels['wechat']))
        const PosPaymentMethod(
          id: 0,
          code: 'online_wechat',
          name: '微信支付',
          sortOrder: 10,
          enabled: true,
        ),
      if (enabled &&
          _enabledFlag(
            hasWechatQrExplicit ? channels['wechat_qr'] : channels['wechat'],
          ))
        const PosPaymentMethod(
          id: 0,
          code: 'offline_wechat_qr',
          name: '微信收款码',
          sortOrder: 15,
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
      if (enabled && (_enabledFlag(channels['receivable']) || channels['receivable'] == null))
        const PosPaymentMethod(
          id: 0,
          code: 'receivable',
          name: '客户挂账',
          sortOrder: 50,
          enabled: true,
        ),
    ];
    return (
      methods: List<PosPaymentMethod>.unmodifiable(methods),
      available: enabled,
    );
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
    final result = _submissionResult(data);
    onKitchenOrderChanged?.call();
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'create_order',
        result: 'success',
        targetType: 'table',
        targetId: tableNumber,
        amountFen: _linesAmountFen(lines),
        detail: {
          'fulfillment': '堂食',
          'diners': diners,
          'lines': lines.length,
          'order_no': result.orderNo,
        },
      ),
    );
    return result;
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
    final result = _submissionResult(data);
    onKitchenOrderChanged?.call();
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'create_order',
        result: 'success',
        targetType: 'takeout',
        targetId: '打包',
        amountFen: _linesAmountFen(lines),
        detail: {
          'fulfillment': '打包',
          'lines': lines.length,
          'order_no': result.orderNo,
        },
      ),
    );
    return result;
  }

  @override
  Future<int?> addDishes({
    required String orderNo,
    required String tableNumber,
    required List<PosCartLine> lines,
    String? clientRequestId,
    int? expectedVersion,
  }) async {
    _validateOrderLines(lines);
    final data = await client.post(
      cashierAddDishesEndpoint,
      headers: {
        'X-Client-Request-Id': _clientRequestId(
          'add-dishes',
          supplied: clientRequestId,
        ),
      },
      body: {
        'order_no': orderNo,
        'table_number': tableNumber,
        'goods_list': lines.map((line) => line.requestBody()).toList(),
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
      },
    );
    onKitchenOrderChanged?.call();
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'add_dish',
        result: 'success',
        targetType: 'order',
        targetId: orderNo,
        amountFen: _linesAmountFen(lines),
        detail: {'table_number': tableNumber, 'lines': lines.length},
      ),
    );
    return _extractRevision(data);
  }

  @override
  Future<int?> refundDish({
    required String orderNo,
    required int detailId,
    required int quantity,
    PosRefundStockAction? stockAction,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  }) async {
    final trimmedReason = reason?.trim() ?? '';
    final data = await client.post(
      cashierRefundDishEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('refund-dish')},
      body: {
        'order_no': orderNo,
        'detail_id': detailId,
        'quantity': quantity,
        if (stockAction != null) 'stock_action': stockAction.wireValue,
        if (trimmedReason.isNotEmpty) 'reason': trimmedReason,
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
        ..._sensitiveField(approvalToken, account, password),
      },
    );
    onKitchenOrderChanged?.call();
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'remove_dish',
        result: 'success',
        targetType: 'order',
        targetId: orderNo,
        detail: {
          'detail_id': detailId,
          'quantity': quantity,
          'reason': trimmedReason,
          'stock_action': stockAction?.wireValue,
        },
      ),
    );
    return _extractRevision(data);
  }

  @override
  Future<CashierManualRefundResult> manualRefund({
    required String orderNo,
    double? refundAmount,
    String? reason,
    String? account,
    String? password,
    String? approvalToken,
  }) async {
    final data = await client.post(
      cashierManualRefundEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('manual-refund')},
      body: {
        'order_no': orderNo.trim(),
        if (refundAmount != null && refundAmount > 0)
          'refund_amount': refundAmount,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
        ..._sensitiveField(approvalToken, account, password),
      },
    );
    final result = CashierManualRefundResult.fromJson(_map(data));
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'order',
        action: 'refund_cash',
        result: 'success',
        targetType: 'order',
        targetId: orderNo,
        amountFen: refundAmount != null ? (refundAmount * 100).round() : null,
        detail: {'reason': reason?.trim()},
      ),
    );
    return result;
  }

  @override
  Future<int?> giftDish({
    required String orderNo,
    required int detailId,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  }) async {
    final data = await client.post(
      cashierUpdatePriceEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('gift-dish')},
      body: {
        'order_no': orderNo,
        'detail_id': detailId,
        'total_price': 0,
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
        ..._sensitiveField(approvalToken, account, password),
      },
    );
    return _extractRevision(data);
  }

  @override
  Future<int?> discountOrder({
    required String orderNo,
    required double discountAmount,
    required String reason,
    String? account,
    String? password,
    String? approvalToken,
    int? expectedVersion,
  }) async {
    final data = await client.post(
      cashierDiscountEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('discount-order')},
      body: {
        'orderNo': orderNo,
        'discountAmount': discountAmount,
        'reason': reason.trim(),
        if (expectedVersion != null) 'expectedVersion': expectedVersion,
        ..._sensitiveField(approvalToken, account, password),
      },
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'discount',
        result: 'success',
        targetType: 'order',
        targetId: orderNo,
        amountFen: (discountAmount * 100).round(),
        detail: {'reason': reason.trim()},
      ),
    );
    return _extractRevision(data);
  }

  @override
  Future<void> updateDiners({
    required String orderNo,
    required int diners,
  }) async {
    await client.post(
      cashierOrderUpdateDinersEndpoint,
      headers: {'X-Client-Request-Id': _clientRequestId('update-diners')},
      body: {
        'order_no': orderNo.trim(),
        'number_of_diners': diners,
      },
    );
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'order',
        action: 'update_diners',
        result: 'success',
        targetType: 'order',
        targetId: orderNo,
        detail: {'diners': diners},
      ),
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
  Future<void> checkout({
    required String orderNo,
    required String paymentMethod,
    double? cashAmount,
    String collectionSessionId = '',
    bool force = false,
    String? approvalToken,
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
        if (force) 'force': true,
        if (approvalToken != null && approvalToken.trim().isNotEmpty)
          'approvalToken': approvalToken.trim(),
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
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'checkout',
        result: 'success',
        targetType: 'order',
        targetId: orderNo,
        detail: {'payment_method': paymentMethod, 'cash_amount': cashAmount},
      ),
    );
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
  Future<PosOfflineCollectionQr> createOfflineCollectionQr({
    required String channel,
    required String orderNo,
    required String sessionId,
    required int amountMinor,
  }) async {
    if (amountMinor <= 0) {
      throw const ApiException('待收金额须大于0，无法生成收款码');
    }
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
  Future<PosWechatNativeOrder> createWechatNativeOrder({
    required String orderNo,
    String? terminalId,
  }) async {
    try {
      final response = await client.post(
        cashierWechatNativeOrdersEndpoint,
        body: {
          'orderNo': orderNo.trim(),
          if (terminalId != null && terminalId.trim().isNotEmpty)
            'terminalId': terminalId.trim(),
        },
      );
      final map = _map(response);
      return PosWechatNativeOrder.fromJson(map);
    } on ApiException catch (e) {
      throw CashierWechatNativeException(
        code: e.code ?? -1,
        message: e.message,
      );
    }
  }

  @override
  Future<PosWechatNativeStatus> queryWechatNativeOrder({
    required String orderNo,
  }) async {
    try {
      final response = await client.get(
        cashierWechatNativeOrderQueryEndpoint.withPathParams({
          'orderNo': orderNo.trim(),
        }),
      );
      final map = _map(response);
      return PosWechatNativeStatus.fromJson(map);
    } on ApiException catch (e) {
      throw CashierWechatNativeException(
        code: e.code ?? -1,
        message: e.message,
      );
    }
  }

  @override
  Future<PosWechatNativeCloseResult> closeWechatNativeOrder({
    required String orderNo,
  }) async {
    try {
      final response = await client.post(
        cashierWechatNativeOrderCloseEndpoint.withPathParams({
          'orderNo': orderNo.trim(),
        }),
        body: {},
      );
      final map = _map(response);
      return PosWechatNativeCloseResult.fromJson(map);
    } on ApiException catch (e) {
      throw CashierWechatNativeException(
        code: e.code ?? -1,
        message: e.message,
      );
    }
  }

  @override
  Future<PosWechatMicropayOrder> payWechatMicropay({
    required String orderNo,
    required String authCode,
    String? terminalId,
  }) async {
    try {
      final response = await client.post(
        cashierWechatMicropayOrdersEndpoint,
        body: {
          'orderNo': orderNo.trim(),
          'authCode': authCode.trim(),
          if (terminalId != null && terminalId.trim().isNotEmpty)
            'terminalId': terminalId.trim(),
        },
      );
      final map = _map(response);
      return PosWechatMicropayOrder.fromJson(map);
    } on ApiException catch (e) {
      throw CashierWechatMicropayException(
        code: e.code ?? -1,
        message: e.message,
      );
    }
  }

  @override
  Future<PosWechatMicropayStatus> queryWechatMicropayOrder({
    required String orderNo,
  }) async {
    try {
      final response = await client.get(
        cashierWechatMicropayOrderQueryEndpoint.withPathParams({
          'orderNo': orderNo.trim(),
        }),
      );
      final map = _map(response);
      return PosWechatMicropayStatus.fromJson(map);
    } on ApiException catch (e) {
      throw CashierWechatMicropayException(
        code: e.code ?? -1,
        message: e.message,
      );
    }
  }

  @override
  Future<PosWechatMicropayReverseResult> reverseWechatMicropayOrder({
    required String orderNo,
  }) async {
    try {
      final response = await client.post(
        cashierWechatMicropayOrderReverseEndpoint.withPathParams({
          'orderNo': orderNo.trim(),
        }),
        body: {},
      );
      final map = _map(response);
      return PosWechatMicropayReverseResult.fromJson(map);
    } on ApiException catch (e) {
      throw CashierWechatMicropayException(
        code: e.code ?? -1,
        message: e.message,
      );
    }
  }

  @override
  Future<List<PosReceivableEligibleAccount>> loadEligibleAccounts() async {
    try {
      final response = await client.get(cashierReceivableEligibleAccountsEndpoint);
      final rawList = response is List
          ? response
          : (response is Map && response['accounts'] is List)
              ? response['accounts'] as List
              : (response is Map && response['data'] is List)
                  ? response['data'] as List
                  : const [];
      return rawList
          .whereType<Map>()
          .map((e) => PosReceivableEligibleAccount.fromJson(e.cast<String, Object?>()))
          .toList(growable: false);
    } on ApiException catch (e) {
      throw CashierReceivableException(code: e.code ?? -1, message: e.message);
    }
  }

  @override
  Future<PosReceivableClaim> chargeReceivable({
    required String orderNo,
    required int accountId,
    required String requestId,
    String? note,
  }) async {
    try {
      final response = await client.post(
        cashierReceivableChargesEndpoint,
        body: {
          'orderNo': orderNo.trim(),
          'accountId': accountId,
          'requestId': requestId.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
        },
      );
      final map = _map(response);
      final claimMap = map['claim'] is Map
          ? (map['claim'] as Map).cast<String, Object?>()
          : map;
      return PosReceivableClaim.fromJson(claimMap);
    } on ApiException catch (e) {
      throw CashierReceivableException(code: e.code ?? -1, message: e.message);
    }
  }

  @override
  Future<List<PosReceivableClaim>> loadReceivableClaims({
    int? accountId,
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final queryParams = <String, String>{
        'page': '$page',
        'pageSize': '$pageSize',
        if (accountId != null) 'accountId': '$accountId',
        if (status != null && status.isNotEmpty) 'status': status,
      };
      final response = await client.get(
        cashierReceivableClaimsEndpoint,
        query: queryParams,
      );
      final map = _map(response);
      final rawList = map['items'] is List
          ? map['items'] as List
          : (map['data'] is List ? map['data'] as List : const []);
      return rawList
          .whereType<Map>()
          .map((e) => PosReceivableClaim.fromJson(e.cast<String, Object?>()))
          .toList(growable: false);
    } on ApiException catch (e) {
      throw CashierReceivableException(code: e.code ?? -1, message: e.message);
    }
  }

  @override
  Future<PosReceivableClaim> loadReceivableClaimDetail(int id) async {
    try {
      final response = await client.get(
        cashierReceivableClaimDetailEndpoint.withPathParams({'id': '$id'}),
      );
      final map = _map(response);
      final claimMap = map['claim'] is Map
          ? (map['claim'] as Map).cast<String, Object?>()
          : map;
      return PosReceivableClaim.fromJson(claimMap);
    } on ApiException catch (e) {
      throw CashierReceivableException(code: e.code ?? -1, message: e.message);
    }
  }

  @override
  Future<PosReceivableLedger> collectReceivable({
    required int claimId,
    required int amountFen,
    required String channel,
    required String requestId,
    String? note,
    int? drawerSessionId,
  }) async {
    try {
      final response = await client.post(
        cashierReceivableCollectionsEndpoint.withPathParams({'id': '$claimId'}),
        body: {
          'amountFen': amountFen,
          'channel': channel,
          'requestId': requestId.trim(),
          if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
          if (drawerSessionId != null) 'drawerSessionId': drawerSessionId,
        },
      );
      final map = _map(response);
      final ledgerMap = map['ledger'] is Map
          ? (map['ledger'] as Map).cast<String, Object?>()
          : map;
      return PosReceivableLedger.fromJson(ledgerMap);
    } on ApiException catch (e) {
      throw CashierReceivableException(code: e.code ?? -1, message: e.message);
    }
  }

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
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'checkout',
        result: 'success',
        targetType: 'order',
        targetId: orderNo,
        amountFen:
            settlement.wechatMinor +
            settlement.alipayMinor +
            settlement.balanceMinor +
            settlement.cashMinor,
        detail: {
          'payment_method': PosPaymentChannelKind.combined.canonicalCode,
          'wechat_minor': settlement.wechatMinor,
          'alipay_minor': settlement.alipayMinor,
          'balance_minor': settlement.balanceMinor,
          'cash_minor': settlement.cashMinor,
        },
      ),
    );
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
  Future<String?> hangOrder({required String orderNo, String? reason}) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      throw ArgumentError('挂单需要有效订单号');
    }
    final response = await client.post(
      cashierOrderHangEndpoint,
      body: {
        'order_no': normalizedOrderNo,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    final map = _map(response);
    // client.post 已解包 data；兼容未解包场景（map['data'] 存在时优先）。
    final data = (map['data'] is Map) ? map['data'] : map;
    // 服务端返回挂单号（hang_no/hangNo）时带回；仅返回列表/空时不强求。
    if (data is Map) {
      final raw = data['hang_no'] ?? data['hangNo'] ?? data['order_no'];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    }
    return null;
  }

  @override
  Future<bool> unhangOrder({required String orderNo}) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      throw ArgumentError('取单需要有效订单号');
    }
    final response = await client.post(
      cashierOrderUnhangEndpoint,
      body: {'order_no': normalizedOrderNo},
    );
    final map = _map(response);
    return map['code'] == 0 || map['hang_status'] == 0;
  }

  @override
  Future<List<HangOrderSummary>> getHangList() async {
    final response = await client.get(cashierOrderHangListEndpoint);
    final map = _map(response);
    final rawList = map['list'] ??
        (map['data'] is Map ? (map['data'] as Map)['list'] : null) ??
        (map['data'] is List ? map['data'] : null);
    if (rawList is List) {
      return rawList
          .whereType<Map>()
          .map((item) => HangOrderSummary.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false);
    }
    return const [];
  }

  @override
  Future<PosPrintResult> printFrontTicket({
    required int orderId,
    String? orderNo,
  }) => printReceiptTicket(
    type: PosReceiptPrintType.front,
    orderId: orderId,
    orderNo: orderNo ?? '',
  );

  @override
  Future<PosPrintResult> printReceiptTicket({
    required PosReceiptPrintType type,
    required int orderId,
    required String orderNo,
  }) async {
    final normalizedOrderNo = orderNo.trim();
    if (orderId <= 0 && normalizedOrderNo.isEmpty) {
      throw ArgumentError('打印小票需要有效订单');
    }
    final response = await client.post(
      cashierPrintDispatchEndpoint,
      body: {
        if (orderId > 0) 'order_id': orderId,
        if (normalizedOrderNo.isNotEmpty) 'order_no': normalizedOrderNo,
        'scenario': type.scenario,
        'is_reprint': true,
      },
    );
    final map = _map(response);
    final data = (map['data'] is Map<String, dynamic>)
        ? map['data'] as Map<String, dynamic>
        : (map['data'] is Map)
        ? (map['data'] as Map).cast<String, dynamic>()
        : map;
    return PosPrintResult.fromJson({
      ...data,
      if (normalizedOrderNo.isNotEmpty &&
          data['order_no'] == null &&
          data['orderNo'] == null)
        'order_no': normalizedOrderNo,
    });
  }

  @override
  Future<void> reprintKitchenTicket({required String orderNo}) async {
    final normalizedOrderNo = orderNo.trim();
    if (normalizedOrderNo.isEmpty) {
      throw ArgumentError('后厨补打需要有效订单号');
    }
    await printReceiptTicket(
      type: PosReceiptPrintType.kitchen,
      orderId: 0,
      orderNo: normalizedOrderNo,
    );
  }

  @override
  Future<PrintPreviewResult> fetchPrintPreview({
    String scenario = 'ORDER',
    int? orderId,
    String? orderNo,
    int? deviceId,
    String paperSize = '58mm',
    bool isAddDishes = false,
    String? customContent,
  }) async {
    final response = await client.request(
      settingsPrintingPreviewPostEndpoint,
      body: {
        'scenario': scenario,
        if (orderId != null) 'orderId': orderId,
        if (orderNo != null) 'orderNo': orderNo,
        if (deviceId != null) 'deviceId': deviceId,
        'paperSize': paperSize,
        'isAddDishes': isAddDishes,
        if (customContent != null) 'customContent': customContent,
      },
    );
    final map = _map(response);
    final dataMap = map['data'] is Map ? _map(map['data']) : map;
    return PrintPreviewResult.fromJson(dataMap);
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
      body: {'order_no': orderNo.trim(), 'reason': reason.trim()},
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
  Future<PosTableCheckoutResult> checkoutTable({
    required String tableNumber,
    String paymentMethod = 'cash',
    double? cashAmount,
    bool force = false,
    String? approvalToken,
  }) async {
    final idempotencyKey = _tableIdempotencyKey('table-checkout');
    final data = await client.post(
      cashierTableCheckoutEndpoint,
      headers: {
        'Idempotency-Key': idempotencyKey,
        'X-Client-Request-Id': _clientRequestId('table-checkout'),
      },
      body: {
        'tableNumber': tableNumber,
        'paymentMethod': paymentMethod,
        if (cashAmount != null) 'cashAmount': cashAmount,
        'idempotencyKey': idempotencyKey,
        if (force) 'force': true,
        if (approvalToken != null && approvalToken.trim().isNotEmpty)
          'approvalToken': approvalToken.trim(),
      },
    );
    final map = _map(data);
    final result = PosTableCheckoutResult.fromJson(map);
    CashierOperationAuditStore.instance.record(
      CashierOperationAuditDraft(
        module: 'pos',
        action: 'table_checkout',
        result: 'success',
        targetType: 'table',
        targetId: tableNumber,
        detail: {
          'payment_method': paymentMethod,
          if (cashAmount != null) 'cash_amount': cashAmount,
          'settled_orders': result.settledOrders,
          'total_amount': result.totalAmount,
          'change_amount': result.changeAmount,
        },
      ),
    );
    return result;
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

Map<String, String> _sensitiveAuthorization(String? account, String? password) {
  final normalizedAccount = account?.trim() ?? '';
  if (normalizedAccount.isEmpty || password == null || password.isEmpty) {
    throw const ApiException('敏感操作需要现场输入授权员工账号和密码');
  }
  return {'account': normalizedAccount, 'password': password};
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
  return {'authorization': _sensitiveAuthorization(account, password)};
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

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

/// 收银台点餐仅展示「本店菜单实际使用」的分类。
///
/// `t_category` 为全局共享类目主数据（无门店维度），
/// `GET /admin/category/listAll` 按设计全表返回；若收银端不按本店菜品过滤，
/// 会把其他门店或无菜品的分类一并显示（跨店分类串台）。
/// 以合并后的本店菜品（含 C 端全量菜单兜底）分类主键/分类码为命中依据，
/// 语义与 C 端 `GET /dish/listAll` 的「空分类不下发」保持一致。
List<PosCategory> _shopCategoriesUsedByDishes(
  List<PosCategory> categories,
  List<Map<String, Object?>> dishRows,
) {
  if (categories.isEmpty || dishRows.isEmpty) return categories;
  final usedIds = <int>{};
  final usedCodes = <String>{};
  for (final dish in dishRows) {
    final nestedType = dish['type'] is Map
        ? (dish['type'] as Map).cast<String, Object?>()
        : dish['category'] is Map
        ? (dish['category'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final id = _integer(
      dish['typeId'] ??
          dish['type_id'] ??
          dish['category_id'] ??
          dish['categoryId'] ??
          nestedType['id'],
    );
    if (id > 0) usedIds.add(id);
    final code = _string(
      dish['cid'] ??
          dish['category_code'] ??
          dish['categoryCode'] ??
          nestedType['cid'] ??
          nestedType['value'],
    );
    if (code.isNotEmpty) usedCodes.add(code);
  }
  return categories
      .where(
        (category) =>
            (category.id > 0 && usedIds.contains(category.id)) ||
            (category.code.isNotEmpty && usedCodes.contains(category.code)),
      )
      .toList(growable: false);
}

int? _extractRevision(Object? response) {
  if (response is Map) {
    final rev = response['revision'] ??
        (response['data'] is Map ? (response['data'] as Map)['revision'] : null) ??
        (response['order'] is Map ? (response['order'] as Map)['revision'] : null);
    if (rev is num) return rev.toInt();
    if (rev != null) return int.tryParse('$rev');
  }
  return null;
}
