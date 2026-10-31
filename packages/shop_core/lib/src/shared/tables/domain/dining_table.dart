class DiningTable {
  const DiningTable({
    this.id = 0,
    required this.number,
    required this.status,
    required this.people,
    this.amount,
    this.openedAt,
    this.receivingStatus = '',
    this.orderNo = '',
  });

  final int id;
  final String number;
  final TableStatus status;
  final int people;
  final num? amount;
  final DateTime? openedAt;
  final String receivingStatus;

  /// 该桌绑定的未结订单号（后端 table/status 返回 order_no）。用于从桌台直接跳订单详情。
  final String orderNo;

  bool get isOccupied => status != TableStatus.empty;
  bool get canClearAfterCheckout =>
      status == TableStatus.settled && amount != null && amount == 0;

  Duration? occupiedDuration(DateTime now) {
    final start = openedAt;
    if (!isOccupied || start == null) return null;
    final duration = now.difference(start);
    return duration.isNegative ? Duration.zero : duration;
  }

  factory DiningTable.fromJson(Map<String, Object?> json) {
    final status = _status(json);
    return DiningTable(
      id: _int(json['id'] ?? json['table_id'] ?? json['tableId'], fallback: 0),
      number: _string(
        json['number'] ?? json['table_number'] ?? json['tableNumber'],
      ),
      status: status,
      people: _int(
        json['people_count'] ??
            json['peopleCount'] ??
            json['number_of_diners'] ??
            json['numberOfDiners'],
        fallback: 2,
      ),
      amount: _num(json['amount'] ?? json['sett_amount'] ?? json['settAmount']),
      openedAt: _dateTime(
        json['open_time'] ?? json['openTime'] ?? json['order_time'],
      ),
      receivingStatus: _string(
        json['receiving_status'] ??
            json['receivingStatus'] ??
            json['order_receiving'] ??
            json['orderReceiving'],
      ),
      orderNo: _string(json['order_no'] ?? json['orderNo']),
    );
  }
}

class TableOverview {
  const TableOverview({
    required this.tables,
    this.takeoutOrders = const [],
    this.pickupOrders = const [],
  });

  final List<DiningTable> tables;
  final List<FulfillmentOrder> takeoutOrders;
  final List<FulfillmentOrder> pickupOrders;

  int get total => tables.length;
  int get dineInCount => tables.where((table) => table.isOccupied).length;
  int get takeoutCount =>
      takeoutOrders.where((order) => order.status.isActive).length;
  int get pickupCount =>
      pickupOrders.where((order) => order.status.isActive).length;
  int get settled =>
      tables.where((table) => table.status == TableStatus.settled).length;
  int get pending =>
      tables.where((table) => table.status == TableStatus.pending).length;
  int get empty =>
      tables.where((table) => table.status == TableStatus.empty).length;
}

enum TableStatus { empty, settled, pending }

class FulfillmentOrder {
  const FulfillmentOrder({
    required this.id,
    required this.type,
    required this.status,
    required this.pickupCode,
    this.orderNo = '',
    this.tableNumber = '',
    this.amount = 0,
    this.receivingStatus = '',
    this.dispatchStatus = '',
    this.createdAt,
  });

  final int id;
  final FulfillmentType type;
  final FulfillmentStatus status;
  final String pickupCode;
  final String orderNo;
  final String tableNumber;
  final num amount;
  final String receivingStatus;
  final String dispatchStatus;
  final DateTime? createdAt;

  String get displayCode {
    final code = pickupCode.trim();
    if (code.isEmpty) return '';
    if (RegExp(r'^[A-Za-z]').hasMatch(code)) return code;
    return '${type.codePrefix}$code';
  }

  Duration? elapsedDuration(DateTime now) {
    final start = createdAt;
    if (start == null) return null;
    final duration = now.difference(start);
    return duration.isNegative ? Duration.zero : duration;
  }

  factory FulfillmentOrder.fromJson(
    Map<String, Object?> json, {
    required FulfillmentType type,
  }) {
    return FulfillmentOrder(
      id: _int(json['id'] ?? json['order_id'] ?? json['orderId'], fallback: 0),
      type: type,
      status: _fulfillmentStatus(json, type),
      orderNo: _string(json['order_no'] ?? json['orderNo']),
      tableNumber: _string(
        json['table_number'] ?? json['tableNumber'] ?? json['number'],
      ),
      amount:
          _num(
            json['payable_amount'] ??
                json['payableAmount'] ??
                json['sett_amount'] ??
                json['settAmount'] ??
                json['amount'],
          ) ??
          0,
      receivingStatus: _string(
        json['receiving_status'] ??
            json['receivingStatus'] ??
            json['order_receiving'],
      ),
      dispatchStatus: _string(
        json['dispatch_status'] ??
            json['dispatchStatus'] ??
            json['takeout_dispatch_status'] ??
            json['takeoutDispatchStatus'],
      ),
      pickupCode: _string(
        json['pickup_code'] ??
            json['pickupCode'] ??
            json['takeout_code'] ??
            json['takeoutCode'] ??
            json['code'] ??
            json['order_code'] ??
            json['orderCode'] ??
            json['id'],
      ),
      createdAt: _dateTime(
        json['order_time'] ??
            json['orderTime'] ??
            json['created_at'] ??
            json['createdAt'] ??
            json['pay_time'] ??
            json['payTime'],
      ),
    );
  }
}

enum FulfillmentType {
  takeout('B'),
  pickup('A');

  const FulfillmentType(this.codePrefix);

  final String codePrefix;
}

enum FulfillmentStatus {
  pendingPayment,
  waiting,
  delivering,
  completed;

  bool get isActive => this != FulfillmentStatus.completed;
}

class FulfillmentOrderDetail {
  const FulfillmentOrderDetail({
    required this.order,
    required this.lines,
    this.paymentMethod = '',
  });

  final FulfillmentOrder order;
  final List<FulfillmentOrderLine> lines;
  final String paymentMethod;
}

class FulfillmentOrderLine {
  const FulfillmentOrderLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.specification = '',
  });

  final String name;
  final int quantity;
  final num unitPrice;
  final num totalPrice;
  final String specification;

  factory FulfillmentOrderLine.fromJson(Map<String, Object?> json) {
    final quantity = _int(
      json['quantity'] ?? json['number'] ?? json['count'],
      fallback: 0,
    );
    final total =
        _num(json['total_price'] ?? json['totalPrice'] ?? json['subtotal']) ??
        0;
    final unit =
        _num(
          json['unitprice'] ??
              json['unit_price'] ??
              json['unitPrice'] ??
              json['price'],
        ) ??
        (quantity > 0 ? total / quantity : 0);
    return FulfillmentOrderLine(
      name: _string(json['name'] ?? json['dish_name'] ?? json['dishName']),
      quantity: quantity,
      unitPrice: unit,
      totalPrice: total,
      specification: _cleanSpecification(
        _string(
          json['selectedSpicy'] ??
              json['selected_spicy'] ??
              json['specification'] ??
              json['spec'],
        ),
      ),
    );
  }
}

TableStatus _status(Map<String, Object?> json) {
  final raw = _string(
    json['status'] ??
        json['table_status'] ??
        json['tableStatus'] ??
        json['transac_status'] ??
        json['transacStatus'],
  ).toLowerCase();
  final orderNo = _string(json['order_no'] ?? json['orderNo']);

  if (raw.isNotEmpty) {
    return switch (raw) {
      '0' => TableStatus.empty,
      '1' => TableStatus.pending,
      '2' => TableStatus.settled,
      'success' || 'settled' || 'paid' => TableStatus.settled,
      'unsettled' || 'pending' || 'occupied' => TableStatus.pending,
      _ => TableStatus.empty,
    };
  }

  return orderNo.isEmpty ? TableStatus.empty : TableStatus.pending;
}

FulfillmentStatus _fulfillmentStatus(
  Map<String, Object?> json,
  FulfillmentType type,
) {
  final transaction = _string(
    json['transac_status'] ??
        json['transacStatus'] ??
        json['payment_status'] ??
        json['paymentStatus'],
  ).toLowerCase();
  if (transaction == 'unsettled' ||
      transaction == 'pending' ||
      transaction == '0') {
    return FulfillmentStatus.pendingPayment;
  }
  final receiving = _string(
    json['receiving_status'] ??
        json['receivingStatus'] ??
        json['order_receiving'],
  ).toLowerCase();
  final dispatch = _string(
    json['dispatch_status'] ??
        json['dispatchStatus'] ??
        json['takeout_dispatch_status'] ??
        json['takeoutDispatchStatus'],
  ).toLowerCase();
  final zsqDispatch = _string(
    json['zsq_dispatch_status'] ?? json['zsqDispatchStatus'],
  ).toLowerCase();
  final zsqPhase = _string(json['zsq_phase'] ?? json['zsqPhase']).toUpperCase();

  if (receiving == 'off_order' ||
      receiving == '已完成' ||
      dispatch == 'completed' ||
      dispatch == '已完成' ||
      zsqDispatch == 'completed' ||
      zsqPhase == 'DELIVERED') {
    return FulfillmentStatus.completed;
  }

  if (type == FulfillmentType.takeout &&
      (dispatch == 'delivering' ||
          dispatch == '配送中' ||
          zsqPhase == 'TO_SHOP' ||
          zsqPhase == 'TO_USER')) {
    return FulfillmentStatus.delivering;
  }

  return FulfillmentStatus.waiting;
}

String _cleanSpecification(String value) {
  return value
      .split(RegExp(r'[/,，;；]'))
      .map((item) {
        final trimmed = item.trim();
        final separator = trimmed.indexOf(RegExp(r'[:：]'));
        return separator >= 0
            ? trimmed.substring(separator + 1).trim()
            : trimmed;
      })
      .where((item) => item.isNotEmpty)
      .join(' / ');
}

String _string(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

num? _num(Object? value) {
  if (value == null) return null;
  if (value is num) return value;
  return num.tryParse('$value');
}

DateTime? _dateTime(Object? value) {
  final raw = _string(value);
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw) ??
      DateTime.tryParse(raw.replaceFirst(' ', 'T'));
}
