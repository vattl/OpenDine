import 'dart:convert';

class DiningTable {
  const DiningTable({
    this.id = 0,
    required this.number,
    required this.status,
    required this.people,
    this.amount,
    this.openedAt,
    this.receivingStatus = '',
    this.areaCode = '',
    this.areaName = '',
    this.qrcode = '',
  });

  final int id;
  final String number;
  final TableStatus status;
  final int people;
  final num? amount;
  final DateTime? openedAt;
  final String receivingStatus;
  final String areaCode;
  final String areaName;
  final String qrcode;

  DiningTable copyWith({
    int? id,
    String? number,
    TableStatus? status,
    int? people,
    num? amount,
    DateTime? openedAt,
    String? receivingStatus,
    String? areaCode,
    String? areaName,
    String? qrcode,
  }) {
    return DiningTable(
      id: id ?? this.id,
      number: number ?? this.number,
      status: status ?? this.status,
      people: people ?? this.people,
      amount: amount ?? this.amount,
      openedAt: openedAt ?? this.openedAt,
      receivingStatus: receivingStatus ?? this.receivingStatus,
      areaCode: areaCode ?? this.areaCode,
      areaName: areaName ?? this.areaName,
      qrcode: qrcode ?? this.qrcode,
    );
  }

  bool get isOccupied => status != TableStatus.empty;
  bool get canClearAfterCheckout =>
      status == TableStatus.settled && amount != null && amount == 0;

  /// 计算归属区域代码（优先后端返回的 areaCode，缺省时按桌号前缀 A=hall, B=box, C=patio 推断）
  String get effectiveAreaCode {
    if (areaCode.isNotEmpty) return areaCode;
    final numUpper = number.toUpperCase();
    if (numUpper.startsWith('B') || numUpper.contains('包厢')) return 'box';
    if (numUpper.startsWith('C') || numUpper.contains('露天') || numUpper.contains('外摆')) return 'patio';
    return 'hall';
  }

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
      areaCode: _string(json['area_code'] ?? json['areaCode']),
      areaName: _string(json['area_name'] ?? json['areaName']),
      qrcode: _string(json['qrcode'] ?? json['qr_code'] ?? json['qrCode']),
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
    this.shopId,
    this.orderNo = '',
    this.tableNumber = '',
    this.amount = 0,
    this.receivingStatus = '',
    this.kdsOrderStatus = '',
    this.dispatchStatus = '',
    this.createdAt,
    this.remark = '',
  });

  final int id;
  final FulfillmentType type;
  final FulfillmentStatus status;
  final String pickupCode;
  final int? shopId;
  final String orderNo;
  final String tableNumber;
  final num amount;
  final String receivingStatus;
  final String kdsOrderStatus;
  final String dispatchStatus;
  final DateTime? createdAt;
  final String remark;

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
      shopId: _nullableInt(
        json['shop_id'] ?? json['shopId'] ?? json['store_id'] ?? json['storeId'],
      ),
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
      kdsOrderStatus: _string(
        json['kds_order_status'] ??
            json['kdsOrderStatus'] ??
            json['make_status'] ??
            json['makeStatus'] ??
            json['cook_status'] ??
            json['cookStatus'] ??
            json['kitchen_status'] ??
            json['kitchenStatus'] ??
            json['production_status'] ??
            json['productionStatus'],
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
      remark: _string(
        json['remark'] ??
            json['note'] ??
            json['memo'] ??
            json['order_remark'] ??
            json['orderRemark'] ??
            json['user_remark'] ??
            json['userRemark'],
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
    this.remark = '',
  });

  final FulfillmentOrder order;
  final List<FulfillmentOrderLine> lines;
  final String paymentMethod;
  final String remark;

  String get effectiveRemark =>
      remark.trim().isNotEmpty ? remark.trim() : order.remark.trim();
}

class FulfillmentOrderLine {
  const FulfillmentOrderLine({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.specification = '',
    this.productionStatus = '',
    this.kdsStatusText = '',
    this.kdsItemStatus = '',
    this.kdsServedQuantity,
  });

  final String name;
  final int quantity;
  final num unitPrice;
  final num totalPrice;
  final String specification;
  final String productionStatus;

  /// 服务端 KDS 制作状态中文文案（v1.2.224 `kds_status_text`）。
  final String kdsStatusText;

  /// 服务端 KDS 制作状态码（v1.2.224 `kds_item_status`）：0待制作/1制作中/2已完成/3已退菜。
  final String kdsItemStatus;

  /// 已传菜数量（v1.2.224 `kds_served_quantity`）。
  final int? kdsServedQuantity;

  bool get isRefunded =>
      kdsItemStatus == '3' ||
      kdsStatusText == '已退菜' ||
      productionStatus == '3' ||
      productionStatus == 'refunded' ||
      productionStatus == 'cancelled' ||
      productionStatus == '已退菜';

  bool get isPartiallyServed =>
      !isRefunded &&
      kdsServedQuantity != null &&
      kdsServedQuantity! > 0 &&
      quantity > 0 &&
      kdsServedQuantity! < quantity;

  bool get isServed =>
      !isRefunded &&
      (productionStatusLabel == '已出餐' ||
          (quantity > 0 &&
              kdsServedQuantity != null &&
              kdsServedQuantity! >= quantity));

  bool get isInProgress =>
      !isRefunded &&
      (productionStatusLabel == '制作中' || isPartiallyServed);

  bool get isPending =>
      !isRefunded && productionStatusLabel == '待制作';

  String get productionStatusLabel {
    if (isRefunded) {
      return '已退菜';
    }
    if (kdsServedQuantity != null && kdsServedQuantity! > 0) {
      if (quantity > 0 && kdsServedQuantity! >= quantity) {
        return '已出餐';
      }
      return '已出$kdsServedQuantity/$quantity';
    }
    return switch (productionStatus) {
      '2' || 'done' || 'completed' || 'served' || 'ready' ||
              'off_order' || '已出餐' || '已完成' =>
        '已出餐',
      '1' || 'cooking' || 'in_progress' || 'making' || 'preparing' || '制作中' || '烹饪中' =>
        '制作中',
      '0' || 'pending' || 'wait' || 'rec_order' || 'accepted' || '待制作' =>
        '待制作',
      '' || 'mis_order' || 'not_started' || 'unstarted' || '未制作' =>
        '未制作',
      '3' || 'refunded' || 'cancelled' || 'canceled' || 'voided' || '已退菜' || '已取消' =>
        '已退菜',
      _ => '—',
    };
  }

  FulfillmentOrderLine copyWith({
    String? name,
    int? quantity,
    num? unitPrice,
    num? totalPrice,
    String? specification,
    String? productionStatus,
    String? kdsStatusText,
    String? kdsItemStatus,
    int? kdsServedQuantity,
  }) => FulfillmentOrderLine(
    name: name ?? this.name,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    totalPrice: totalPrice ?? this.totalPrice,
    specification: specification ?? this.specification,
    productionStatus: productionStatus ?? this.productionStatus,
    kdsStatusText: kdsStatusText ?? this.kdsStatusText,
    kdsItemStatus: kdsItemStatus ?? this.kdsItemStatus,
    kdsServedQuantity: kdsServedQuantity ?? this.kdsServedQuantity,
  );

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
    final kdsStatusText = _string(
      json['kds_status_text'] ?? json['kdsStatusText'],
    ).trim();
    final kdsItemStatus = _string(
      json['kds_item_status'] ?? json['kdsItemStatus'],
    ).trim();
    final kdsServedQuantity = _nullableInt(
      json['kds_served_quantity'] ?? json['kdsServedQuantity'],
    );
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
      productionStatus: _string(
        kdsStatusText.isNotEmpty
            ? kdsStatusText
            : kdsItemStatus.isNotEmpty
                ? kdsItemStatus
                : _detailProductionStatus(json),
      ).trim().toLowerCase(),
      kdsStatusText: kdsStatusText,
      kdsItemStatus: kdsItemStatus,
      kdsServedQuantity: kdsServedQuantity,
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
  final source = value.trim();
  if (source.isEmpty) return '';
  // 外卖/履约明细接口 selectedSpicy 为 JSON 字符串（如 {"辣度":"微辣"}），
  // 直接按文本提取会残留引号/大括号等标点，先尝试结构化解析。
  if (source.startsWith('{') || source.startsWith('[')) {
    try {
      final decoded = jsonDecode(source);
      return _specValues(decoded).join(' / ');
    } catch (_) {
      // 非标准 JSON，降级到键值对提取
    }
  }
  return value
      .split(RegExp(r'[/,，;；]'))
      .map((item) {
        final trimmed = item.trim();
        final separator = trimmed.indexOf(RegExp(r'[:：]'));
        return separator >= 0
            ? _cleanSpecToken(trimmed.substring(separator + 1))
            : _cleanSpecToken(trimmed);
      })
      .where((item) => item.isNotEmpty)
      .join(' / ');
}

String _cleanSpecToken(String raw) => raw
    .replaceAll('"', '')
    .replaceAll("'", '')
    .replaceAll('[', '')
    .replaceAll(']', '')
    .replaceAll('{', '')
    .replaceAll('}', '')
    .trim();

List<String> _specValues(Object? decoded) {
  if (decoded is Map) {
    // 结构化对象优先取名称类字段，避免把价格等数字混入规格。
    for (final key in const ['name', 'label', 'value', 'text', '名称']) {
      final v = decoded[key];
      if (v != null && v is! Map && v is! List) {
        final s = _cleanSpecToken('$v');
        if (s.isNotEmpty) return [s];
      }
    }
    final out = <String>[];
    for (final v in decoded.values) {
      if (v is Map || v is List) {
        out.addAll(_specValues(v));
      } else if (v != null) {
        final s = _cleanSpecToken('$v');
        if (s.isNotEmpty && num.tryParse(s) == null) out.add(s);
      }
    }
    return out;
  }
  if (decoded is List) {
    final out = <String>[];
    for (final v in decoded) {
      out.addAll(_specValues(v));
    }
    return out;
  }
  if (decoded != null) {
    final s = _cleanSpecToken('$decoded');
    return s.isEmpty ? const [] : [s];
  }
  return const [];
}

/// 订单明细（OrderDetail）没有 KDS 字段时的制作状态推导：
/// `line_status` 仅是退菜软删标记（normal/refunded），不能作为制作状态，
/// 否则 normal 会遮蔽接单状态导致出品状态恒为空（—）。
/// 制作状态以接单状态 `order_rece` 为准：rec_order→待制作、mis_order→未制作、
/// off_order→已出餐、cancelled→已退菜。
String _detailProductionStatus(Map<String, Object?> json) {
  final lineStatus = _string(
    json['line_status'] ?? json['lineStatus'],
  ).toLowerCase();
  if (lineStatus == 'refunded') return 'refunded';
  return _string(
    json['order_rece'] ??
        json['orderReceiving'] ??
        json['order_receiving'] ??
        json['receiving_status'] ??
        json['receivingStatus'],
  );
}

String _string(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value, {required int fallback}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_string(value));
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
