class AdminOrder {
  const AdminOrder({
    required this.id,
    required this.orderNo,
    required this.tableNumber,
    required this.totalAmount,
    required this.kdsOrderStatus,
    required this.receivingStatus,
    required this.checkoutCashTender,
    required this.checkoutChangeAmount,
    required this.checkoutChangeChannelLabel,
    required this.lines,
    this.goodsAmount = 0,
    this.discountAmount = 0,
    this.serviceFee = 0,
    this.refundAmount = 0,
    this.giftPayAmount = 0,
    this.deliveryFee = 0,
    this.createdAt = '',
    this.payTime = '',
    this.payStatus = '',
    this.orderType = '',
    this.orderNumber = 0,
    this.paymentMethod = '',
    this.remark = '',
    this.openid = '',
    this.payOpenid = '',
    this.transactionId = '',
    this.takeoutDeliveryId = 0,
    this.takeoutDispatchStatus = '',
    this.user,
    this.revision,
  });

  final int id;
  final String orderNo;
  final String tableNumber;
  final double totalAmount;
  final double goodsAmount;
  final double discountAmount;
  final double serviceFee;
  final double refundAmount;
  final double giftPayAmount;
  final double deliveryFee;
  final String kdsOrderStatus;
  final String receivingStatus;
  final double checkoutCashTender;
  final double checkoutChangeAmount;
  final String checkoutChangeChannelLabel;
  final List<OrderLine> lines;
  final String createdAt;
  final String payTime;
  final String payStatus;
  final String orderType;
  final int orderNumber;
  final String paymentMethod;
  final String remark;
  final String openid;
  final String payOpenid;
  final String transactionId;
  final int takeoutDeliveryId;
  final String takeoutDispatchStatus;
  final OrderUserBrief? user;
  final int? revision;

  double get paidAmount =>
      goodsAmount - discountAmount + serviceFee - refundAmount - giftPayAmount;

  bool get isPaid => payStatus == 'success';
  bool get isUnsettled => payStatus == 'unsettled';
  bool get isTakeout => orderType == '外卖' || takeoutDeliveryId > 0;
  bool get isPacked => orderType == '打包' || orderType == '自提';
  bool get needsPickupCodeHighlight => isTakeout || isPacked;
  bool get canWechatRefund => isPaid && transactionId.isNotEmpty;

  factory AdminOrder.fromJson(Map<String, Object?> json) {
    final goods = _double(
      json['sett_amount'] ??
          json['settAmount'] ??
          json['total_amount'] ??
          json['totalAmount'] ??
          json['pay_amount'],
    );
    final discount = _double(json['discount_amount'] ?? json['discountAmount']);
    final serviceFee = _double(json['service_fee'] ?? json['serviceFee']);
    final refund = _double(json['refund_amount'] ?? json['refundAmount']);
    final gift = _double(json['pay_amount_gift'] ?? json['payAmountGift']);
    return AdminOrder(
      id: _int(json['id']),
      orderNo: _string(json['order_no'] ?? json['orderNo']),
      tableNumber: _string(json['table_number'] ?? json['tableNumber']),
      totalAmount: goods - discount + serviceFee - refund - gift,
      goodsAmount: goods,
      discountAmount: discount,
      serviceFee: serviceFee,
      refundAmount: refund,
      giftPayAmount: gift,
      deliveryFee: _double(json['delivery_fee'] ?? json['deliveryFee']),
      kdsOrderStatus: _string(
        json['kds_order_status'] ?? json['kdsOrderStatus'],
      ),
      receivingStatus: _string(
        json['receiving_status'] ??
            json['receivingStatus'] ??
            json['order_receiving'],
      ),
      checkoutCashTender: _double(
        json['checkout_cash_tender'] ??
            json['checkoutCashTender'] ??
            json['cashTender'],
      ),
      checkoutChangeAmount: _double(
        json['checkout_change_amount'] ??
            json['checkoutChangeAmount'] ??
            json['changeAmount'],
      ),
      checkoutChangeChannelLabel: _string(
        json['checkout_change_channel_label'] ??
            json['checkoutChangeChannelLabel'] ??
            json['changeChannel'],
      ),
      lines: _list(
        json['lines'] ?? json['items'] ?? json['details'],
      ).map((item) => OrderLine.fromJson(item)).toList(growable: false),
      createdAt: _string(
        json['created_at'] ??
            json['createdAt'] ??
            json['order_time'] ??
            json['orderTime'],
      ),
      payTime: _string(json['pay_time'] ?? json['payTime']),
      payStatus: _string(
        json['pay_status'] ?? json['payStatus'] ?? json['transac_status'],
      ),
      orderType: _string(
        json['order_type'] ?? json['orderType'] ?? json['dineInOrTakeOut'],
      ),
      orderNumber: _int(json['orderNumber'] ?? json['order_number']),
      paymentMethod: _string(
        json['payment_method'] ?? json['paymentMethod'] ?? json['pay_method'],
      ),
      remark: _string(json['remark'] ?? json['note']),
      openid: _string(json['openid']),
      payOpenid: _string(json['pay_openid'] ?? json['payOpenid']),
      transactionId: _string(json['transaction_id'] ?? json['transactionId']),
      takeoutDeliveryId: _int(
        json['takeout_delivery_id'] ?? json['takeoutDeliveryId'],
      ),
      takeoutDispatchStatus: _string(
        json['takeout_dispatch_status'] ?? json['takeoutDispatchStatus'],
      ),
      user: json['user'] is Map
          ? OrderUserBrief.fromJson(
              (json['user'] as Map).cast<String, Object?>(),
            )
          : null,
      revision: _nullableInt(
        json['revision'] ?? json['order_revision'] ?? json['orderRevision'],
      ),
    );
  }

  AdminOrder copyWith({
    String? receivingStatus,
    List<OrderLine>? lines,
    OrderUserBrief? user,
    int? revision,
  }) {
    return AdminOrder(
      id: id,
      orderNo: orderNo,
      tableNumber: tableNumber,
      totalAmount: totalAmount,
      goodsAmount: goodsAmount,
      discountAmount: discountAmount,
      serviceFee: serviceFee,
      refundAmount: refundAmount,
      giftPayAmount: giftPayAmount,
      deliveryFee: deliveryFee,
      kdsOrderStatus: kdsOrderStatus,
      receivingStatus: receivingStatus ?? this.receivingStatus,
      checkoutCashTender: checkoutCashTender,
      checkoutChangeAmount: checkoutChangeAmount,
      checkoutChangeChannelLabel: checkoutChangeChannelLabel,
      lines: lines ?? this.lines,
      createdAt: createdAt,
      payTime: payTime,
      payStatus: payStatus,
      orderType: orderType,
      orderNumber: orderNumber,
      paymentMethod: paymentMethod,
      remark: remark,
      openid: openid,
      payOpenid: payOpenid,
      transactionId: transactionId,
      takeoutDeliveryId: takeoutDeliveryId,
      takeoutDispatchStatus: takeoutDispatchStatus,
      user: user ?? this.user,
      revision: revision ?? this.revision,
    );
  }
}

class OrderUserBrief {
  const OrderUserBrief({
    required this.openid,
    this.nickname = '',
    this.phone = '',
    this.balance = 0,
    this.principalBalance = 0,
    this.giftBalance = 0,
    this.points = 0,
    this.consumeAmount = 0,
  });

  final String openid;
  final String nickname;
  final String phone;
  final double balance;
  final double principalBalance;
  final double giftBalance;
  final int points;
  final double consumeAmount;

  factory OrderUserBrief.fromJson(Map<String, Object?> json) {
    return OrderUserBrief(
      openid: _string(json['openid']),
      nickname: _string(json['nickname'] ?? json['name']),
      phone: _string(json['phone']),
      balance: _double(json['balance']),
      principalBalance: _double(json['principal_balance']),
      giftBalance: _double(json['gift_balance']),
      points: _int(json['points']),
      consumeAmount: _double(json['consume_amount'] ?? json['consumeAmount']),
    );
  }
}

class OrderLine {
  const OrderLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.lineStatus,
    this.orderRound = 0,
    this.unit = '',
    this.specification = '',
    this.totalPrice = 0,
    this.receivingStatus = '',
  });

  final int id;
  final String name;
  final int quantity;
  final String lineStatus;
  final int orderRound;
  final String unit;
  final String specification;
  final double totalPrice;
  final String receivingStatus;

  bool get refundable => lineStatus.isEmpty || lineStatus == 'normal';

  factory OrderLine.fromJson(Map<String, Object?> json) {
    return OrderLine(
      id: _int(json['id'] ?? json['detail_id'] ?? json['detailId']),
      name: _string(json['name'] ?? json['dish_name'] ?? json['dishName']),
      quantity: _int(json['quantity'] ?? json['number'] ?? json['count']),
      lineStatus: _string(
        json['line_status'] ?? json['lineStatus'] ?? json['status'],
      ),
      orderRound: _int(json['morder_num'] ?? json['Morder_num']),
      unit: _string(json['unit']),
      specification: _string(
        json['selectedSpicy'] ??
            json['selected_spicy'] ??
            json['specification'] ??
            json['spec'],
      ),
      totalPrice: _double(json['total_price'] ?? json['totalPrice']),
      receivingStatus: _string(json['order_rece'] ?? json['orderRece']),
    );
  }

  OrderLine copyWith({String? lineStatus, int? quantity}) {
    return OrderLine(
      id: id,
      name: name,
      quantity: quantity ?? this.quantity,
      lineStatus: lineStatus ?? this.lineStatus,
      orderRound: orderRound,
      unit: unit,
      specification: specification,
      totalPrice: totalPrice,
      receivingStatus: receivingStatus,
    );
  }
}

class PagedOrders {
  const PagedOrders({
    required this.orders,
    required this.total,
    required this.todayCount,
  });

  final List<AdminOrder> orders;
  final int total;
  final int todayCount;
}

String refundLineStatus(OrderLine line) {
  return line.refundable ? 'refunded' : line.lineStatus;
}

String _string(Object? value) => value == null ? '' : '$value';

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double _double(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

List<Map<String, Object?>> _list(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => item.cast<String, Object?>())
        .toList(growable: false);
  }
  return const [];
}
