import 'dart:convert';

import '../../tables/domain/dining_table.dart';

class PosCategory {
  const PosCategory({
    required this.id,
    required this.name,
    required this.code,
    required this.sorting,
  });

  final int id;
  final String name;
  final String code;
  final int sorting;

  factory PosCategory.fromJson(Map<String, Object?> json) {
    return PosCategory(
      id: _int(json['id']),
      name: _string(json['label'] ?? json['value'] ?? json['name']),
      code: _string(json['cid'] ?? json['value'] ?? json['id']),
      sorting: _int(json['sorting']),
    );
  }
}

class PosDish {
  const PosDish({
    required this.id,
    required this.name,
    required this.categoryId,
    this.categoryCode = '',
    required this.price,
    required this.unit,
    required this.stock,
    required this.onSale,
    required this.soldOut,
    required this.specGroups,
  });

  final int id;
  final String name;
  final int categoryId;
  final String categoryCode;
  final double price;
  final String unit;
  final int? stock;
  final bool onSale;
  final bool soldOut;
  final List<PosSpecGroup> specGroups;

  bool get available => onSale && !soldOut;

  String get stockLabel {
    if (!onSale || soldOut) return '已售罄';
    final value = stock;
    if (value == null || value <= 0) return '不限量';
    return '剩余：$value';
  }

  factory PosDish.fromJson(Map<String, Object?> json) {
    final type = json['type'] is Map
        ? (json['type'] as Map).cast<String, Object?>()
        : json['category'] is Map
        ? (json['category'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return PosDish(
      id: _int(json['id'] ?? json['dish_id'] ?? json['dishId']),
      name: _string(json['name'] ?? json['dish_name'] ?? json['dishName']),
      categoryId: _int(
        json['typeId'] ??
            json['type_id'] ??
            json['category_id'] ??
            json['categoryId'] ??
            type['id'] ??
            json['cid'],
      ),
      categoryCode: _string(
        json['cid'] ??
            json['category_code'] ??
            json['categoryCode'] ??
            type['cid'] ??
            type['value'],
      ),
      price: _double(json['unitprice'] ?? json['unit_price'] ?? json['price']),
      unit: _string(json['unit']).isEmpty ? '份' : _string(json['unit']),
      stock: _nullableInt(json['stock']),
      onSale: _bool(json['onsale'], fallback: true),
      soldOut: _bool(json['sold_out'] ?? json['soldOut']),
      specGroups: _specGroups(json['specification'] ?? json['spec']),
    );
  }

  String get requestCategoryCode =>
      categoryCode.isNotEmpty ? categoryCode : categoryId.toString();

  PosDish withCategoryCode(String value) => PosDish(
    id: id,
    name: name,
    categoryId: categoryId,
    categoryCode: value,
    price: price,
    unit: unit,
    stock: stock,
    onSale: onSale,
    soldOut: soldOut,
    specGroups: specGroups,
  );
}

class PosSpecGroup {
  const PosSpecGroup({required this.label, required this.options});

  final String label;
  final List<String> options;
}

class PosCartLine {
  const PosCartLine({
    required this.dish,
    required this.selections,
    required this.quantity,
  });

  final PosDish dish;
  final Map<String, String> selections;
  final int quantity;

  double get total => dish.price * quantity;
  String get specification => selections.values.join('、');
  String get key => '${dish.id}|${jsonEncode(selections)}';

  PosCartLine copyWith({int? quantity}) {
    return PosCartLine(
      dish: dish,
      selections: selections,
      quantity: quantity ?? this.quantity,
    );
  }

  Map<String, Object?> requestBody({String? clientLineId}) {
    return {
      // The unified cashier contract validates normal menu lines by dish_id.
      // Keep mId for older deployments during the compatibility window.
      'dish_id': dish.id,
      'mId': dish.id,
      'name': dish.name,
      'cid': dish.requestCategoryCode,
      'quantity': '$quantity',
      'unit': dish.unit,
      'total_price': total,
      'selectedSpicy': selections.isEmpty ? '' : jsonEncode(selections),
      if (clientLineId?.trim().isNotEmpty == true)
        'client_line_id': clientLineId!.trim(),
    };
  }
}

class PosCart {
  const PosCart({this.lines = const []});

  final List<PosCartLine> lines;

  double get total => lines.fold(0, (sum, line) => sum + line.total);
  double get packagingFee => total <= 0 ? 0 : (total / 100).ceilToDouble();
  double get totalWithPackaging => total + packagingFee;
  int get itemCount => lines.fold(0, (sum, line) => sum + line.quantity);

  int quantityForDish(int dishId) => lines
      .where((line) => line.dish.id == dishId)
      .fold(0, (sum, line) => sum + line.quantity);

  int? remainingStock(PosDish dish) {
    final stock = dish.stock;
    if (stock == null || stock <= 0) return null;
    final remaining = stock - quantityForDish(dish.id);
    return remaining > 0 ? remaining : 0;
  }

  PosCart add(
    PosDish dish, {
    Map<String, String> selections = const {},
    int quantity = 1,
  }) {
    if (!dish.available) return this;
    final normalized = <String, String>{
      for (final group in dish.specGroups)
        if ((selections[group.label] ?? '').isNotEmpty)
          group.label: selections[group.label]!,
    };
    final availableStock = remainingStock(dish);
    if (availableStock == 0) return this;
    final requestedQuantity = quantity.clamp(1, 99);
    final quantityToAdd = availableStock == null
        ? requestedQuantity
        : requestedQuantity.clamp(1, availableStock);
    final candidate = PosCartLine(
      dish: dish,
      selections: normalized,
      quantity: quantityToAdd,
    );
    final index = lines.indexWhere((line) => line.key == candidate.key);
    if (index < 0) return PosCart(lines: [...lines, candidate]);
    return PosCart(
      lines: [
        for (var i = 0; i < lines.length; i++)
          i == index
              ? lines[i].copyWith(
                  quantity: (lines[i].quantity + candidate.quantity).clamp(
                    1,
                    99,
                  ),
                )
              : lines[i],
      ],
    );
  }

  PosCart updateQuantity(String key, int quantity) {
    if (quantity <= 0) return remove(key);
    final index = lines.indexWhere((line) => line.key == key);
    if (index < 0) return this;
    final line = lines[index];
    var nextQuantity = quantity;
    final stock = line.dish.stock;
    if (stock != null && stock > 0) {
      final quantityOnOtherLines =
          quantityForDish(line.dish.id) - line.quantity;
      final maximumForLine = stock - quantityOnOtherLines;
      if (maximumForLine <= 0) return remove(key);
      if (nextQuantity > maximumForLine) nextQuantity = maximumForLine;
    }
    return PosCart(
      lines: [
        for (var i = 0; i < lines.length; i++)
          i == index ? lines[i].copyWith(quantity: nextQuantity) : lines[i],
      ],
    );
  }

  PosCart remove(String key) {
    return PosCart(
      lines: lines.where((line) => line.key != key).toList(growable: false),
    );
  }
}

enum PosRefundStockAction {
  restore('RESTORE', '回退库存', '退菜增加门店可售库存；售罄商品加回后若 stock > 0 自动恢复在售'),
  noRestore('NO_RESTORE', '计入损耗', '菜品已做/顾客口感问题等，不加回库存，记录退菜流水'),
  outOfStock('OUT_OF_STOCK', '缺货估清', '后厨食材用尽，退菜不加库存，并将该菜品库存清零并强制全店售罄');

  const PosRefundStockAction(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

class PosOrderLine {
  const PosOrderLine({
    required this.id,
    required this.name,
    required this.quantity,
    required this.total,
    required this.specification,
    required this.refunded,
  });

  final int id;
  final String name;
  final int quantity;
  final double total;
  final String specification;
  final bool refunded;

  double get unitPrice => quantity <= 0 ? total : total / quantity;

  factory PosOrderLine.fromJson(Map<String, Object?> json) {
    final selections = _selectionLabel(
      json['selectedSpicy'] ?? json['selected_spicy'] ?? json['specification'],
    );
    final status = _string(
      json['line_status'] ?? json['lineStatus'] ?? json['order_rece'],
    ).toLowerCase();
    return PosOrderLine(
      id: _int(json['id'] ?? json['detail_id'] ?? json['detailId']),
      name: _string(json['name'] ?? json['dish_name'] ?? json['dishName']),
      quantity: _int(json['quantity'] ?? json['number'] ?? json['count']),
      total: _double(json['total_price'] ?? json['totalPrice']),
      specification: selections,
      refunded: status == 'refunded',
    );
  }
}

class PosOrder {
  const PosOrder({
    required this.id,
    required this.orderNo,
    required this.tableNumber,
    required this.diners,
    required this.total,
    required this.createdAt,
    required this.lines,
    this.memberPhone = '',
    this.memberOpenid = '',
    this.memberBalance,
    this.grossAmount = 0,
    this.discountAmount = 0,
    this.wipeZeroAmount = 0,
    this.receivingStatus = '',
    this.kdsOrderStatus = '',
  });

  final int id;
  final String orderNo;
  final String tableNumber;
  final int diners;
  final double total;
  final double grossAmount;
  final double discountAmount;
  final double wipeZeroAmount;
  final String memberPhone;
  final String memberOpenid;
  final double? memberBalance;
  final DateTime? createdAt;
  final List<PosOrderLine> lines;
  final String receivingStatus;
  final String kdsOrderStatus;

  bool get hasRegisteredMember => memberPhone.trim().isNotEmpty;
  bool get canUseStoredValue =>
      hasRegisteredMember &&
      memberOpenid.trim().isNotEmpty &&
      memberBalance != null;

  factory PosOrder.fromJson(Map<String, Object?> json) {
    final goods = _mapList(
      json['goods_list'] ?? json['lines'] ?? json['items'] ?? json['details'],
    );
    final amount = _double(
      json['sett_amount'] ?? json['settAmount'] ?? json['total_amount'],
    );
    final discount = _double(json['discount_amount'] ?? json['discountAmount']);
    final service = _double(json['service_fee'] ?? json['serviceFee']);
    final refund = _double(json['refund_amount'] ?? json['refundAmount']);
    final wipeZero = _double(
      json['wipe_zero_amount'] ?? json['wipeZeroAmount'] ?? json['wipe_amount'],
    );
    final gross = amount + service - refund;
    return PosOrder(
      id: _int(json['id'] ?? json['order_id'] ?? json['orderId']),
      orderNo: _string(json['order_no'] ?? json['orderNo']),
      tableNumber: _string(json['table_number'] ?? json['tableNumber']),
      diners: _int(
        json['number_of_diners'] ??
            json['numberOfDiners'] ??
            json['people_count'],
        fallback: 1,
      ),
      total: gross - discount - wipeZero,
      grossAmount: gross,
      discountAmount: discount,
      wipeZeroAmount: wipeZero,
      memberPhone: _string(json['member_phone'] ?? json['memberPhone']),
      memberOpenid: _string(
        json['member_openid'] ??
            json['memberOpenid'] ??
            json['openid'] ??
            json['openId'] ??
            json['pay_openid'] ??
            json['payOpenid'],
      ),
      memberBalance: _nullableDouble(
        json['member_balance'] ?? json['memberBalance'],
      ),
      createdAt: _dateTime(
        json['order_time'] ?? json['orderTime'] ?? json['created_at'],
      ),
      lines: goods.map(PosOrderLine.fromJson).toList(growable: false),
      receivingStatus: _string(
        json['receiving_status'] ??
            json['receivingStatus'] ??
            json['order_receiving'] ??
            json['orderReceiving'],
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
    );
  }

  PosOrder copyWith({
    List<PosOrderLine>? lines,
    String? receivingStatus,
    String? kdsOrderStatus,
  }) {
    return PosOrder(
      id: id,
      orderNo: orderNo,
      tableNumber: tableNumber,
      diners: diners,
      total: total,
      grossAmount: grossAmount,
      discountAmount: discountAmount,
      wipeZeroAmount: wipeZeroAmount,
      memberPhone: memberPhone,
      memberOpenid: memberOpenid,
      memberBalance: memberBalance,
      createdAt: createdAt,
      lines: lines ?? this.lines,
      receivingStatus: receivingStatus ?? this.receivingStatus,
      kdsOrderStatus: kdsOrderStatus ?? this.kdsOrderStatus,
    );
  }
}

class PosWorkspace {
  const PosWorkspace({
    required this.table,
    required this.categories,
    required this.dishes,
    required this.currentOrder,
    this.paymentMethods = const [],
    this.paymentConfigurationAvailable = true,
  });

  final DiningTable table;
  final List<PosCategory> categories;
  final List<PosDish> dishes;
  final PosOrder? currentOrder;
  final List<PosPaymentMethod> paymentMethods;
  final bool paymentConfigurationAvailable;
}

class PosOfflineCollectionQr {
  const PosOfflineCollectionQr({
    required this.shopId,
    required this.channel,
    required this.qrImageBase64,
    required this.jumpUrl,
    required this.expiresInSeconds,
  });

  final int shopId;
  final String channel;
  final String qrImageBase64;
  final String jumpUrl;
  final int expiresInSeconds;

  factory PosOfflineCollectionQr.fromJson(Map<String, Object?> json) {
    return PosOfflineCollectionQr(
      shopId: _int(json['shopId'] ?? json['shop_id']),
      channel: _string(json['channel']),
      qrImageBase64: _string(json['qrImageBase64'] ?? json['qr_image_base64']),
      jumpUrl: _string(json['jumpUrl'] ?? json['jump_url']),
      expiresInSeconds: _int(
        json['expiresInSeconds'] ?? json['expires_in_seconds'],
        fallback: 180,
      ),
    );
  }
}

class PosPrintResult {
  const PosPrintResult({
    required this.content,
    required this.printSuccess,
    required this.orderNo,
  });

  final String content;
  final bool printSuccess;
  final String orderNo;

  factory PosPrintResult.fromJson(Map<String, Object?> json) {
    return PosPrintResult(
      content: _string(json['content']),
      printSuccess: _bool(json['printSuccess'] ?? json['print_success']),
      orderNo: _string(json['order_no'] ?? json['orderNo']),
    );
  }
}

class PosPaymentMethod {
  const PosPaymentMethod({
    required this.id,
    required this.code,
    required this.name,
    required this.sortOrder,
    required this.enabled,
  });

  final int id;
  final String code;
  final String name;
  final int sortOrder;
  final bool enabled;
  PosPaymentChannelKind? get kind => PosPaymentChannelKind.normalize(code);

  factory PosPaymentMethod.fromJson(Map<String, Object?> json) =>
      PosPaymentMethod(
        id: _int(json['id']),
        code: _string(json['code']),
        name: _string(json['name']),
        sortOrder: _int(json['sort_order'] ?? json['sortOrder']),
        enabled: _bool(json['enabled']),
      );
}

enum PosPaymentChannelKind {
  cash('cash'),
  wechat('offline_wechat_qr'),
  alipay('offline_alipay_qr'),
  balance('online_balance'),
  combined('online_combined');

  const PosPaymentChannelKind(this.canonicalCode);

  final String canonicalCode;

  static PosPaymentChannelKind? normalize(Object? value) {
    final compact = _string(value)
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s._-]+'), '')
        .replaceAll('clients', '')
        .replaceAll('channels', '')
        .replaceAll('effective', '')
        .replaceAll('enabled', '');
    return switch (compact) {
      'cash' ||
      'offlinecash' ||
      'cashpayment' ||
      'cashiercash' ||
      '现金' ||
      '现金支付' => PosPaymentChannelKind.cash,
      'offlinewechatqr' ||
      'offlinewechat' ||
      'onlinewechat' ||
      'wechat' ||
      'wechatpay' ||
      'wechatqr' ||
      'wxpay' ||
      'weixin' ||
      'wx' ||
      'cashierwechat' ||
      'offlinecollectwechat' ||
      'miniprogramwechat' ||
      '微信' ||
      '微信支付' ||
      '微信码' ||
      '微信收款码' => PosPaymentChannelKind.wechat,
      'offlinealipayqr' ||
      'offlinealipay' ||
      'onlinealipay' ||
      'alipay' ||
      'alipaypay' ||
      'alipayqr' ||
      'ali' ||
      'cashieralipay' ||
      'offlinecollectalipay' ||
      '支付宝' ||
      '支付宝支付' ||
      '支付宝码' ||
      '支付宝收款码' => PosPaymentChannelKind.alipay,
      'onlinebalance' ||
      'balance' ||
      'balancepay' ||
      'memberbalance' ||
      'storedvalue' ||
      'cashierbalance' ||
      'miniprogrambalance' ||
      '余额' ||
      '余额支付' ||
      '储值支付' => PosPaymentChannelKind.balance,
      'onlinecombined' ||
      'combined' ||
      'combination' ||
      'combinedpay' ||
      'mixed' ||
      'mixedpayment' ||
      'partialcash' ||
      'cashiercombined' ||
      '组合支付' ||
      '混合支付' => PosPaymentChannelKind.combined,
      _ => null,
    };
  }
}

enum PosChangeChannel {
  wechat('wechat', '微信'),
  cash('cash', '现金'),
  alipay('alipay', '支付宝');

  const PosChangeChannel(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

class PosCashSettlement {
  const PosCashSettlement({
    required this.cashReceivedMinor,
    required this.cashTenderMinor,
    required this.changeAmountMinor,
    this.changeChannel,
  });

  factory PosCashSettlement.fromMinorUnits({
    required int cashReceivedMinor,
    required int cashTenderMinor,
    PosChangeChannel? changeChannel,
  }) {
    final change = (cashTenderMinor - cashReceivedMinor).clamp(0, 1 << 62);
    return PosCashSettlement(
      cashReceivedMinor: cashReceivedMinor,
      cashTenderMinor: cashTenderMinor,
      changeAmountMinor: change,
      changeChannel: change == 0 ? null : changeChannel,
    );
  }

  final int cashReceivedMinor;
  final int cashTenderMinor;
  final int changeAmountMinor;
  final PosChangeChannel? changeChannel;

  double get cashReceived => cashReceivedMinor / 100;
  double get cashTender => cashTenderMinor / 100;
  double get changeAmount => changeAmountMinor / 100;
}

class PosCheckoutSettlement {
  const PosCheckoutSettlement({
    this.wechatMinor = 0,
    this.alipayMinor = 0,
    this.balanceMinor = 0,
    this.cashMinor = 0,
    this.cashTenderMinor = 0,
    this.changeAmountMinor = 0,
    this.changeChannel,
  });

  final int wechatMinor;
  final int alipayMinor;
  final int balanceMinor;
  final int cashMinor;
  final int cashTenderMinor;
  final int changeAmountMinor;
  final PosChangeChannel? changeChannel;

  int get positiveChannelCount => [
    wechatMinor,
    alipayMinor,
    balanceMinor,
    cashMinor,
  ].where((amount) => amount > 0).length;

  bool isBalanced(int totalMinor) {
    final amounts = [wechatMinor, alipayMinor, balanceMinor, cashMinor];
    return totalMinor >= 0 &&
        amounts.every((amount) => amount >= 0) &&
        amounts.fold<int>(0, (sum, amount) => sum + amount) == totalMinor;
  }
}

class PosSubmittedOrderDetail {
  const PosSubmittedOrderDetail({
    required this.detailId,
    required this.dishId,
    required this.name,
    required this.quantity,
    required this.remainingQuantity,
    required this.unit,
    required this.clientLineId,
    required this.raw,
  });

  final int detailId;
  final int dishId;
  final String name;
  final int quantity;
  final int remainingQuantity;
  final String unit;
  final String clientLineId;
  final Map<String, Object?> raw;

  factory PosSubmittedOrderDetail.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : const <String, Object?>{};
    final quantity = _int(map['quantity']);
    return PosSubmittedOrderDetail(
      detailId: _int(map['detail_id'] ?? map['id']),
      dishId: _int(map['dish_id'] ?? map['dishId']),
      name: _string(map['name'] ?? map['dish_name']),
      quantity: quantity,
      remainingQuantity: _int(
        map['remaining_quantity'],
        fallback: quantity - _int(map['refunded_quantity']),
      ),
      unit: _string(map['unit']),
      clientLineId: _string(map['client_line_id']),
      raw: Map.unmodifiable(map),
    );
  }

  Map<String, Object?> toLocalLine() => {
    ...raw,
    'detail_id': detailId,
    if (dishId > 0) 'dish_id': dishId,
    if (name.isNotEmpty) 'name': name,
    'quantity': remainingQuantity,
    if (unit.isNotEmpty) 'unit': unit,
    if (clientLineId.isNotEmpty) 'client_line_id': clientLineId,
  };
}

class PosSubmissionResult {
  const PosSubmissionResult({
    required this.id,
    required this.orderNo,
    this.accepted = true,
    this.fulfillmentStatus = 'ready',
    this.cloudAcceptanceStatus = '',
    this.orderDetails = const [],
  });

  final int id;
  final String orderNo;
  final bool accepted;
  final String fulfillmentStatus;
  final String cloudAcceptanceStatus;
  final List<PosSubmittedOrderDetail> orderDetails;

  bool get isReadyForLocalKds =>
      id > 0 &&
      orderNo.trim().isNotEmpty &&
      accepted &&
      fulfillmentStatus == 'ready';

  bool get hasFormalOrderDetails =>
      orderDetails.isNotEmpty &&
      orderDetails.every((detail) => detail.detailId > 0);

  factory PosSubmissionResult.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : const <String, Object?>{};
    return PosSubmissionResult(
      id: _int(map['id'] ?? map['order_id'] ?? map['orderId']),
      orderNo: _string(map['order_no'] ?? map['orderNo']),
      accepted: _bool(map['accepted']),
      fulfillmentStatus: _string(
        map['fulfillment_status'] ?? map['fulfillmentStatus'],
      ),
      cloudAcceptanceStatus: _string(
        map['cloud_acceptance_status'] ?? map['cloudAcceptanceStatus'],
      ),
      orderDetails: _mapList(
        map['order_details'] ?? map['orderDetails'],
      ).map(PosSubmittedOrderDetail.fromJson).toList(growable: false),
    );
  }

  factory PosSubmissionResult.fromKdsRebuildJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : const <String, Object?>{};
    final order = map['order'] is Map
        ? (map['order'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return PosSubmissionResult(
      id: _int(order['id'] ?? order['order_id'] ?? map['order_id']),
      orderNo: _string(
        order['order_no'] ?? order['orderNo'] ?? map['order_no'],
      ),
      accepted: true,
      fulfillmentStatus: 'ready',
      cloudAcceptanceStatus: _string(
        order['cloud_acceptance_status'] ?? order['order_receiving'],
      ),
      orderDetails: _mapList(
        map['lines'] ?? map['order_details'],
      ).map(PosSubmittedOrderDetail.fromJson).toList(growable: false),
    );
  }
}

List<PosSpecGroup> _specGroups(Object? raw) {
  final source = _string(raw);
  if (source.isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map) {
      return decoded.entries
          .where(
            (entry) => entry.value is List && (entry.value as List).isNotEmpty,
          )
          .map(
            (entry) => PosSpecGroup(
              label: '${entry.key}',
              options: (entry.value as List)
                  .map((value) => '$value'.trim())
                  .where((value) => value.isNotEmpty)
                  .toList(growable: false),
            ),
          )
          .toList(growable: false);
    }
    if (decoded is List) {
      final options = decoded
          .map((value) {
            if (value is Map) return _string(value['name'] ?? value['label']);
            return '$value'.trim();
          })
          .where((value) => value.isNotEmpty)
          .toList(growable: false);
      return options.isEmpty
          ? const []
          : [PosSpecGroup(label: '规格', options: options)];
    }
  } catch (_) {
    final options = source
        .split(RegExp(r'[,，/]'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    return options.isEmpty
        ? const []
        : [PosSpecGroup(label: '规格', options: options)];
  }
  return const [];
}

String _selectionLabel(Object? raw) {
  final source = _string(raw);
  if (source.isEmpty) return '';
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map) return decoded.values.join('、');
  } catch (_) {}
  return source;
}

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}

String _string(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? fallback;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
}

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse('$value');
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final source = '$value'.toLowerCase();
  if (source == 'true' || source == '1') return true;
  if (source == 'false' || source == '0') return false;
  return fallback;
}

DateTime? _dateTime(Object? value) {
  final source = _string(value);
  if (source.isEmpty) return null;
  return DateTime.tryParse(source) ??
      DateTime.tryParse(source.replaceFirst(' ', 'T'));
}

/// 挂单池项（GET /cashier/order/hang-list）。
class HangOrder {
  const HangOrder({
    required this.orderNo,
    this.tableNumber = '',
    this.diners = 0,
    this.settAmount = 0,
    this.hangTime = '',
    this.hangMinutes = 0,
    this.hangReason = '',
    this.hangAdminId,
  });

  final String orderNo;
  final String tableNumber;
  final int diners;
  final double settAmount;
  final String hangTime;
  final int hangMinutes;
  final String hangReason;
  final int? hangAdminId;

  factory HangOrder.fromJson(Map<String, Object?> json) => HangOrder(
    orderNo: _string(json['order_no'] ?? json['orderNo']),
    tableNumber: _string(json['table_number'] ?? json['tableNumber']),
    diners: _int(json['diners']),
    settAmount: _double(json['sett_amount'] ?? json['settAmount']),
    hangTime: _string(json['hang_time'] ?? json['hangTime']),
    hangMinutes: _int(json['hang_minutes'] ?? json['hangMinutes']),
    hangReason: _string(json['hang_reason'] ?? json['hangReason']),
    hangAdminId: _nullableInt(json['hang_admin_id'] ?? json['hangAdminId']),
  );
}

/// 挂单池结果（GET /cashier/order/hang-list）。
class HangListResult {
  const HangListResult({required this.orders, required this.total});

  final List<HangOrder> orders;
  final int total;

  factory HangListResult.fromJson(Object? value) {
    final map = value is Map
        ? value.cast<String, Object?>()
        : const <String, Object?>{};
    final raw = map['list'] is List ? map['list'] as List : const [];
    return HangListResult(
      orders: raw
          .whereType<Map>()
          .map((e) => HangOrder.fromJson(e.cast<String, Object?>()))
          .toList(growable: false),
      total: _int(map['total']),
    );
  }
}

/// 整桌结账结果（POST /cashier/table/checkout）。
class TableCheckoutResult {
  const TableCheckoutResult({
    required this.tableNumber,
    this.settledOrders = 0,
    this.totalAmount = 0,
    this.cashAmount = 0,
    this.changeAmount = 0,
  });

  final String tableNumber;
  final int settledOrders;
  final double totalAmount;
  final double cashAmount;
  final double changeAmount;

  factory TableCheckoutResult.fromJson(Map<String, Object?> json) {
    final rawOrders = json['settledOrders'] is List
        ? json['settledOrders'] as List
        : (json['settled_orders'] is List ? json['settled_orders'] as List : const []);
    return TableCheckoutResult(
      tableNumber: _string(json['tableNumber'] ?? json['table_number']),
      settledOrders: _int(
        json['settledOrderCount'] ?? json['settled_order_count'],
        fallback: rawOrders.length,
      ),
      totalAmount: _double(json['totalAmount'] ?? json['total_amount']),
      cashAmount: _double(json['cashAmount'] ?? json['cash_amount']),
      changeAmount: _double(json['changeAmount'] ?? json['change_amount']),
    );
  }
}

/// 桌台状态图（GET /cashier/table/statusMap）：桌号 -> 状态值。
class TableStatusMap {
  const TableStatusMap({required this.map});

  final Map<String, Object?> map;

  factory TableStatusMap.fromJson(Map<String, Object?> json) {
    final raw = json['map'] is Map
        ? (json['map'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return TableStatusMap(map: raw);
  }
}
