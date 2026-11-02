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
    this.comboDefinition,
    this.servingDurationMinutes = 10,
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
  final PosComboDefinition? comboDefinition;
  final int servingDurationMinutes;

  bool get isCombo => comboDefinition?.enabled == true;

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
      comboDefinition: PosComboDefinition.fromJsonOrNull(
        json['comboDefinition'] ?? json['combo_definition'],
      ),
      servingDurationMinutes:
          _nullableInt(
            json['serving_duration_minutes'] ?? json['servingDurationMinutes'],
          ) ??
          10,
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
    comboDefinition: comboDefinition,
    servingDurationMinutes: servingDurationMinutes,
  );
}

class PosSpecGroup {
  const PosSpecGroup({required this.label, required this.options});

  final String label;
  final List<String> options;
}

class PosComboDefinition {
  const PosComboDefinition({
    required this.comboId,
    required this.dishId,
    required this.comboType,
    required this.status,
    required this.fixedItems,
    required this.groups,
    this.limitPerOrder,
    this.limitPerUser,
    this.limitCycle = 'daily',
    this.startTime,
    this.endTime,
    this.availableDays,
    this.timeRangeStart,
    this.timeRangeEnd,
    this.applyDiningType = 'all',
    this.allowCoupon = true,
    this.dailyStock,
  });

  final int comboId;
  final int dishId;
  final String comboType;
  final int status;
  final List<PosComboFixedItem> fixedItems;
  final List<PosComboGroup> groups;
  final int? limitPerOrder;
  final int? limitPerUser;
  final String limitCycle;
  final String? startTime;
  final String? endTime;
  final String? availableDays;
  final String? timeRangeStart;
  final String? timeRangeEnd;
  final String applyDiningType;
  final bool allowCoupon;
  final int? dailyStock;

  bool get enabled => comboId > 0 && status != 0;

  bool orderLimitReached(int quantityInOrder) =>
      limitPerOrder != null &&
      limitPerOrder! > 0 &&
      quantityInOrder >= limitPerOrder!;

  String? unavailableReason({
    required DateTime now,
    required bool packingOrder,
  }) {
    if (!enabled) return '套餐已停用';
    final startsAt = _comboDateTime(startTime);
    if (startsAt != null && now.isBefore(startsAt)) return '活动尚未开始';
    final endsAt = _comboDateTime(endTime);
    if (endsAt != null && now.isAfter(endsAt)) return '活动已结束';
    final days = (availableDays ?? '')
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .toSet();
    if (days.isNotEmpty && !days.contains(now.weekday)) return '今日不可售';
    final currentMinutes = now.hour * 60 + now.minute;
    final startMinutes = _timeMinutes(timeRangeStart);
    if (startMinutes != null && currentMinutes < startMinutes) {
      return '${_shortTime(timeRangeStart!)} 开始售卖';
    }
    final endMinutes = _timeMinutes(timeRangeEnd);
    if (endMinutes != null && currentMinutes > endMinutes) {
      return '${_shortTime(timeRangeEnd!)} 已结束';
    }
    final requiredDining = applyDiningType.trim().toLowerCase();
    if (requiredDining == 'dine_in' && packingOrder) return '仅限堂食';
    if (requiredDining == 'take_out' && !packingOrder) return '仅限打包';
    return null;
  }

  double extraPriceFor(Map<String, List<int>> selections) {
    var total = 0.0;
    for (final group in groups) {
      final selectedIds = selections[group.key] ?? const <int>[];
      for (final option in group.options) {
        if (selectedIds.contains(option.dishId)) total += option.extraPrice;
      }
    }
    return total;
  }

  static PosComboDefinition? fromJsonOrNull(Object? raw) {
    final json = _objectMap(raw);
    if (json.isEmpty) return null;
    final comboId = _int(json['comboId'] ?? json['combo_id'] ?? json['id']);
    if (comboId <= 0) return null;
    return PosComboDefinition(
      comboId: comboId,
      dishId: _int(json['dishId'] ?? json['dish_id']),
      comboType: _string(json['comboType'] ?? json['combo_type']),
      status: _int(json['status'], fallback: 1),
      fixedItems: _mapList(
        json['fixedItems'] ?? json['fixed_items'],
      ).map(PosComboFixedItem.fromJson).toList(growable: false),
      groups: _mapList(
        json['groups'],
      ).map(PosComboGroup.fromJson).toList(growable: false),
      limitPerOrder: _nullableInt(
        json['limitPerOrder'] ?? json['limit_per_order'],
      ),
      limitPerUser: _nullableInt(
        json['limitPerUser'] ?? json['limit_per_user'],
      ),
      limitCycle: _string(json['limitCycle'] ?? json['limit_cycle']).isEmpty
          ? 'daily'
          : _string(json['limitCycle'] ?? json['limit_cycle']),
      startTime: _optionalText(json['startTime'] ?? json['start_time']),
      endTime: _optionalText(json['endTime'] ?? json['end_time']),
      availableDays: _optionalText(
        json['availableDays'] ?? json['available_days'],
      ),
      timeRangeStart: _optionalText(
        json['timeRangeStart'] ?? json['time_range_start'],
      ),
      timeRangeEnd: _optionalText(
        json['timeRangeEnd'] ?? json['time_range_end'],
      ),
      applyDiningType:
          _string(json['applyDiningType'] ?? json['apply_dining_type']).isEmpty
          ? 'all'
          : _string(json['applyDiningType'] ?? json['apply_dining_type']),
      allowCoupon: _bool(
        json['allowCoupon'] ?? json['allow_coupon'],
        fallback: true,
      ),
      dailyStock: _nullableInt(json['dailyStock'] ?? json['daily_stock']),
    );
  }
}

DateTime? _comboDateTime(String? raw) {
  final value = raw?.trim() ?? '';
  if (value.isEmpty) return null;
  return DateTime.tryParse(value.replaceFirst(' ', 'T'));
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

int? _timeMinutes(String? raw) {
  final parts = (raw ?? '').split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;
  return hour * 60 + minute;
}

String _shortTime(String raw) {
  final parts = raw.split(':');
  return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : raw;
}

class PosComboFixedItem {
  const PosComboFixedItem({required this.dishId, required this.quantity});

  final int dishId;
  final int quantity;

  factory PosComboFixedItem.fromJson(Map<String, Object?> json) =>
      PosComboFixedItem(
        dishId: _int(
          json['componentDishId'] ??
              json['component_dish_id'] ??
              json['dishId'] ??
              json['dish_id'],
        ),
        quantity: _int(
          json['qtyPerCombo'] ?? json['qty_per_combo'],
          fallback: 1,
        ),
      );
}

class PosComboGroup {
  const PosComboGroup({
    required this.key,
    required this.title,
    required this.minPick,
    required this.maxPick,
    required this.options,
  });

  final String key;
  final String title;
  final int minPick;
  final int maxPick;
  final List<PosComboOption> options;

  factory PosComboGroup.fromJson(Map<String, Object?> json) => PosComboGroup(
    key: _string(json['groupKey'] ?? json['group_key']),
    title: _string(json['title']),
    minPick: _int(json['minPick'] ?? json['min_pick'], fallback: 1),
    maxPick: _int(json['maxPick'] ?? json['max_pick'], fallback: 1),
    options: _mapList(
      json['items'] ?? json['options'],
    ).map(PosComboOption.fromJson).toList(growable: false),
  );
}

class PosComboOption {
  const PosComboOption({required this.dishId, required this.extraPrice});

  final int dishId;
  final double extraPrice;

  factory PosComboOption.fromJson(Map<String, Object?> json) => PosComboOption(
    dishId: _int(
      json['componentDishId'] ??
          json['component_dish_id'] ??
          json['dishId'] ??
          json['dish_id'],
    ),
    extraPrice: _double(json['extraPrice'] ?? json['extra_price']),
  );
}

class PosCartLine {
  const PosCartLine({
    required this.dish,
    required this.selections,
    required this.quantity,
    this.comboSelections = const {},
  });

  final PosDish dish;
  final Map<String, String> selections;
  final int quantity;
  final Map<String, List<int>> comboSelections;

  double get unitPrice =>
      dish.price + (dish.comboDefinition?.extraPriceFor(comboSelections) ?? 0);
  double get total => unitPrice * quantity;
  String get specification => selections.values.join('、');
  String get key =>
      '${dish.id}|${jsonEncode(selections)}|${jsonEncode(comboSelections)}';

  PosCartLine copyWith({int? quantity}) {
    return PosCartLine(
      dish: dish,
      selections: selections,
      quantity: quantity ?? this.quantity,
      comboSelections: comboSelections,
    );
  }

  Map<String, Object?> requestBody({String? clientLineId}) {
    final combo = dish.comboDefinition;
    return {
      // The unified cashier contract validates normal menu lines by dish_id.
      // Keep mId for older deployments during the compatibility window.
      'dish_id': dish.id,
      'mId': dish.id,
      'name': dish.name,
      'cid': dish.requestCategoryCode,
      'quantity': '$quantity',
      'unit': dish.unit,
      'serving_duration_minutes': dish.servingDurationMinutes,
      'total_price': total,
      'selectedSpicy': selections.isEmpty ? '' : jsonEncode(selections),
      if (combo?.enabled == true) 'line_type': 'combo',
      if (combo?.enabled == true) 'combo_id': combo!.comboId,
      if (combo?.enabled == true)
        'combo_selections': {
          for (final entry in comboSelections.entries)
            entry.key: List<int>.from(entry.value),
        },
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
    Map<String, List<int>> comboSelections = const {},
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
      comboSelections: _normalizeComboSelections(dish, comboSelections),
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

  Map<String, List<int>> _normalizeComboSelections(
    PosDish dish,
    Map<String, List<int>> selections,
  ) {
    final combo = dish.comboDefinition;
    if (combo == null || !combo.enabled) return const {};
    return {
      for (final group in combo.groups)
        if (group.key.isNotEmpty)
          group.key: List<int>.unmodifiable(
            (selections[group.key] ?? const <int>[])
                .where(
                  (dishId) =>
                      group.options.any((option) => option.dishId == dishId),
                )
                .toList(growable: false),
          ),
    };
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

/// 退菜库存动作（对齐服务端 v1.2.203 `stock_action`）。
enum PosRefundStockAction {
  restore('RESTORE', '回退库存', '退菜数量加回门店可售库存；若菜品处于售罄且回退后有货，自动解除售罄'),
  noRestore('NO_RESTORE', '损耗不回退', '菜品已制作或食材已损耗：只退菜退款，不加回库存，记录损耗流水'),
  outOfStock('OUT_OF_STOCK', '缺货估清', '食材用尽退菜：不回退库存，该菜品库存清零并强制售罄，全端即时广播');

  const PosRefundStockAction(this.wireValue, this.label, this.description);

  final String wireValue;
  final String label;
  final String description;
}

class PosOrderLine {
  const PosOrderLine({
    required this.id,
    required this.name,
    this.orderNo = '',
    required this.quantity,
    required this.total,
    required this.specification,
    required this.refunded,
    this.unit = '',
    this.productionStatus = '',
    this.kdsStatusText = '',
    this.kdsItemStatus = '',
    this.kdsServedQuantity,
    this.lineType = '',
    this.comboId,
    this.comboInstanceId = '',
    this.parentDetailId,
  });

  final int id;
  final String name;
  final String orderNo;
  final int quantity;
  final double total;
  final String unit;
  final String specification;
  final bool refunded;
  final String productionStatus;

  /// 服务端 KDS 制作状态中文文案（v1.2.224 `kds_status_text`）。
  final String kdsStatusText;

  /// 服务端 KDS 制作状态码（v1.2.224 `kds_item_status`）：0待制作/1制作中/2已完成/3已退菜。
  final String kdsItemStatus;

  /// 已传菜数量（v1.2.224 `kds_served_quantity`）。
  final int? kdsServedQuantity;
  final String lineType;
  final int? comboId;
  final String comboInstanceId;
  final int? parentDetailId;

  bool get isComboHeader => lineType == 'combo_header';
  bool get isComboComponent => lineType == 'combo_component';

  bool get isRefunded =>
      refunded ||
      kdsItemStatus == '3' ||
      kdsStatusText == '已退菜' ||
      productionStatus == '3' ||
      productionStatus == 'refunded' ||
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
      !isRefunded && (productionStatusLabel == '制作中' || isPartiallyServed);

  bool get isPending => !isRefunded && productionStatusLabel == '待制作';

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
      '2' ||
      'done' ||
      'completed' ||
      'served' ||
      'ready' ||
      'off_order' ||
      '已出餐' ||
      '已完成' => '已出餐',
      '1' ||
      'cooking' ||
      'in_progress' ||
      'making' ||
      'preparing' ||
      '制作中' ||
      '烹饪中' => '制作中',
      '0' || 'pending' || 'wait' || 'rec_order' || 'accepted' || '待制作' => '待制作',
      '' || 'mis_order' || 'not_started' || 'unstarted' || '未制作' => '未制作',
      '3' ||
      'refunded' ||
      'cancelled' ||
      'canceled' ||
      'voided' ||
      '已退菜' ||
      '已取消' => '已退菜',
      _ => '—',
    };
  }

  double get unitPrice => quantity <= 0 ? total : total / quantity;

  PosOrderLine copyWith({
    int? id,
    String? name,
    String? orderNo,
    int? quantity,
    double? total,
    String? unit,
    String? specification,
    bool? refunded,
    String? productionStatus,
    String? kdsStatusText,
    String? kdsItemStatus,
    int? kdsServedQuantity,
    String? lineType,
    int? comboId,
    String? comboInstanceId,
    int? parentDetailId,
  }) => PosOrderLine(
    id: id ?? this.id,
    name: name ?? this.name,
    orderNo: orderNo ?? this.orderNo,
    quantity: quantity ?? this.quantity,
    total: total ?? this.total,
    unit: unit ?? this.unit,
    specification: specification ?? this.specification,
    refunded: refunded ?? this.refunded,
    productionStatus: productionStatus ?? this.productionStatus,
    kdsStatusText: kdsStatusText ?? this.kdsStatusText,
    kdsItemStatus: kdsItemStatus ?? this.kdsItemStatus,
    kdsServedQuantity: kdsServedQuantity ?? this.kdsServedQuantity,
    lineType: lineType ?? this.lineType,
    comboId: comboId ?? this.comboId,
    comboInstanceId: comboInstanceId ?? this.comboInstanceId,
    parentDetailId: parentDetailId ?? this.parentDetailId,
  );

  factory PosOrderLine.fromJson(Map<String, Object?> json) {
    final selections = _selectionLabel(
      json['selectedSpicy'] ?? json['selected_spicy'] ?? json['specification'],
    );
    final rawLineStatus = _string(
      json['line_status'] ?? json['lineStatus'],
    ).toLowerCase();
    // line_status 仅为退菜软删标记（normal/refunded），normal 不能遮蔽接单状态，
    // 否则退菜判定与出品状态会读取不到 order_rece。
    final status = rawLineStatus == 'refunded'
        ? 'refunded'
        : _string(
            json['order_rece'] ??
                json['orderReceiving'] ??
                json['order_receiving'] ??
                json['receiving_status'] ??
                json['receivingStatus'],
          ).toLowerCase();
    final kdsStatusText = _string(
      json['kds_status_text'] ?? json['kdsStatusText'],
    ).trim();
    final kdsItemStatus = _string(
      json['kds_item_status'] ?? json['kdsItemStatus'],
    ).trim();
    final rawItemStatus = _string(
      json['item_status'] ?? json['itemStatus'],
    ).trim();
    final rawProdStatus = _string(
      json['production_status'] ?? json['productionStatus'],
    ).trim().toLowerCase();
    final kdsServedQuantity = _nullableInt(
      json['kds_served_quantity'] ?? json['kdsServedQuantity'],
    );
    final isRefundedDish =
        status == 'refunded' ||
        kdsItemStatus == '3' ||
        rawItemStatus == '3' ||
        kdsStatusText == '已退菜' ||
        rawProdStatus == 'refunded' ||
        rawProdStatus == '已退菜';
    return PosOrderLine(
      id: _int(json['id'] ?? json['detail_id'] ?? json['detailId']),
      name: _string(json['name'] ?? json['dish_name'] ?? json['dishName']),
      orderNo: _string(
        json['Morder_no'] ??
            json['morder_no'] ??
            json['order_no'] ??
            json['orderNo'],
      ).trim(),
      quantity: _int(json['quantity'] ?? json['number'] ?? json['count']),
      total: _double(json['total_price'] ?? json['totalPrice']),
      unit: _string(json['unit'] ?? json['dish_unit'] ?? json['dishUnit']),
      specification: selections,
      refunded: isRefundedDish,
      productionStatus: _string(
        kdsStatusText.isNotEmpty
            ? kdsStatusText
            : kdsItemStatus.isNotEmpty
            ? kdsItemStatus
            : json['production_status'] ??
                  json['productionStatus'] ??
                  json['item_status'] ??
                  json['itemStatus'] ??
                  json['order_rece'],
      ).trim().toLowerCase(),
      kdsStatusText: kdsStatusText,
      kdsItemStatus: kdsItemStatus,
      kdsServedQuantity: kdsServedQuantity,
      lineType: _string(
        json['line_type'] ?? json['lineType'],
      ).trim().toLowerCase(),
      comboId: _nullableInt(json['combo_id'] ?? json['comboId']),
      comboInstanceId: _string(
        json['combo_instance_id'] ?? json['comboInstanceId'],
      ).trim(),
      parentDetailId: _nullableInt(
        json['parent_detail_id'] ?? json['parentDetailId'],
      ),
    );
  }
}

class PosOrder {
  const PosOrder({
    required this.id,
    required this.orderNo,
    this.masterOrderNo,
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
    this.revision,
  });

  final int id;
  final String orderNo;
  final String? masterOrderNo;
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
  final int? revision;

  bool get hasRegisteredMember => memberPhone.trim().isNotEmpty;
  bool get canUseStoredValue =>
      hasRegisteredMember &&
      memberOpenid.trim().isNotEmpty &&
      memberBalance != null;

  bool get isMergedSlaveOrder =>
      masterOrderNo != null && masterOrderNo!.trim().isNotEmpty;

  factory PosOrder.fromJson(Map<String, Object?> json) {
    final goods = _mapList(
      json['goods_list'] ?? json['lines'] ?? json['items'] ?? json['details'],
    );
    final rawOrderNo = _string(json['order_no'] ?? json['orderNo']).trim();
    final parsedLines = [
      for (final l in goods.map(PosOrderLine.fromJson))
        l.orderNo.isEmpty && rawOrderNo.isNotEmpty
            ? l.copyWith(orderNo: rawOrderNo)
            : l,
    ];
    final linesTotal = parsedLines
        .where((line) => !line.refunded)
        .fold<double>(0.0, (sum, line) => sum + line.total);
    var amount = _positiveDouble(json['sett_amount']) ??
        _positiveDouble(json['settAmount']) ??
        _positiveDouble(json['total_amount']) ??
        _positiveDouble(json['totalAmount']) ??
        _positiveDouble(json['pay_amount']) ??
        _positiveDouble(json['amount']) ??
        (linesTotal > 0
            ? linesTotal
            : _double(
                json['sett_amount'] ??
                    json['settAmount'] ??
                    json['total_amount'],
              ));
    if (amount <= 0 && linesTotal > 0) {
      amount = linesTotal;
    }
    final discount = _double(json['discount_amount'] ?? json['discountAmount']);
    final service = _double(json['service_fee'] ?? json['serviceFee']);
    final refund = _double(json['refund_amount'] ?? json['refundAmount']);
    final wipeZero = _double(
      json['wipe_zero_amount'] ?? json['wipeZeroAmount'] ?? json['wipe_amount'],
    );
    final gross = amount + service - refund;
    final rawMaster = _string(json['master_order_no'] ?? json['masterOrderNo']);
    final calculatedTotal = gross - discount - wipeZero;
    final total = calculatedTotal > 0
        ? calculatedTotal
        : (discount <= 0 && wipeZero <= 0 && linesTotal > 0
            ? linesTotal
            : calculatedTotal);
    return PosOrder(
      id: _int(json['id'] ?? json['order_id'] ?? json['orderId']),
      orderNo: rawOrderNo,
      masterOrderNo: rawMaster.isEmpty ? null : rawMaster,
      tableNumber: _string(json['table_number'] ?? json['tableNumber']),
      diners: _int(
        json['number_of_diners'] ??
            json['numberOfDiners'] ??
            json['people_count'],
        fallback: 1,
      ),
      total: total,
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
      lines: parsedLines,
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
      revision: _nullableInt(
        json['revision'] ?? json['order_revision'] ?? json['orderRevision'],
      ),
    );
  }

  PosOrder copyWith({
    List<PosOrderLine>? lines,
    String? receivingStatus,
    String? kdsOrderStatus,
    String? masterOrderNo,
    double? total,
    double? grossAmount,
    double? discountAmount,
    double? wipeZeroAmount,
    int? revision,
  }) {
    return PosOrder(
      id: id,
      orderNo: orderNo,
      masterOrderNo: masterOrderNo ?? this.masterOrderNo,
      tableNumber: tableNumber,
      diners: diners,
      total: total ?? this.total,
      grossAmount: grossAmount ?? this.grossAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      wipeZeroAmount: wipeZeroAmount ?? this.wipeZeroAmount,
      memberPhone: memberPhone,
      memberOpenid: memberOpenid,
      memberBalance: memberBalance,
      createdAt: createdAt,
      lines: lines ?? this.lines,
      receivingStatus: receivingStatus ?? this.receivingStatus,
      kdsOrderStatus: kdsOrderStatus ?? this.kdsOrderStatus,
      revision: revision ?? this.revision,
    );
  }
}

class PosWorkspace {
  const PosWorkspace({
    required this.table,
    required this.categories,
    required this.dishes,
    required this.currentOrder,
    this.tableOrders = const [],
    this.paymentMethods = const [],
    this.paymentConfigurationAvailable = true,
  });

  final DiningTable table;
  final List<PosCategory> categories;
  final List<PosDish> dishes;
  final PosOrder? currentOrder;
  final List<PosOrder> tableOrders;
  final List<PosPaymentMethod> paymentMethods;
  final bool paymentConfigurationAvailable;

  PosWorkspace copyWith({
    DiningTable? table,
    List<PosCategory>? categories,
    List<PosDish>? dishes,
    PosOrder? currentOrder,
    List<PosOrder>? tableOrders,
    List<PosPaymentMethod>? paymentMethods,
    bool? paymentConfigurationAvailable,
  }) {
    return PosWorkspace(
      table: table ?? this.table,
      categories: categories ?? this.categories,
      dishes: dishes ?? this.dishes,
      currentOrder: currentOrder ?? this.currentOrder,
      tableOrders: tableOrders ?? this.tableOrders,
      paymentMethods: paymentMethods ?? this.paymentMethods,
      paymentConfigurationAvailable:
          paymentConfigurationAvailable ?? this.paymentConfigurationAvailable,
    );
  }

  bool get isMergedTable =>
      tableOrders.length > 1 ||
      (currentOrder?.isMergedSlaveOrder ?? false) ||
      tableOrders.any((o) => o.isMergedSlaveOrder);

  double get tableTotalPayable {
    if (tableOrders.isEmpty) return currentOrder?.total ?? 0;
    return tableOrders.fold(0.0, (sum, o) => sum + o.total);
  }

  double get tableTotalDiscount {
    if (tableOrders.isEmpty) {
      return (currentOrder?.discountAmount ?? 0) +
          (currentOrder?.wipeZeroAmount ?? 0);
    }
    return tableOrders.fold(
      0.0,
      (sum, o) => sum + o.discountAmount + o.wipeZeroAmount,
    );
  }

  PosOrder? findOrderByDetailId(int detailId) {
    for (final o in tableOrders) {
      if (o.lines.any((l) => l.id == detailId)) {
        return o;
      }
    }
    return currentOrder;
  }

  PosOrder? findOrderByLine(PosOrderLine line) {
    if (line.orderNo.isNotEmpty) {
      for (final o in tableOrders) {
        if (o.orderNo == line.orderNo) return o;
      }
    }
    return findOrderByDetailId(line.id);
  }

  List<PosOrderLine> get allLines {
    if (tableOrders.isEmpty) return currentOrder?.lines ?? const [];
    return [
      for (final order in tableOrders)
        for (final line in order.lines)
          line.orderNo.isEmpty ? line.copyWith(orderNo: order.orderNo) : line,
    ];
  }
}

class PosTableCheckoutResult {
  const PosTableCheckoutResult({
    required this.tableNumber,
    required this.settledOrders,
    required this.totalAmount,
    this.cashAmount,
    this.changeAmount = 0,
  });

  final String tableNumber;
  final List<String> settledOrders;
  final double totalAmount;
  final double? cashAmount;
  final double changeAmount;

  factory PosTableCheckoutResult.fromJson(Map<String, Object?> json) {
    final rawSettled = json['settledOrders'] ?? json['settled_orders'];
    final List<String> settledList;
    if (rawSettled is List) {
      settledList = rawSettled.map((e) => '$e').toList(growable: false);
    } else if (rawSettled != null) {
      settledList = List.generate(
        int.tryParse('$rawSettled') ?? 0,
        (i) => 'ORDER_${i + 1}',
      );
    } else {
      settledList = const [];
    }
    return PosTableCheckoutResult(
      tableNumber: _string(json['tableNumber'] ?? json['table_number']),
      settledOrders: settledList,
      totalAmount: _double(json['totalAmount'] ?? json['total_amount']),
      cashAmount: _nullableDouble(json['cashAmount'] ?? json['cash_amount']),
      changeAmount: _double(json['changeAmount'] ?? json['change_amount']),
    );
  }
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
    final rawSuccess =
        json['printSuccess'] ?? json['print_success'] ?? json['success'];
    final failedCount = _int(json['failed_count'] ?? json['failedCount']);
    final dispatchedCount = _int(
      json['dispatched_count'] ?? json['dispatchedCount'],
    );
    final totalJobs = _int(json['total_jobs'] ?? json['totalJobs']);
    final bool dispatchSuccess = totalJobs > 0
        ? (dispatchedCount > 0 && failedCount == 0)
        : true;
    final bool printSuccess = rawSuccess != null
        ? _bool(rawSuccess)
        : dispatchSuccess;
    final content = _string(json['content'] ?? json['summary'] ?? json['msg']);
    return PosPrintResult(
      content: content,
      printSuccess: printSuccess,
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
  wechatMicropay('online_wechat_micropay'),
  wechatNative('online_wechat'),
  wechat('offline_wechat_qr'),
  alipay('offline_alipay_qr'),
  balance('online_balance'),
  combined('online_combined'),
  receivable('receivable');

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
      'onlinewechatmicropay' ||
      'wechatmicropay' ||
      'micropay' ||
      'micropaywechat' ||
      'cashierwechatmicropay' ||
      '微信付款码' ||
      '微信付款码支付' ||
      '付款码' ||
      '付款码支付' => PosPaymentChannelKind.wechatMicropay,
      'onlinewechat' ||
      'wechatnative' ||
      'nativewechat' ||
      'cashierwechatnative' ||
      '微信native支付' ||
      '微信动态码' ||
      '微信动态码支付' => PosPaymentChannelKind.wechatNative,
      'offlinewechatqr' ||
      'offlinewechat' ||
      'wechatqr' ||
      'wechat' ||
      'wechatpay' ||
      'wxpay' ||
      'weixin' ||
      'wx' ||
      'cashierwechat' ||
      'miniprogramwechat' ||
      'offlinecollectwechat' ||
      '微信' ||
      '微信支付' ||
      '微信收款码' ||
      '微信码' => PosPaymentChannelKind.wechat,
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
      '混合支付' => PosPaymentKindNormalizedCombined,
      'receivable' ||
      'receivables' ||
      'credit' ||
      'ar' ||
      'charge' ||
      'cashierreceivable' ||
      '挂账' ||
      '客户挂账' ||
      '企业挂账' ||
      '挂账支付' ||
      '记账' ||
      '记账支付' => PosPaymentChannelKind.receivable,
      _ => null,
    };
  }
}

const PosPaymentChannelKind PosPaymentKindNormalizedCombined =
    PosPaymentChannelKind.combined;

class PosWechatNativeOrder {
  const PosWechatNativeOrder({
    required this.paymentId,
    required this.orderNo,
    required this.outTradeNo,
    required this.codeUrl,
    required this.amountFen,
    this.expiresAt,
    this.tradeState = 'NOTPAY',
    this.reused = false,
  });

  final int paymentId;
  final String orderNo;
  final String outTradeNo;
  final String codeUrl;
  final int amountFen;
  final DateTime? expiresAt;
  final String tradeState;
  final bool reused;

  double get amountYuan => amountFen / 100.0;

  factory PosWechatNativeOrder.fromJson(Map<String, dynamic> json) {
    final payload = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    DateTime? parseDate(Object? value) {
      if (value == null) return null;
      try {
        return DateTime.parse(value.toString());
      } catch (_) {
        return null;
      }
    }

    return PosWechatNativeOrder(
      paymentId: _int(payload['paymentId'] ?? payload['payment_id']),
      orderNo: _string(payload['orderNo'] ?? payload['order_no']),
      outTradeNo: _string(payload['outTradeNo'] ?? payload['out_trade_no']),
      codeUrl: _string(payload['codeUrl'] ?? payload['code_url']),
      amountFen: _int(payload['amountFen'] ?? payload['amount_fen']),
      expiresAt: parseDate(payload['expiresAt'] ?? payload['expires_at']),
      tradeState: _string(
        payload['tradeState'] ?? payload['trade_state'] ?? 'NOTPAY',
      ),
      reused: _bool(payload['reused']),
    );
  }
}

class PosWechatNativeStatus {
  const PosWechatNativeStatus({
    required this.paymentId,
    required this.orderNo,
    required this.outTradeNo,
    required this.amountFen,
    required this.tradeState,
    required this.status,
    this.transactionId,
  });

  final int paymentId;
  final String orderNo;
  final String outTradeNo;
  final int amountFen;
  final String tradeState;
  final String status;
  final String? transactionId;

  bool get isSuccess => tradeState.toUpperCase() == 'SUCCESS';
  bool get isClosed =>
      tradeState.toUpperCase() == 'CLOSED' ||
      tradeState.toUpperCase() == 'REVOKED';
  bool get isPayError => tradeState.toUpperCase() == 'PAYERROR';

  factory PosWechatNativeStatus.fromJson(Map<String, dynamic> json) {
    final payload = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    return PosWechatNativeStatus(
      paymentId: _int(payload['paymentId'] ?? payload['payment_id']),
      orderNo: _string(payload['orderNo'] ?? payload['order_no']),
      outTradeNo: _string(payload['outTradeNo'] ?? payload['out_trade_no']),
      amountFen: _int(payload['amountFen'] ?? payload['amount_fen']),
      tradeState: _string(payload['tradeState'] ?? payload['trade_state']),
      status: _string(payload['status']),
      transactionId: payload['transactionId'] != null
          ? _string(payload['transactionId'])
          : null,
    );
  }
}

class PosWechatNativeCloseResult {
  const PosWechatNativeCloseResult({
    required this.closed,
    this.idempotent = false,
    this.outTradeNo,
  });

  final bool closed;
  final bool idempotent;
  final String? outTradeNo;

  factory PosWechatNativeCloseResult.fromJson(Map<String, dynamic> json) {
    final payload = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    return PosWechatNativeCloseResult(
      closed: _bool(payload['closed']),
      idempotent: _bool(payload['idempotent']),
      outTradeNo: payload['outTradeNo'] != null
          ? _string(payload['outTradeNo'])
          : null,
    );
  }
}

class PosWechatMicropayOrder {
  const PosWechatMicropayOrder({
    required this.orderNo,
    required this.outTradeNo,
    required this.amountFen,
    this.tradeState = 'USERPAYING',
    this.status = 'USERPAYING',
    this.transactionId,
  });

  final String orderNo;
  final String outTradeNo;
  final int amountFen;
  final String tradeState;
  final String status;
  final String? transactionId;

  double get amountYuan => amountFen / 100.0;
  bool get isSuccess => tradeState.toUpperCase() == 'SUCCESS';
  bool get isUserPaying => tradeState.toUpperCase() == 'USERPAYING';

  factory PosWechatMicropayOrder.fromJson(Map<String, dynamic> json) {
    final payload = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    return PosWechatMicropayOrder(
      orderNo: _string(payload['orderNo'] ?? payload['order_no']),
      outTradeNo: _string(payload['outTradeNo'] ?? payload['out_trade_no']),
      amountFen: _int(payload['amountFen'] ?? payload['amount_fen']),
      tradeState: _string(payload['tradeState'] ?? payload['trade_state']),
      status: _string(payload['status']),
      transactionId: payload['transactionId'] != null
          ? _string(payload['transactionId'])
          : null,
    );
  }
}

class PosWechatMicropayStatus {
  const PosWechatMicropayStatus({
    required this.orderNo,
    required this.outTradeNo,
    required this.amountFen,
    required this.tradeState,
    required this.status,
    this.transactionId,
  });

  final String orderNo;
  final String outTradeNo;
  final int amountFen;
  final String tradeState;
  final String status;
  final String? transactionId;

  double get amountYuan => amountFen / 100.0;
  bool get isSuccess => tradeState.toUpperCase() == 'SUCCESS';
  bool get isUserPaying => tradeState.toUpperCase() == 'USERPAYING';
  bool get isClosed =>
      tradeState.toUpperCase() == 'CLOSED' ||
      tradeState.toUpperCase() == 'REVOKED';
  bool get isPayError => tradeState.toUpperCase() == 'PAYERROR';

  factory PosWechatMicropayStatus.fromJson(Map<String, dynamic> json) {
    final payload = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    return PosWechatMicropayStatus(
      orderNo: _string(payload['orderNo'] ?? payload['order_no']),
      outTradeNo: _string(payload['outTradeNo'] ?? payload['out_trade_no']),
      amountFen: _int(payload['amountFen'] ?? payload['amount_fen']),
      tradeState: _string(payload['tradeState'] ?? payload['trade_state']),
      status: _string(payload['status']),
      transactionId: payload['transactionId'] != null
          ? _string(payload['transactionId'])
          : null,
    );
  }
}

class PosWechatMicropayReverseResult {
  const PosWechatMicropayReverseResult({
    required this.reversed,
    this.alreadyPaid = false,
    this.outTradeNo,
  });

  final bool reversed;
  final bool alreadyPaid;
  final String? outTradeNo;

  factory PosWechatMicropayReverseResult.fromJson(Map<String, dynamic> json) {
    final payload = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    return PosWechatMicropayReverseResult(
      reversed: _bool(payload['reversed'] ?? (payload['status'] == 'REVERSED')),
      alreadyPaid: _bool(payload['alreadyPaid'] ?? payload['already_paid']),
      outTradeNo: payload['outTradeNo'] != null
          ? _string(payload['outTradeNo'])
          : null,
    );
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
    if (decoded is Map) {
      return decoded.values
          .where((value) => value is! Map && value is! List)
          .where(
            (value) =>
                value != null &&
                num.tryParse(_cleanSpecToken('$value')) == null,
          )
          .map((value) => _cleanSpecToken('$value'))
          .where((value) => value.isNotEmpty)
          .join('、');
    }
  } catch (_) {}
  return source;
}

String _cleanSpecToken(String raw) => raw
    .replaceAll('"', '')
    .replaceAll("'", '')
    .replaceAll('[', '')
    .replaceAll(']', '')
    .replaceAll('{', '')
    .replaceAll('}', '')
    .trim();

List<Map<String, Object?>> _mapList(Object? value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, Object?>())
      .toList(growable: false);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map) return value.cast<String, Object?>();
  final source = _string(value);
  if (source.isEmpty) return const {};
  try {
    final decoded = jsonDecode(source);
    return decoded is Map
        ? decoded.cast<String, Object?>()
        : const <String, Object?>{};
  } catch (_) {
    return const {};
  }
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

double? _positiveDouble(Object? value) {
  final d = _nullableDouble(value);
  return (d != null && d > 0) ? d : null;
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

/// 门店可挂账授信账户模型 (WI-023 / v1.2.298)
class PosReceivableEligibleAccount {
  const PosReceivableEligibleAccount({
    required this.id,
    required this.scopeType,
    required this.customerType,
    required this.customerName,
    this.contactName = '',
    this.contactPhone = '',
    this.taxNo = '',
    required this.creditLimitFen,
    required this.availableLimitFen,
    this.outstandingFen = 0,
    this.paymentTermsDays = 30,
    this.status = 'ACTIVE',
    this.notes = '',
  });

  final int id;
  final String scopeType;
  final String customerType;
  final String customerName;
  final String contactName;
  final String contactPhone;
  final String taxNo;
  final int creditLimitFen;
  final int availableLimitFen;
  final int outstandingFen;
  final int paymentTermsDays;
  final String status;
  final String notes;

  double get creditLimitYuan => creditLimitFen / 100.0;
  double get availableLimitYuan => availableLimitFen / 100.0;
  double get outstandingYuan => outstandingFen / 100.0;

  bool canCover(double requiredYuan) =>
      availableLimitYuan >= (requiredYuan - 0.0001);

  bool get isCompany => customerType.toUpperCase() == 'COMPANY';

  factory PosReceivableEligibleAccount.fromJson(Map<String, Object?> json) {
    final creditLimit = _int(
      json['creditLimitFen'] ?? json['credit_limit_fen'],
    );
    final outstanding = _int(json['outstandingFen'] ?? json['outstanding_fen']);

    // 优先读取服务端下发的可用额度；若未传或异常为0且未清为0，则通过 (creditLimitFen - outstandingFen) 兜底计算
    final rawAvailable =
        json['availableLimitFen'] ??
        json['available_limit_fen'] ??
        json['availableFen'] ??
        json['available_fen'];
    int available;
    if (rawAvailable != null) {
      final parsed = _int(rawAvailable);
      if (parsed == 0 && outstanding == 0 && creditLimit > 0) {
        available = creditLimit;
      } else {
        available = parsed;
      }
    } else {
      available = (creditLimit - outstanding).clamp(0, creditLimit);
    }

    return PosReceivableEligibleAccount(
      id: _int(json['id']),
      scopeType: _string(json['scopeType'] ?? json['scope_type'] ?? 'SHOP'),
      customerType: _string(
        json['customerType'] ?? json['customer_type'] ?? 'PERSON',
      ),
      customerName: _string(json['customerName'] ?? json['customer_name']),
      contactName: _string(json['contactName'] ?? json['contact_name']),
      contactPhone: _string(json['contactPhone'] ?? json['contact_phone']),
      taxNo: _string(json['taxNo'] ?? json['tax_no']),
      creditLimitFen: creditLimit,
      availableLimitFen: available,
      outstandingFen: outstanding,
      paymentTermsDays: _int(
        json['paymentTermsDays'] ?? json['payment_terms_days'] ?? 30,
      ),
      status: _string(json['status'] ?? 'ACTIVE'),
      notes: _string(json['notes']),
    );
  }
}

/// 门店应收账款单据模型 (WI-023 / v1.2.298)
class PosReceivableClaim {
  const PosReceivableClaim({
    required this.id,
    required this.claimNo,
    required this.orderNo,
    required this.shopId,
    required this.accountId,
    required this.originalAmountFen,
    required this.collectedAmountFen,
    required this.outstandingFen,
    this.writtenOffAmountFen = 0,
    required this.status,
    this.dueDate = '',
    this.overdueDays = 0,
    this.customerName = '',
    this.customerType = '',
    this.contactPhone = '',
  });

  final int id;
  final String claimNo;
  final String orderNo;
  final int shopId;
  final int accountId;
  final int originalAmountFen;
  final int collectedAmountFen;
  final int outstandingFen;
  final int writtenOffAmountFen;
  final String status;
  final String dueDate;
  final int overdueDays;
  final String customerName;
  final String customerType;
  final String contactPhone;

  double get originalAmountYuan => originalAmountFen / 100.0;
  double get collectedAmountYuan => collectedAmountFen / 100.0;
  double get outstandingYuan => outstandingFen / 100.0;
  double get writtenOffAmountYuan => writtenOffAmountFen / 100.0;

  bool get isUnsettled => status == 'OPEN' || status == 'PARTIAL';
  bool get isOverdue => overdueDays > 0;

  factory PosReceivableClaim.fromJson(Map<String, Object?> json) {
    return PosReceivableClaim(
      id: _int(json['id']),
      claimNo: _string(json['claimNo'] ?? json['claim_no']),
      orderNo: _string(json['orderNo'] ?? json['order_no']),
      shopId: _int(json['shopId'] ?? json['shop_id']),
      accountId: _int(json['accountId'] ?? json['account_id']),
      originalAmountFen: _int(
        json['originalAmountFen'] ?? json['original_amount_fen'],
      ),
      collectedAmountFen: _int(
        json['collectedAmountFen'] ?? json['collected_amount_fen'],
      ),
      outstandingFen: _int(json['outstandingFen'] ?? json['outstanding_fen']),
      writtenOffAmountFen: _int(
        json['writtenOffAmountFen'] ?? json['written_off_amount_fen'],
      ),
      status: _string(json['status'] ?? 'OPEN'),
      dueDate: _string(json['dueDate'] ?? json['due_date']),
      overdueDays: _int(json['overdueDays'] ?? json['overdue_days']),
      customerName: _string(
        json['customerName'] ??
            json['customer_name'] ??
            json['accountCustomerName'] ??
            json['account_customer_name'],
      ),
      customerType: _string(
        json['customerType'] ??
            json['customer_type'] ??
            json['accountCustomerType'] ??
            json['account_customer_type'],
      ),
      contactPhone: _string(
        json['contactPhone'] ??
            json['contact_phone'] ??
            json['accountContactPhone'] ??
            json['account_contact_phone'],
      ),
    );
  }
}

/// 门店应收回款流水记录 (WI-023 / v1.2.298)
class PosReceivableLedger {
  const PosReceivableLedger({
    required this.id,
    required this.ledgerNo,
    required this.claimId,
    required this.orderNo,
    required this.direction,
    required this.entryType,
    required this.amountFen,
    required this.channel,
    this.drawerSessionId,
    this.createdAt,
  });

  final int id;
  final String ledgerNo;
  final int claimId;
  final String orderNo;
  final String direction;
  final String entryType;
  final int amountFen;
  final String channel;
  final int? drawerSessionId;
  final DateTime? createdAt;

  double get amountYuan => amountFen / 100.0;

  factory PosReceivableLedger.fromJson(Map<String, Object?> json) {
    return PosReceivableLedger(
      id: _int(json['id']),
      ledgerNo: _string(json['ledgerNo'] ?? json['ledger_no']),
      claimId: _int(json['claimId'] ?? json['claim_id']),
      orderNo: _string(json['orderNo'] ?? json['order_no']),
      direction: _string(json['direction'] ?? 'CREDIT'),
      entryType: _string(
        json['entryType'] ?? json['entry_type'] ?? 'COLLECTION',
      ),
      amountFen: _int(json['amountFen'] ?? json['amount_fen']),
      channel: _string(json['channel'] ?? 'CASH'),
      drawerSessionId: _nullableInt(
        json['drawerSessionId'] ?? json['drawer_session_id'],
      ),
      createdAt: _dateTime(json['createdAt'] ?? json['created_at']),
    );
  }
}
