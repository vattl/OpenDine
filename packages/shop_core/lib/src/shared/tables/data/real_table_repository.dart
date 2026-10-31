import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/dining_table.dart';
import 'table_repository.dart';

class RealTableRepository implements TableRepository {
  const RealTableRepository(this.client);

  final AdminApiClient client;

  @override
  Future<TableOverview> loadTableOverview() async {
    final orderCountsFuture = _loadOrderCounts();
    final data = await client.get(tableStatusEndpoint);
    final rows = objectList(data);
    final tables = rows.map(DiningTable.fromJson).toList(growable: false)
      ..sort(_compareTableNumber);
    final orderCounts = await orderCountsFuture;
    return TableOverview(
      tables: tables,
      takeoutOrders: orderCounts.takeoutOrders,
      pickupOrders: orderCounts.pickupOrders,
    );
  }

  @override
  Future<void> createTable(String number) async {
    final trimmed = number.trim();
    if (trimmed.isEmpty) throw ArgumentError('桌台号不能为空');
    await client.post(tableAddEndpoint, body: {'number': trimmed});
  }

  @override
  Future<void> deleteTable(int id) async {
    if (id <= 0) throw ArgumentError('桌台 ID 无效');
    await client.get(tableDeleteEndpoint, query: {'id': id});
  }

  Future<_OrderCounts> _loadOrderCounts() async {
    try {
      final data = await client.post(
        orderListEndpoint,
        body: const {
          'pageNum': 1,
          'pageSize': 100,
          'start': 0,
          'transac_status': '',
          'query': '',
          'keyword': '',
        },
      );
      return _OrderCounts.fromRows(objectList(data));
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
    return FulfillmentOrderDetail(
      order: current,
      lines: _detailRows(
        data,
      ).map(FulfillmentOrderLine.fromJson).toList(growable: false),
      paymentMethod: orderJson == null
          ? ''
          : _string(orderJson['payment_method'] ?? orderJson['paymentMethod']),
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
    return FulfillmentOrderDetail(
      order: current,
      lines: _goodsRows(
        orderJson,
      ).map(FulfillmentOrderLine.fromJson).toList(growable: false),
      paymentMethod: _string(
        orderJson['payment_method'] ?? orderJson['paymentMethod'],
      ),
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

  factory _OrderCounts.fromRows(List<Map<String, Object?>> rows) {
    final takeoutOrders = <FulfillmentOrder>[];
    final pickupOrders = <FulfillmentOrder>[];
    for (final row in rows) {
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

bool _isCancelledOrder(Map<String, Object?> row) {
  final status = _string(
    row['receiving_status'] ?? row['receivingStatus'] ?? row['order_receiving'],
  ).toLowerCase();
  final dispatch = _string(
    row['dispatch_status'] ??
        row['dispatchStatus'] ??
        row['takeout_dispatch_status'] ??
        row['takeoutDispatchStatus'],
  ).toLowerCase();
  return status == 'cancelled' ||
      status == '已取消' ||
      dispatch == 'cancelled' ||
      dispatch == '已取消';
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
