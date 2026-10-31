import 'dart:convert';

enum CashierBillStatus { all, success, unsettled, refunded, cancelled, unknown }

extension CashierBillStatusPresentation on CashierBillStatus {
  String get label => switch (this) {
    CashierBillStatus.all => '全部状态',
    CashierBillStatus.success => '已结账',
    CashierBillStatus.unsettled => '未结账',
    CashierBillStatus.refunded => '已退款',
    CashierBillStatus.cancelled => '已取消',
    CashierBillStatus.unknown => '未知状态',
  };

  String? get apiValue => switch (this) {
    CashierBillStatus.success => 'success',
    CashierBillStatus.unsettled => 'unsettled',
    CashierBillStatus.refunded => 'refunded',
    CashierBillStatus.cancelled => 'cancelled',
    _ => null,
  };
}

enum CashierOrderType { all, dineIn, takeout, pickup }

extension CashierOrderTypePresentation on CashierOrderType {
  String get label => switch (this) {
    CashierOrderType.all => '全部',
    CashierOrderType.dineIn => '堂食',
    CashierOrderType.takeout => '外卖',
    CashierOrderType.pickup => '自提',
  };

  String? get apiValue => switch (this) {
    CashierOrderType.dineIn => '堂食',
    CashierOrderType.takeout => '外卖',
    CashierOrderType.pickup => '打包',
    _ => null,
  };

  bool matches(String typeText) {
    if (this == CashierOrderType.all) return true;
    final normalized = typeText.toLowerCase().trim();
    return switch (this) {
      CashierOrderType.dineIn =>
        normalized == '堂食' ||
        normalized == 'dine_in' ||
        normalized == 'dinein',
      CashierOrderType.takeout =>
        normalized == '外卖' ||
        normalized == 'takeout' ||
        normalized == 'delivery',
      CashierOrderType.pickup =>
        normalized == '打包' ||
        normalized == '自提' ||
        normalized == 'pickup' ||
        normalized == 'pack' ||
        normalized == 'takeaway',
      _ => true,
    };
  }
}

enum CashierDatePreset { today, yesterday, last7Days, custom }

extension CashierDatePresetPresentation on CashierDatePreset {
  String get label => switch (this) {
    CashierDatePreset.today => '今日',
    CashierDatePreset.yesterday => '昨日',
    CashierDatePreset.last7Days => '近7天',
    CashierDatePreset.custom => '自定义',
  };
}

class CashierBillQuery {
  const CashierBillQuery({
    this.status = CashierBillStatus.all,
    this.orderType = CashierOrderType.all,
    this.datePreset = CashierDatePreset.today,
    this.tableNumber = '',
    this.keyword = '',
    this.startTime,
    this.endTime,
    this.cashierId,
    this.pageNum = 1,
    this.pageSize = 10,
  });

  final CashierBillStatus status;
  final CashierOrderType orderType;
  final CashierDatePreset datePreset;
  final String tableNumber;
  final String keyword;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? cashierId;
  final int pageNum;
  final int pageSize;

  bool get usesSearch =>
      tableNumber.trim().isNotEmpty ||
      keyword.trim().isNotEmpty ||
      orderType != CashierOrderType.all ||
      datePreset != CashierDatePreset.today ||
      startTime != null ||
      endTime != null ||
      cashierId != null;

  bool get hasCustomTimeRange => startTime != null && endTime != null;

  String get timeRangeLabel {
    if (startTime == null || endTime == null) {
      return '默认时间 (最近3小时/未结)';
    }
    switch (datePreset) {
      case CashierDatePreset.today:
        return '今日全天';
      case CashierDatePreset.yesterday:
        return '昨日全天';
      case CashierDatePreset.last7Days:
        return '近 7 天';
      case CashierDatePreset.custom:
        final s = startTime!;
        final e = endTime!;
        final sText =
            '${s.year}/${s.month.toString().padLeft(2, '0')}/${s.day.toString().padLeft(2, '0')}';
        final eText =
            '${e.year}/${e.month.toString().padLeft(2, '0')}/${e.day.toString().padLeft(2, '0')}';
        return '$sText 至 $eText';
    }
  }

  bool get hasFilters => status != CashierBillStatus.all || usesSearch || hasCustomTimeRange;

  CashierBillQuery copyWith({
    CashierBillStatus? status,
    CashierOrderType? orderType,
    CashierDatePreset? datePreset,
    String? tableNumber,
    String? keyword,
    Object? startTime = _unset,
    Object? endTime = _unset,
    Object? cashierId = _unset,
    int? pageNum,
    int? pageSize,
  }) {
    return CashierBillQuery(
      status: status ?? this.status,
      orderType: orderType ?? this.orderType,
      datePreset: datePreset ?? this.datePreset,
      tableNumber: tableNumber ?? this.tableNumber,
      keyword: keyword ?? this.keyword,
      startTime: identical(startTime, _unset)
          ? this.startTime
          : startTime as DateTime?,
      endTime: identical(endTime, _unset) ? this.endTime : endTime as DateTime?,
      cashierId: identical(cashierId, _unset)
          ? this.cashierId
          : cashierId as int?,
      pageNum: pageNum ?? this.pageNum,
      pageSize: pageSize ?? this.pageSize,
    );
  }
}

class CashierPaymentChannel {
  const CashierPaymentChannel({
    required this.code,
    required this.label,
    required this.amount,
  });

  final String code;
  final String label;
  final double amount;
}

class CashierBillLine {
  const CashierBillLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.specification,
    required this.unit,
    required this.lineStatus,
    this.kdsItemStatus,
    this.kdsStatusText,
    this.kdsServedQuantity,
  });

  final int id;
  final String name;
  final int quantity;
  final double unitPrice;
  final double totalPrice;
  final String specification;
  final String unit;
  final String lineStatus;
  final int? kdsItemStatus;
  final String? kdsStatusText;
  final int? kdsServedQuantity;

  bool get isRefunded =>
      lineStatus.toLowerCase() == 'refunded' ||
      kdsItemStatus == 3 ||
      kdsStatusText == '已退菜';

  factory CashierBillLine.fromJson(Map<String, Object?> json) {
    final quantity = _int(_first(json, const ['quantity', 'number', 'count']));
    final total = _money(_first(json, const ['total_price', 'totalPrice']));
    final explicitUnitPrice = _money(
      _first(json, const ['unitprice', 'unit_price', 'unitPrice', 'price']),
    );
    final rawStatusText = _first(json, const [
      'kds_status_text',
      'kdsStatusText',
      'kds_status',
      'kdsStatus',
    ]);
    final statusText = rawStatusText == null ? null : _text(rawStatusText);

    return CashierBillLine(
      id: _int(_first(json, const ['id', 'detail_id', 'detailId'])),
      name: _text(_first(json, const ['name', 'dish_name', 'dishName'])),
      quantity: quantity,
      unitPrice: explicitUnitPrice > 0
          ? explicitUnitPrice
          : quantity > 0
          ? total / quantity
          : 0,
      totalPrice: total,
      specification: _specification(
        _first(json, const [
          'selectedSpicy',
          'selected_spicy',
          'specification',
          'spec',
        ]),
      ),
      unit: _text(json['unit']),
      lineStatus: _text(
        _first(json, const ['line_status', 'lineStatus', 'status']),
      ),
      kdsItemStatus: _intOrNull(_first(json, const [
        'kds_item_status',
        'kdsItemStatus',
      ])),
      kdsStatusText: (statusText != null && statusText.isNotEmpty) ? statusText : null,
      kdsServedQuantity: _intOrNull(_first(json, const [
        'kds_served_quantity',
        'kdsServedQuantity',
      ])),
    );
  }
}

class CashierBillSummary {
  const CashierBillSummary({
    this.todayRevenue = 0.0,
    this.orderCount = 0,
    this.avgOrderPrice = 0.0,
    this.totalDiscount = 0.0,
  });

  final double todayRevenue;
  final int orderCount;
  final double avgOrderPrice;
  final double totalDiscount;
}

class CashierBill {
  const CashierBill({
    required this.id,
    required this.orderNo,
    required this.tableNumber,
    required this.orderTime,
    required this.cashierId,
    required this.cashierName,
    this.cashierWorkNo = '',
    required this.status,
    required this.itemQuantity,
    required this.goodsAmount,
    required this.discountAmount,
    required this.serviceFee,
    required this.refundAmount,
    required this.giftAmount,
    required this.payableAmount,
    required this.paidAmount,
    required this.paymentMethod,
    required this.paymentChannels,
    required this.cashTender,
    required this.changeAmount,
    required this.changeChannelLabel,
    required this.lines,
    this.orderType = '堂食',
    this.payTime,
    this.remark = '',
    this.packageFee = 0.0,
    this.deliveryFee = 0.0,
    this.memberName = '',
    this.memberPhone = '',
    this.memberBalance = 0.0,
    this.memberId,
    this.discountPercentText = '',
    this.transactionId = '',
    this.openid = '',
    this.payOpenid = '',
    this.isDailySettled = false,
    this.revision,
    this.numberOfDiners,
  });

  final int id;
  final String orderNo;
  final String tableNumber;
  final DateTime? orderTime;
  final int cashierId;
  final String cashierName;
  final String cashierWorkNo;
  final CashierBillStatus status;
  final int itemQuantity;
  final double goodsAmount;
  final double discountAmount;
  final double serviceFee;
  final double refundAmount;
  final double giftAmount;
  final double payableAmount;
  final double paidAmount;
  final String paymentMethod;
  final List<CashierPaymentChannel> paymentChannels;
  final double cashTender;
  final double changeAmount;
  final String changeChannelLabel;
  final List<CashierBillLine> lines;
  final String orderType;
  final DateTime? payTime;
  final String remark;
  final double packageFee;
  final double deliveryFee;
  final String memberName;
  final String memberPhone;
  final double memberBalance;
  final int? memberId;
  final String discountPercentText;
  final String transactionId;
  final String openid;
  final int? revision;
  final int? numberOfDiners;

  /// 订单是否已退款
  bool get isRefunded => status == CashierBillStatus.refunded;

  /// 订单是否已取消
  bool get isCancelled => status == CashierBillStatus.cancelled;

  /// 订单是否包含现金收款（纯现金或组合支付）——用于人工退款分流（v1.2.211）。
  bool get hasCashChannel =>
      cashTender > 0 ||
      paymentChannels.any(
        (channel) =>
            channel.code.toLowerCase() == 'cash' ||
            channel.label.contains('现金'),
      );
  final String payOpenid;
  final bool isDailySettled;

  bool get canResumeTable =>
      status == CashierBillStatus.unsettled && tableNumber.isNotEmpty;

  CashierBill copyWith({
    int? id,
    String? orderNo,
    String? tableNumber,
    DateTime? orderTime,
    int? cashierId,
    String? cashierName,
    String? cashierWorkNo,
    CashierBillStatus? status,
    int? itemQuantity,
    double? goodsAmount,
    double? discountAmount,
    double? serviceFee,
    double? refundAmount,
    double? giftAmount,
    double? payableAmount,
    double? paidAmount,
    String? paymentMethod,
    List<CashierPaymentChannel>? paymentChannels,
    double? cashTender,
    double? changeAmount,
    String? changeChannelLabel,
    List<CashierBillLine>? lines,
    String? orderType,
    DateTime? payTime,
    String? remark,
    double? packageFee,
    double? deliveryFee,
    String? memberName,
    String? memberPhone,
    double? memberBalance,
    int? memberId,
    String? discountPercentText,
    String? transactionId,
    String? openid,
    String? payOpenid,
    bool? isDailySettled,
    int? revision,
    int? numberOfDiners,
  }) {
    return CashierBill(
      id: id ?? this.id,
      orderNo: orderNo ?? this.orderNo,
      tableNumber: tableNumber ?? this.tableNumber,
      orderTime: orderTime ?? this.orderTime,
      cashierId: cashierId ?? this.cashierId,
      cashierName: cashierName ?? this.cashierName,
      cashierWorkNo: cashierWorkNo ?? this.cashierWorkNo,
      status: status ?? this.status,
      itemQuantity: itemQuantity ?? this.itemQuantity,
      goodsAmount: goodsAmount ?? this.goodsAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      serviceFee: serviceFee ?? this.serviceFee,
      refundAmount: refundAmount ?? this.refundAmount,
      giftAmount: giftAmount ?? this.giftAmount,
      payableAmount: payableAmount ?? this.payableAmount,
      paidAmount: paidAmount ?? this.paidAmount,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentChannels: paymentChannels ?? this.paymentChannels,
      cashTender: cashTender ?? this.cashTender,
      changeAmount: changeAmount ?? this.changeAmount,
      changeChannelLabel: changeChannelLabel ?? this.changeChannelLabel,
      lines: lines ?? this.lines,
      orderType: orderType ?? this.orderType,
      payTime: payTime ?? this.payTime,
      remark: remark ?? this.remark,
      packageFee: packageFee ?? this.packageFee,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      memberName: memberName ?? this.memberName,
      memberPhone: memberPhone ?? this.memberPhone,
      memberBalance: memberBalance ?? this.memberBalance,
      memberId: memberId ?? this.memberId,
      discountPercentText: discountPercentText ?? this.discountPercentText,
      transactionId: transactionId ?? this.transactionId,
      openid: openid ?? this.openid,
      payOpenid: payOpenid ?? this.payOpenid,
      isDailySettled: isDailySettled ?? this.isDailySettled,
      revision: revision ?? this.revision,
      numberOfDiners: numberOfDiners ?? this.numberOfDiners,
    );
  }

  factory CashierBill.fromJson(
    Map<String, Object?> json, {
    List<CashierBillLine>? lines,
  }) {
    final parsedLines =
        lines ?? _lineMaps(json).map(CashierBillLine.fromJson).toList();
    final goods = _money(
      _first(json, const [
        'sett_amount',
        'settAmount',
        'goods_amount',
        'total_amount',
        'original_amount',
        'originalAmount',
      ]),
    );
    final discount = _money(
      _first(json, const ['discount_amount', 'discountAmount']),
    );
    final service = _money(_first(json, const ['service_fee', 'serviceFee']));
    final refund = _money(
      _first(json, const ['refund_amount', 'refundAmount']),
    );
    final gift = _money(
      _first(json, const ['pay_amount_gift', 'payAmountGift']),
    );
    final pkgFee = _money(
      _first(json, const [
        'package_fee',
        'packageFee',
        'packing_fee',
        'packingFee',
        'box_fee',
        'boxFee',
      ]),
    );
    final delFee = _money(
      _first(json, const [
        'delivery_fee',
        'deliveryFee',
        'shipping_fee',
        'shippingFee',
      ]),
    );
    final payable = goods - discount + service + pkgFee + delFee - refund - gift;
    final paymentMethod = _firstNonEmptyText(json, const [
      'payment_channel_code',
      'paymentChannelCode',
      'payment_method',
      'paymentMethod',
      'pay_method',
      'payment_channel_type',
      'paymentChannelType',
    ]);
    final channels = _paymentChannels(json);
    final status = _status(
      _first(json, const [
        'transac_status',
        'transacStatus',
        'pay_status',
        'status',
      ]),
      refundAmount: refund,
    );
    final double normalizedPayable = payable < 0 ? 0.0 : payable;
    if (channels.isEmpty &&
        status == CashierBillStatus.success &&
        normalizedPayable > 0) {
      final definition = _paymentDefinition(paymentMethod);
      if (definition != null) {
        channels.add(
          CashierPaymentChannel(
            code: definition.$1,
            label: definition.$2,
            amount: normalizedPayable,
          ),
        );
      }
    }
    final explicitPaid = _money(
      _first(json, const ['paid_amount', 'paidAmount', 'actual_amount']),
    );
    final explicitCount = _int(
      _first(json, const [
        'goods_count',
        'goodsCount',
        'item_count',
        'itemCount',
        'dish_count',
      ]),
    );
    final cashier = json['cashier'] is Map
        ? (json['cashier'] as Map).cast<String, Object?>()
        : const <String, Object?>{};

    final user = json['user'] is Map
        ? (json['user'] as Map).cast<String, Object?>()
        : (json['member'] is Map
            ? (json['member'] as Map).cast<String, Object?>()
            : const <String, Object?>{});

    final rawOrderType = _text(
      _first(json, const [
        'dineInOrTakeOut',
        'dine_in_or_take_out',
        'order_type',
        'orderType',
        'type',
      ]),
    );
    final orderType = switch (rawOrderType.toLowerCase()) {
      'takeout' || '外卖' || 'delivery' => '外卖',
      'pickup' || '自提' => '自提',
      '打包' || 'pack' || 'takeaway' => '打包',
      'dine_in' || 'dinein' || '堂食' => '堂食',
      _ => rawOrderType.isNotEmpty ? rawOrderType : '堂食',
    };

    final orderTimeVal = _dateTime(
      _first(json, const [
        'order_time',
        'orderTime',
        'created_at',
        'createdAt',
      ]),
    );

    final payTimeVal = _dateTime(
      _first(json, const [
        'pay_time',
        'payTime',
        'sett_time',
        'settTime',
        'updated_at',
        'updatedAt',
      ]),
    );

    final remarkText = _text(
      _first(json, const ['remark', 'note', 'memo', 'order_remark', 'orderRemark']),
    );

    final memberNameText = _firstNonEmptyText(json, const [
      'member_name',
      'memberName',
      'user_name',
      'userName',
      'nickname',
    ]).isNotEmpty
        ? _firstNonEmptyText(json, const [
            'member_name',
            'memberName',
            'user_name',
            'userName',
            'nickname',
          ])
        : _text(user['name'] ?? user['nickname']);

    final memberPhoneText = _firstNonEmptyText(json, const [
      'member_phone',
      'memberPhone',
      'phone',
      'telephone',
      'user_phone',
    ]).isNotEmpty
        ? _firstNonEmptyText(json, const [
            'member_phone',
            'memberPhone',
            'phone',
            'telephone',
            'user_phone',
          ])
        : _text(user['phone']);

    final memberBalanceVal = _money(
      _first(json, const [
        'member_balance',
        'memberBalance',
        'user_balance',
        'balance',
      ]) ??
          user['balance'],
    );

    final memberIdVal = _int(
      _first(json, const ['user_id', 'userId', 'member_id', 'memberId']) ??
          user['id'],
    );

    String discountText = '';
    if (discount > 0 && goods > 0) {
      final ratio = ((goods - discount) / goods * 10).toStringAsFixed(1);
      final cleanRatio = ratio.endsWith('.0') ? ratio.substring(0, ratio.length - 2) : ratio;
      discountText = '${cleanRatio}折';
    }

    final transactionIdText = _firstNonEmptyText(json, const [
      'transaction_id',
      'transactionId',
      'wx_transaction_id',
      'payment_transaction_id',
    ]);

    final openidText = _firstNonEmptyText(json, const [
      'openid',
      'user_openid',
      'userOpenid',
      'openId',
    ]);

    final payOpenidText = _firstNonEmptyText(json, const [
      'pay_openid',
      'payOpenid',
    ]);

    return CashierBill(
      id: _int(json['id']),
      orderNo: _text(_first(json, const ['order_no', 'orderNo'])),
      tableNumber: _text(_first(json, const ['table_number', 'tableNumber'])),
      orderTime: orderTimeVal,
      cashierId: _int(
        _first(json, const [
              'cashier_id',
              'cashierId',
              'admin_id',
              'adminId',
            ]) ??
            cashier['id'],
      ),
      cashierName: _text(
        _first(json, const [
              'cashier_display_name',
              'cashierDisplayName',
              'display_name',
              'displayName',
              'real_name',
              'realName',
              'operator_name',
              'operatorName',
              'cashier_name',
              'cashierName',
              'admin_name',
              'adminName',
            ]) ??
            cashier['displayName'] ??
            cashier['realName'] ??
            cashier['name'],
      ),
      cashierWorkNo: _text(
        _first(json, const [
              'cashier_work_no',
              'cashierWorkNo',
              'work_no',
              'workNo',
            ]) ??
            cashier['workNo'] ??
            cashier['work_no'],
      ),
      status: status,
      itemQuantity: explicitCount > 0
          ? explicitCount
          : parsedLines.fold(0, (sum, line) => sum + line.quantity),
      goodsAmount: goods,
      discountAmount: discount,
      serviceFee: service,
      refundAmount: refund,
      giftAmount: gift,
      payableAmount: normalizedPayable,
      paidAmount: explicitPaid > 0
          ? explicitPaid
          : status == CashierBillStatus.success
          ? normalizedPayable
          : channels.fold<double>(0.0, (sum, item) => sum + item.amount),
      paymentMethod: paymentMethod,
      paymentChannels: List.unmodifiable(channels),
      cashTender: _money(
        _first(json, const [
          'checkout_cash_tender',
          'checkoutCashTender',
          'cashTender',
        ]),
      ),
      changeAmount: _money(
        _first(json, const [
          'checkout_change_amount',
          'checkoutChangeAmount',
          'changeAmount',
        ]),
      ),
      changeChannelLabel: _text(
        _first(json, const [
          'checkout_change_channel_label',
          'checkoutChangeChannelLabel',
          'checkout_change_channel',
          'changeChannel',
        ]),
      ),
      lines: List.unmodifiable(parsedLines),
      orderType: orderType,
      payTime: payTimeVal ?? (status == CashierBillStatus.success ? orderTimeVal : null),
      remark: remarkText,
      packageFee: pkgFee,
      deliveryFee: delFee,
      memberName: memberNameText,
      memberPhone: memberPhoneText,
      memberBalance: memberBalanceVal,
      memberId: memberIdVal > 0 ? memberIdVal : null,
      discountPercentText: discountText,
      transactionId: transactionIdText,
      openid: openidText,
      payOpenid: payOpenidText,
      isDailySettled: json['is_daily_settled'] == true ||
          json['isDailySettled'] == true ||
          json['daily_settled'] == true ||
          json['dailySettled'] == true ||
          json['is_settled_day'] == true ||
          (json['daily_stat_id'] != null && _int(json['daily_stat_id']) > 0),
      revision: _intOrNull(
        _first(json, const [
          'revision',
          'order_revision',
          'orderRevision',
          'version',
        ]),
      ),
      numberOfDiners: _intOrNull(
        _first(json, const [
          'number_of_diners',
          'numberOfDiners',
          'diners',
          'people',
        ]),
      ),
    );
  }
}

List<CashierPaymentChannel> _paymentChannels(Map<String, Object?> json) {
  final splitValue = _first(json, const [
    'payment_split',
    'paymentSplit',
    'split',
    'pay_split',
  ]);
  final split = splitValue is Map
      ? splitValue.cast<Object?, Object?>()
      : const <Object?, Object?>{};

  final methodText = _firstNonEmptyText(json, const [
    'payment_channel_code',
    'paymentChannelCode',
    'payment_method',
    'paymentMethod',
    'pay_method',
  ]);

  final isWechatQr = methodText.contains('微信收款码') ||
      methodText.toLowerCase().contains('offline_wechat_qr') ||
      methodText.toLowerCase().contains('wechat_qr');
  final isAlipayQr = methodText.contains('支付宝收款码') ||
      methodText.toLowerCase().contains('offline_alipay_qr') ||
      methodText.toLowerCase().contains('alipay_qr');

  final wechatLabel = isWechatQr ? '微信收款码' : '微信支付';
  final alipayLabel = isAlipayQr ? '支付宝收款码' : '支付宝';

  final channels = <CashierPaymentChannel>[];
  for (final definition in [
    (
      isWechatQr ? 'offline_wechat_qr' : 'wechat',
      wechatLabel,
      const ['offline_wechat_qr', 'wechat', 'pay_amount_wechat', 'payAmountWechat'],
    ),
    (
      isAlipayQr ? 'offline_alipay_qr' : 'alipay',
      alipayLabel,
      const ['offline_alipay_qr', 'alipay', 'pay_amount_alipay', 'payAmountAlipay'],
    ),
    (
      'balance',
      '余额支付',
      const ['balance', 'online_balance', 'pay_amount_balance', 'payAmountBalance'],
    ),
    ('cash', '现金', const ['cash', 'pay_amount_cash', 'payAmountCash']),
    (
      'gift',
      '赠送金',
      const ['gift', 'balance_gift', 'pay_amount_gift', 'payAmountGift'],
    ),
  ]) {
    Object? raw;
    for (final key in definition.$3) {
      if (split.containsKey(key)) {
        raw = split[key];
        break;
      }
    }
    raw ??= _first(json, definition.$3);
    final amount = _money(raw);
    if (amount > 0) {
      channels.add(
        CashierPaymentChannel(
          code: definition.$1,
          label: definition.$2,
          amount: amount,
        ),
      );
    }
  }
  return channels;
}

(String, String)? _paymentDefinition(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final clean = trimmed.toLowerCase().replaceAll(RegExp(r'[\s-_]+'), '');

  if (clean.contains('微信收款码') || clean == 'offlinewechatqr' || clean == 'wechatqr') {
    return ('offline_wechat_qr', '微信收款码');
  }
  if (clean.contains('支付宝收款码') || clean == 'offlinealipayqr' || clean == 'alipayqr') {
    return ('offline_alipay_qr', '支付宝收款码');
  }
  if (clean == 'wechat' ||
      clean == 'weixin' ||
      clean == 'wx' ||
      clean == 'onlinewechat' ||
      clean == '微信' ||
      clean == '微信支付') {
    return ('wechat', '微信支付');
  }
  if (clean == 'alipay' ||
      clean == 'ali' ||
      clean == 'onlinealipay' ||
      clean == '支付宝' ||
      clean == '支付宝支付') {
    return ('alipay', '支付宝');
  }
  if (clean == 'balance' ||
      clean == 'onlinebalance' ||
      clean == 'memberbalance' ||
      clean == '余额' ||
      clean == '余额支付' ||
      clean == '会员余额') {
    return ('balance', '余额支付');
  }
  if (clean == 'cash' || clean == 'offlinecash' || clean == '现金' || clean == '现金支付') {
    return ('cash', '现金');
  }
  if (clean == 'combined' || clean == 'onlinecombined' || clean == '组合支付') {
    return ('combined', '组合支付');
  }
  return (trimmed, trimmed);
}

Object? _first(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null) return value;
  }
  return null;
}

String _firstNonEmptyText(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _text(json[key]);
    if (value.isNotEmpty) return value;
  }
  return '';
}

List<Map<String, Object?>> _lineMaps(Map<String, Object?> json) {
  for (final key in const [
    'lines',
    'list',
    'items',
    'details',
    'orderDetailList',
  ]) {
    final value = json[key];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => item.cast<String, Object?>())
          .toList();
    }
  }
  return const [];
}

CashierBillStatus _status(Object? value, {num? refundAmount}) {
  final hasRefund = refundAmount != null && refundAmount > 0;
  if (value is num) {
    return switch (value.toInt()) {
      0 => CashierBillStatus.unsettled,
      1 => CashierBillStatus.success,
      2 => hasRefund ? CashierBillStatus.refunded : CashierBillStatus.cancelled,
      3 => CashierBillStatus.refunded,
      _ => CashierBillStatus.unknown,
    };
  }
  final textVal = _text(value).toLowerCase();
  if (textVal == 'refunded' || textVal == '已退款' || textVal == 'refund') {
    return CashierBillStatus.refunded;
  }
  return switch (textVal) {
    'success' || 'paid' || '已结账' => CashierBillStatus.success,
    'unsettled' || 'pending' || '未结账' => CashierBillStatus.unsettled,
    'cancelled' || 'canceled' || '已取消' =>
      hasRefund ? CashierBillStatus.refunded : CashierBillStatus.cancelled,
    _ => hasRefund ? CashierBillStatus.refunded : CashierBillStatus.unknown,
  };
}

DateTime? _dateTime(Object? value) {
  if (value is num) {
    final raw = value.toInt();
    return DateTime.fromMillisecondsSinceEpoch(
      raw.abs() < 100000000000 ? raw * 1000 : raw,
    );
  }
  final text = _text(value);
  if (text.isEmpty) return null;
  return DateTime.tryParse(text.replaceFirst(' ', 'T'));
}

String _specification(Object? value) {
  final text = _text(value);
  if (text.isEmpty) return '';
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map) {
      return decoded.entries
          .map((entry) => '${entry.key}：${_specValue(entry.value)}')
          .join('、');
    }
  } catch (_) {
    // Some historical orders store the display text directly.
  }
  return text;
}

String _specValue(Object? value) => value is List ? value.join('/') : '$value';
String _text(Object? value) => value == null ? '' : '$value'.trim();
int _int(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value)) ?? 0;
int? _intOrNull(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value));
double _money(Object? value) => value is num
    ? value.toDouble()
    : double.tryParse(_text(value).replaceAll(',', '')) ?? 0;

const Object _unset = Object();

class CashierInvoiceResult {
  const CashierInvoiceResult({
    required this.orderNo,
    required this.invoiceStatus,
    required this.invoiceQrUrl,
    required this.invoiceAmount,
    this.taxRate = 0.06,
    this.expireMinutes = 1440,
    this.notice = '',
  });

  final String orderNo;
  final String invoiceStatus;
  final String invoiceQrUrl;
  final double invoiceAmount;
  final double taxRate;
  final int expireMinutes;
  final String notice;

  factory CashierInvoiceResult.fromJson(Map<String, Object?> json) {
    return CashierInvoiceResult(
      orderNo: json['orderNo']?.toString() ?? '',
      invoiceStatus: json['invoiceStatus']?.toString() ?? 'PENDING_SCAN',
      invoiceQrUrl: json['invoiceQrUrl']?.toString() ?? '',
      invoiceAmount: (json['invoiceAmount'] as num?)?.toDouble() ?? 0.0,
      taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0.06,
      expireMinutes: (json['expireMinutes'] as num?)?.toInt() ?? 1440,
      notice: json['notice']?.toString() ?? '',
    );
  }
}


class CashierInvoiceDetails {
  const CashierInvoiceDetails({
    required this.orderNo,
    required this.hasInvoice,
    required this.invoiceStatus,
    required this.invoiceAmount,
    this.fapiaoApplyId = '',
    this.taxRate = 0.06,
    this.titleType = 'PERSONAL',
    this.buyerTitle = '',
    this.buyerTaxNo = '',
    this.buyerPhone = '',
    this.buyerEmail = '',
    this.invoiceNo = '',
    this.invoiceCode = '',
    this.downloadUrl = '',
    this.invoiceQrUrl = '',
    this.failReason = '',
    this.createdAt,
  });

  final String orderNo;
  final bool hasInvoice;
  final String invoiceStatus;
  final double invoiceAmount;
  final String fapiaoApplyId;
  final double taxRate;
  final String titleType;
  final String buyerTitle;
  final String buyerTaxNo;
  final String buyerPhone;
  final String buyerEmail;
  final String invoiceNo;
  final String invoiceCode;
  final String downloadUrl;
  final String invoiceQrUrl;
  final String failReason;
  final DateTime? createdAt;

  bool get isPendingScan => invoiceStatus.toUpperCase() == 'PENDING_SCAN';
  bool get isSubmitted =>
      invoiceStatus.toUpperCase() == 'TITLE_SUBMITTED' ||
      invoiceStatus.toUpperCase() == 'SUBMITTED';
  bool get isIssuing => invoiceStatus.toUpperCase() == 'ISSUING';
  bool get isSuccess =>
      invoiceStatus.toUpperCase() == 'SUCCESS' ||
      invoiceStatus.toUpperCase() == 'ISSUED';
  bool get isFailed => invoiceStatus.toUpperCase() == 'FAILED';
  bool get isReversed => invoiceStatus.toUpperCase() == 'REVERSED';
  bool get isNone => invoiceStatus.toUpperCase() == 'NONE' || !hasInvoice;

  String get statusLabel => switch (invoiceStatus.toUpperCase()) {
    'PENDING_SCAN' => '待顾客扫码',
    'TITLE_SUBMITTED' || 'SUBMITTED' => '抬头已提交',
    'ISSUING' => '开票中',
    'SUCCESS' || 'ISSUED' => '已开具',
    'FAILED' => '开票失败',
    'REVERSED' => '已冲红',
    _ => hasInvoice ? invoiceStatus : '未开票',
  };

  factory CashierInvoiceDetails.fromJson(Map<String, Object?> json) {
    final rawStatus = json['invoiceStatus']?.toString() ??
        json['invoice_status']?.toString() ??
        'NONE';
    final hasInv = json['hasInvoice'] == true ||
        (rawStatus != 'NONE' && rawStatus.isNotEmpty);

    DateTime? parsedCreatedAt;
    final rawCreated = json['createdAt'] ?? json['created_at'];
    if (rawCreated is int) {
      parsedCreatedAt = DateTime.fromMillisecondsSinceEpoch(rawCreated);
    } else if (rawCreated is String && rawCreated.isNotEmpty) {
      parsedCreatedAt = DateTime.tryParse(rawCreated);
    }

    return CashierInvoiceDetails(
      orderNo: json['orderNo']?.toString() ??
          json['order_no']?.toString() ??
          '',
      hasInvoice: hasInv,
      invoiceStatus: rawStatus,
      invoiceAmount: (json['invoiceAmount'] as num?)?.toDouble() ??
          (json['invoice_amount'] as num?)?.toDouble() ??
          0.0,
      fapiaoApplyId: json['fapiaoApplyId']?.toString() ??
          json['fapiao_apply_id']?.toString() ??
          '',
      taxRate: (json['taxRate'] as num?)?.toDouble() ??
          (json['tax_rate'] as num?)?.toDouble() ??
          0.06,
      titleType: json['titleType']?.toString() ??
          json['title_type']?.toString() ??
          'PERSONAL',
      buyerTitle: json['buyerTitle']?.toString() ??
          json['buyer_title']?.toString() ??
          '',
      buyerTaxNo: json['buyerTaxNo']?.toString() ??
          json['buyer_tax_no']?.toString() ??
          '',
      buyerPhone: json['buyerPhone']?.toString() ??
          json['buyer_phone']?.toString() ??
          '',
      buyerEmail: json['buyerEmail']?.toString() ??
          json['buyer_email']?.toString() ??
          '',
      invoiceNo: json['invoiceNo']?.toString() ??
          json['fapiaoNumber']?.toString() ??
          json['fapiao_number']?.toString() ??
          '',
      invoiceCode: json['invoiceCode']?.toString() ??
          json['fapiaoCode']?.toString() ??
          json['fapiao_code']?.toString() ??
          '',
      downloadUrl: json['downloadUrl']?.toString() ??
          json['fapiaoFileUrl']?.toString() ??
          json['fapiao_file_url']?.toString() ??
          '',
      invoiceQrUrl: json['invoiceQrUrl']?.toString() ??
          json['invoice_qr_url']?.toString() ??
          '',
      failReason: json['failReason']?.toString() ??
          json['fail_reason']?.toString() ??
          json['errorMsg']?.toString() ??
          json['error_msg']?.toString() ??
          '',
      createdAt: parsedCreatedAt,
    );
  }
}

class CashierAuditEvent {
  const CashierAuditEvent({
    required this.time,
    required this.action,
    required this.description,
    required this.operator,
  });

  final String time;
  final String action;
  final String description;
  final String operator;

  factory CashierAuditEvent.fromJson(Map<String, Object?> json) {
    return CashierAuditEvent(
      time: json['time']?.toString() ?? '',
      action: json['action']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      operator: json['operator']?.toString() ?? '',
    );
  }
}

class CashierAuditTimeline {
  const CashierAuditTimeline({
    required this.orderNo,
    required this.events,
  });

  final String orderNo;
  final List<CashierAuditEvent> events;

  factory CashierAuditTimeline.fromJson(Map<String, Object?> json) {
    final rawEvents = json['events'];
    final list = <CashierAuditEvent>[];
    if (rawEvents is Iterable) {
      for (final e in rawEvents) {
        if (e is Map) {
          list.add(CashierAuditEvent.fromJson(e.cast<String, Object?>()));
        }
      }
    }
    return CashierAuditTimeline(
      orderNo: json['orderNo']?.toString() ?? '',
      events: List.unmodifiable(list),
    );
  }
}
