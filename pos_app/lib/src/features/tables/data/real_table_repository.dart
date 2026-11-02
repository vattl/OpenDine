import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/dining_table.dart';
import '../domain/takeout_delivery.dart';
import 'table_repository.dart';

class RealTableRepository
    implements TableRepository, TakeoutDeliveryRepository {
  const RealTableRepository(this.client);

  final AdminApiClient client;

  @override
  Future<TableOverview> loadTableOverview() async {
    final orderCountsFuture = _loadOrderCounts();
    final tables = await _loadTablesFromStatusMapOrFallback();
    final orderCounts = await orderCountsFuture;
    return TableOverview(
      tables: tables,
      takeoutOrders: orderCounts.takeoutOrders,
      pickupOrders: orderCounts.pickupOrders,
    );
  }

  /// 仅拉取履约订单（外卖/自提）快照，不拉取桌台状态图（用于顶部常驻栏红点计数）
  Future<TableOverview> loadFulfillmentOverview() async {
    final orderCounts = await _loadOrderCounts();
    return TableOverview(
      tables: const [],
      takeoutOrders: orderCounts.takeoutOrders,
      pickupOrders: orderCounts.pickupOrders,
    );
  }

  /// 收银端桌台状态图（POST 无；GET /cashier/table/statusMap）优先；
  /// 聚合快照不可用（版本差异/网络/权限）时回退运营端 /admin/table/status，
  /// 保证收银台桌台列表始终可用。
  Future<List<DiningTable>> _loadTablesFromStatusMapOrFallback() async {
    try {
      final data = await client.get(cashierTableStatusMapEndpoint);
      final rows = _statusMapRows(data);
      if (rows.isNotEmpty) {
        return rows.map(DiningTable.fromJson).toList(growable: false)
          ..sort(_compareTableNumber);
      }
    } catch (_) {
      // Fall back to the legacy admin snapshot below.
    }
    final data = await client.get(tableStatusEndpoint);
    return objectList(data).map(DiningTable.fromJson).toList(growable: false)
      ..sort(_compareTableNumber);
  }

  Future<_OrderCounts> _loadOrderCounts() async {
    try {
      final shopId = client.shopId ?? 0;
      final data = await client.post(
        orderListEndpoint,
        body: {
          'pageNum': 1,
          'pageSize': 100,
          'start': 0,
          'transac_status': '',
          'query': '',
          'keyword': '',
          if (shopId > 0) 'shop_id': shopId,
        },
      );
      return _OrderCounts.fromRows(
        objectList(data),
        currentShopId: shopId,
      );
    } catch (_) {
      return const _OrderCounts();
    }
  }

  @override
  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  ) async {
    if (order.tableNumber.isEmpty && order.orderNo.isNotEmpty) {
      return _loadFulfillmentOrderDetailByOrderNo(order);
    }
    if (order.id <= 0) throw ArgumentError('订单 ID 无效');
    final data = await client.get(orderDetailEndpoint, query: {'id': order.id});
    final orderJson = _namedMap(data, 'order');
    final current = orderJson == null
        ? order
        : FulfillmentOrder.fromJson(orderJson, type: order.type);
    final remark = orderJson != null
        ? _string(
            orderJson['remark'] ??
                orderJson['note'] ??
                orderJson['memo'] ??
                orderJson['order_remark'] ??
                orderJson['orderRemark'] ??
                orderJson['user_remark'] ??
                orderJson['userRemark'],
          )
        : current.remark;
    return FulfillmentOrderDetail(
      order: current,
      lines: _detailRows(
        data,
      ).map(FulfillmentOrderLine.fromJson).toList(growable: false),
      paymentMethod: orderJson == null
          ? ''
          : _string(orderJson['payment_method'] ?? orderJson['paymentMethod']),
      remark: remark.isNotEmpty ? remark : current.remark,
    );
  }

  Future<FulfillmentOrderDetail> _loadFulfillmentOrderDetailByOrderNo(
    FulfillmentOrder order,
  ) async {
    final data = await client.get(
      tableStatusEndpoint,
      query: {'orderNo': order.orderNo},
    );
    final orderJson = _matchingOrder(data, order.orderNo);
    if (orderJson == null) {
      throw StateError('未找到订单 ${order.orderNo}');
    }
    final current = FulfillmentOrder.fromJson(orderJson, type: order.type);
    final remark = _string(
      orderJson['remark'] ??
          orderJson['note'] ??
          orderJson['memo'] ??
          orderJson['order_remark'] ??
          orderJson['orderRemark'] ??
          orderJson['user_remark'] ??
          orderJson['userRemark'],
    );
    return FulfillmentOrderDetail(
      order: current,
      lines: _goodsRows(
        orderJson,
      ).map(FulfillmentOrderLine.fromJson).toList(growable: false),
      paymentMethod: _string(
        orderJson['payment_method'] ?? orderJson['paymentMethod'],
      ),
      remark: remark.isNotEmpty ? remark : current.remark,
    );
  }

  @override
  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  ) async {
    if (order.id <= 0) throw ArgumentError('订单 ID 无效');
    if (status == FulfillmentStatus.pendingPayment) {
      throw ArgumentError('待结账状态需通过结账模块处理');
    }
    if (order.type == FulfillmentType.takeout &&
        (status == FulfillmentStatus.delivering ||
            status == FulfillmentStatus.completed)) {
      await client.post(
        takeoutDeliveryStatusEndpoint,
        body: {
          'orderId': order.id,
          'dispatch_status': status == FulfillmentStatus.delivering
              ? 'delivering'
              : 'completed',
        },
      );
      return;
    }
    await client.post(
      orderReceivingEndpoint,
      body: {
        'id': order.id,
        'order_receiving': status == FulfillmentStatus.completed
            ? 'off_order'
            : 'rec_order',
      },
    );
  }

  @override
  Future<void> createTable({
    required String number,
    int peopleCount = 4,
    String? areaCode,
    String? areaName,
  }) async {
    await client.post(
      tableAddEndpoint,
      body: {
        'number': number.trim(),
        'table_number': number.trim(),
        'people_count': peopleCount,
        if (areaCode != null && areaCode.isNotEmpty) 'area_code': areaCode,
        if (areaName != null && areaName.isNotEmpty) 'area_name': areaName,
      },
    );
  }

  @override
  Future<void> updateTable({
    required int id,
    required String number,
    int? peopleCount,
    String? areaCode,
    String? areaName,
  }) async {
    await client.post(
      tableUpdateEndpoint,
      body: {
        'id': id,
        'number': number.trim(),
        'table_number': number.trim(),
        if (peopleCount != null) 'people_count': peopleCount,
        if (areaCode != null && areaCode.isNotEmpty) 'area_code': areaCode,
        if (areaName != null && areaName.isNotEmpty) 'area_name': areaName,
      },
    );
  }

  @override
  Future<void> deleteTable(int id) async {
    await client.get(
      tableDeleteEndpoint,
      query: {'id': '$id'},
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
      body: {
        'workNo': account,
        'userName': account,
        'password': password,
      },
    );
  }

  @override
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(
    FulfillmentOrder order,
  ) async {
    if (order.type != FulfillmentType.takeout || order.id <= 0) return null;
    final detailData = await client.get(
      takeoutDeliveryDetailEndpoint,
      query: {'orderId': order.id},
    );
    final detailMap = _responseMap(detailData);
    if (detailMap == null) return null;
    final detail = TakeoutDeliverySnapshot.fromJson(detailMap);
    if (detail.delivery.zsqOpenOrderId <= 0) return detail;
    try {
      final trackingData = await client.get(
        takeoutDeliveryTrackingEndpoint,
        query: {'orderId': order.id},
      );
      final trackingMap = _responseMap(trackingData);
      return trackingMap == null
          ? detail
          : TakeoutDeliverySnapshot.fromJson(trackingMap);
    } on ApiException catch (error) {
      if (error.code == 4091) {
        try {
          final refreshedData = await client.get(
            takeoutDeliveryDetailEndpoint,
            query: {'orderId': order.id},
          );
          final refreshedMap = _responseMap(refreshedData);
          if (refreshedMap != null) {
            return TakeoutDeliverySnapshot.fromJson(refreshedMap);
          }
        } catch (_) {
          // The 4091 result is authoritative even if the follow-up detail read
          // fails; preserve receiver data while clearing stale rider/order IDs.
        }
        return detail.asOrderMissing(error.message);
      }
      // A temporary tracking failure must not hide persisted delivery details.
      return detail;
    } catch (_) {
      // A temporary tracking failure must not hide persisted delivery details.
      return detail;
    }
  }

  @override
  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  }) async {
    if (order.type != FulfillmentType.takeout || order.id <= 0) {
      throw ArgumentError('仅有效外卖订单可以叫骑手');
    }
    final data = await client.post(
      redispatch ? takeoutZsqRedispatchEndpoint : takeoutZsqDispatchEndpoint,
      body: {'orderId': order.id},
    );
    final response = _responseMap(data);
    if (response != null && _namedMap(response, 'delivery') != null) {
      return TakeoutDeliverySnapshot.fromJson(response);
    }
    final refreshed = await loadTakeoutDelivery(order);
    if (refreshed == null) throw StateError('叫骑手成功，但未返回配送信息');
    return refreshed;
  }

  @override
  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(
    FulfillmentOrder order,
  ) async {
    if (order.type != FulfillmentType.takeout || order.id <= 0) {
      throw ArgumentError('仅有效外卖订单可以取消配送');
    }
    final data = await client.post(
      takeoutDeliveryStatusEndpoint,
      body: {'orderId': order.id, 'dispatch_status': 'cancelled'},
    );
    final response = _responseMap(data);
    if (response != null && _namedMap(response, 'delivery') != null) {
      return TakeoutDeliverySnapshot.fromJson(response);
    }
    final refreshed = await loadTakeoutDelivery(order);
    if (refreshed == null) throw StateError('取消配送成功，但未返回配送信息');
    return refreshed;
  }

  @override
  Future<List<Map<String, dynamic>>> loadTableAreas() async {
    try {
      final res = await client.get(cashierTableAreasEndpoint);
      if (res is Map && res['data'] is List) {
        return (res['data'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(growable: false);
      }
      return objectList(res)
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    } catch (_) {
      return const [
        {'code': 'hall', 'name': '大厅散座', 'sort': 1},
        {'code': 'box', 'name': '特色包厢', 'sort': 2},
        {'code': 'patio', 'name': '露天外摆', 'sort': 3},
      ];
    }
  }

  @override
  Future<void> batchClearTables({
    List<int>? tableIds,
    List<String>? tableNumbers,
    String? operatorAccount,
  }) async {
    await client.post(
      cashierTableBatchClearEndpoint,
      body: {
        if (tableIds != null && tableIds.isNotEmpty) 'table_ids': tableIds,
        if (tableNumbers != null && tableNumbers.isNotEmpty)
          'table_numbers': tableNumbers,
        if (operatorAccount != null) 'operator_account': operatorAccount,
      },
    );
  }

  @override
  Future<void> updateTableDiners({
    required String orderNo,
    required String tableNumber,
    required int diners,
    String? operatorAccount,
  }) async {
    await client.put(
      posOrderUpdateDinersPathEndpoint(orderNo),
      body: {
        'diners': diners,
        'table_number': tableNumber,
        if (operatorAccount != null) 'operator_account': operatorAccount,
      },
    );
  }

  @override
  Future<Map<String, dynamic>?> loadTablePulse() async {
    try {
      final res = await client.get(cashierTablePulseEndpoint);
      if (res is Map<String, dynamic>) {
        if (res['data'] is Map<String, dynamic>) {
          return res['data'] as Map<String, dynamic>;
        }
        return res;
      }
    } catch (_) {}
    return null;
  }
}

Map<String, Object?>? _responseMap(Object? value) {
  if (value is! Map) return null;
  return value.cast<String, Object?>();
}

/// 解析收银桌台状态图响应（GET /cashier/table/statusMap）：
/// 优先 `list`/`tableList`/`table_list`/`tables`（完整桌台行）；
/// 否则解析 `map`（桌号 -> status，仅含桌号与状态，供状态色板渲染）。
List<Map<String, Object?>> _statusMapRows(Object? value) {
  if (value is! Map) return const [];
  for (final key in const ['list', 'tableList', 'table_list', 'tables']) {
    final rows = value[key];
    if (rows is List) {
      final parsed = rows
          .whereType<Map>()
          .map((row) => row.cast<String, Object?>())
          .toList(growable: false);
      if (parsed.isNotEmpty) return parsed;
    }
  }
  final map = value['map'];
  if (map is Map) {
    final rows = <Map<String, Object?>>[];
    map.forEach((key, status) {
      rows.add(<String, Object?>{'number': '$key', 'status': status});
    });
    if (rows.isNotEmpty) return rows;
  }
  return const [];
}

Map<String, Object?>? _matchingOrder(Object? value, String orderNo) {
  if (value is Map) {
    final rows = value['orderList'] ?? value['order_list'];
    if (rows is List) {
      final orders = rows.whereType<Map>().map(
        (row) => row.cast<String, Object?>(),
      );
      for (final row in orders) {
        if (_string(row['order_no'] ?? row['orderNo']) == orderNo) return row;
      }
      return null;
    }
    for (final key in const ['data', 'result', 'payload']) {
      final order = _matchingOrder(value[key], orderNo);
      if (order != null) return order;
    }
  }
  return null;
}

List<Map<String, Object?>> _goodsRows(Map<String, Object?> order) {
  for (final key in const [
    'goods_list',
    'goodsList',
    'orderDetailList',
    'order_detail_list',
    'details',
    'items',
    'lines',
  ]) {
    final rows = order[key];
    if (rows is List) return _detailRows(rows);
  }
  return const [];
}

Map<String, Object?>? _namedMap(Object? value, String key) {
  if (value is! Map) return null;
  final direct = value[key];
  if (direct is Map) return direct.cast<String, Object?>();
  for (final nestedKey in const ['data', 'result', 'payload']) {
    final nested = _namedMap(value[nestedKey], key);
    if (nested != null) return nested;
  }
  return null;
}

List<Map<String, Object?>> _detailRows(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }
  if (value is Map) {
    for (final key in const [
      'list',
      'orderDetailList',
      'order_detail_list',
      'details',
      'items',
      'lines',
    ]) {
      final rows = value[key];
      if (rows is List) return _detailRows(rows);
    }
    for (final key in const ['data', 'result', 'payload']) {
      final rows = _detailRows(value[key]);
      if (rows.isNotEmpty) return rows;
    }
  }
  return const [];
}

int _compareTableNumber(DiningTable left, DiningTable right) {
  final leftNumber = int.tryParse(left.number);
  final rightNumber = int.tryParse(right.number);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }
  return left.number.compareTo(right.number);
}

class _OrderCounts {
  const _OrderCounts({
    this.takeoutOrders = const [],
    this.pickupOrders = const [],
  });

  final List<FulfillmentOrder> takeoutOrders;
  final List<FulfillmentOrder> pickupOrders;

  factory _OrderCounts.fromRows(
    List<Map<String, Object?>> rows, {
    int currentShopId = 0,
  }) {
    final takeoutOrders = <FulfillmentOrder>[];
    final pickupOrders = <FulfillmentOrder>[];
    for (final row in rows) {
      if (!_isOrderForCurrentShop(row, currentShopId)) continue;
      if (_isCancelledOrder(row)) continue;
      if (_isTakeoutOrder(row)) {
        takeoutOrders.add(
          FulfillmentOrder.fromJson(row, type: FulfillmentType.takeout),
        );
      }
      if (_isPickupOrder(row)) {
        pickupOrders.add(
          FulfillmentOrder.fromJson(row, type: FulfillmentType.pickup),
        );
      }
    }
    return _OrderCounts(
      takeoutOrders: takeoutOrders,
      pickupOrders: pickupOrders,
    );
  }
}

bool _isOrderForCurrentShop(Map<String, Object?> row, int currentShopId) {
  if (currentShopId <= 0) return true;
  final hasShopKey = row.containsKey('shop_id') ||
      row.containsKey('shopId') ||
      row.containsKey('store_id') ||
      row.containsKey('storeId');
  if (!hasShopKey) return true;
  final rawShopId =
      row['shop_id'] ?? row['shopId'] ?? row['store_id'] ?? row['storeId'];
  if (rawShopId == null || _string(rawShopId).isEmpty) {
    return currentShopId == 1;
  }
  final rowShopId = _int(rawShopId);
  return rowShopId == currentShopId;
}

bool _isCancelledOrder(Map<String, Object?> row) {
  // 外卖「配送」取消（takeout_dispatch_status=cancelled）不等于订单取消：
  // 订单可能已结账、已出餐，只是第三方配送调度被放弃。取消判断只看订单级
  // 状态，避免把这类已完成的配送单误过滤掉。
  final status = _string(
    row['receiving_status'] ?? row['receivingStatus'] ?? row['order_receiving'],
  ).toLowerCase();
  final transaction = _string(
    row['transac_status'] ??
        row['transacStatus'] ??
        row['pay_status'] ??
        row['payStatus'],
  ).toLowerCase();
  return status == 'cancelled' ||
      status == '已取消' ||
      transaction == 'cancelled' ||
      transaction == '已取消';
}

bool _isTakeoutOrder(Map<String, Object?> row) {
  final type = _orderType(row);
  return type == '外卖' ||
      type.toLowerCase() == 'takeout' ||
      _int(row['takeout_delivery_id'] ?? row['takeoutDeliveryId']) > 0;
}

bool _isPickupOrder(Map<String, Object?> row) {
  final type = _orderType(row);
  final normalized = type.toLowerCase();
  return type == '自提' ||
      type == '打包' ||
      normalized == 'pickup' ||
      normalized == 'self_pickup';
}

String _orderType(Map<String, Object?> row) {
  return _string(
    row['order_type'] ?? row['orderType'] ?? row['dineInOrTakeOut'],
  );
}

String _string(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
