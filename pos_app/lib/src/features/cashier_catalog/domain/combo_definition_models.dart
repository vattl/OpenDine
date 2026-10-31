import 'cashier_dish.dart';

class ComboFixedItemModel {
  const ComboFixedItemModel({
    required this.componentDishId,
    this.qtyPerCombo = 1,
    this.sortOrder = 0,
    this.dishName = '',
    this.dishPrice = 0.0,
    this.dishImage,
  });

  final int componentDishId;
  final int qtyPerCombo;
  final int sortOrder;
  final String dishName;
  final double dishPrice;
  final String? dishImage;

  ComboFixedItemModel copyWith({
    int? componentDishId,
    int? qtyPerCombo,
    int? sortOrder,
    String? dishName,
    double? dishPrice,
    String? dishImage,
  }) {
    return ComboFixedItemModel(
      componentDishId: componentDishId ?? this.componentDishId,
      qtyPerCombo: qtyPerCombo ?? this.qtyPerCombo,
      sortOrder: sortOrder ?? this.sortOrder,
      dishName: dishName ?? this.dishName,
      dishPrice: dishPrice ?? this.dishPrice,
      dishImage: dishImage ?? this.dishImage,
    );
  }

  ComboFixedItemModel attachDishInfo(CashierDish dish) {
    return copyWith(
      dishName: dish.name,
      dishPrice: dish.price,
      dishImage: dish.image,
    );
  }

  Map<String, Object?> toJson() => {
    'componentDishId': componentDishId,
    'qtyPerCombo': qtyPerCombo,
    'sortOrder': sortOrder,
  };

  factory ComboFixedItemModel.fromJson(Map<String, Object?> json) {
    final dishId = _asInt(json['componentDishId'] ?? json['component_dish_id']);
    final qty = _asInt(json['qtyPerCombo'] ?? json['qty_per_combo']) ?? 1;
    final sort = _asInt(json['sortOrder'] ?? json['sort_order']) ?? 0;
    final name = (json['dishName'] ?? json['name'] ?? '').toString();
    final price =
        _asDouble(json['dishPrice'] ?? json['unitprice'] ?? json['price']) ??
        0.0;
    final img = json['dishImage'] ?? json['image'];

    return ComboFixedItemModel(
      componentDishId: dishId ?? 0,
      qtyPerCombo: qty > 0 ? qty : 1,
      sortOrder: sort,
      dishName: name,
      dishPrice: price,
      dishImage: img?.toString(),
    );
  }
}

class ComboGroupItemModel {
  const ComboGroupItemModel({
    required this.componentDishId,
    this.extraPrice = 0.0,
    this.sortOrder = 0,
    this.dishName = '',
    this.dishPrice = 0.0,
    this.dishImage,
  });

  final int componentDishId;
  final double extraPrice;
  final int sortOrder;
  final String dishName;
  final double dishPrice;
  final String? dishImage;

  ComboGroupItemModel copyWith({
    int? componentDishId,
    double? extraPrice,
    int? sortOrder,
    String? dishName,
    double? dishPrice,
    String? dishImage,
  }) {
    return ComboGroupItemModel(
      componentDishId: componentDishId ?? this.componentDishId,
      extraPrice: extraPrice ?? this.extraPrice,
      sortOrder: sortOrder ?? this.sortOrder,
      dishName: dishName ?? this.dishName,
      dishPrice: dishPrice ?? this.dishPrice,
      dishImage: dishImage ?? this.dishImage,
    );
  }

  ComboGroupItemModel attachDishInfo(CashierDish dish) {
    return copyWith(
      dishName: dish.name,
      dishPrice: dish.price,
      dishImage: dish.image,
    );
  }

  Map<String, Object?> toJson() => {
    'componentDishId': componentDishId,
    'extraPrice': extraPrice,
    'sortOrder': sortOrder,
  };

  factory ComboGroupItemModel.fromJson(Map<String, Object?> json) {
    final dishId = _asInt(json['componentDishId'] ?? json['component_dish_id']);
    final extra = _asDouble(json['extraPrice'] ?? json['extra_price']) ?? 0.0;
    final sort = _asInt(json['sortOrder'] ?? json['sort_order']) ?? 0;
    final name = (json['dishName'] ?? json['name'] ?? '').toString();
    final price =
        _asDouble(json['dishPrice'] ?? json['unitprice'] ?? json['price']) ??
        0.0;
    final img = json['dishImage'] ?? json['image'];

    return ComboGroupItemModel(
      componentDishId: dishId ?? 0,
      extraPrice: extra,
      sortOrder: sort,
      dishName: name,
      dishPrice: price,
      dishImage: img?.toString(),
    );
  }
}

class ComboGroupModel {
  const ComboGroupModel({
    required this.groupKey,
    required this.title,
    this.minPick = 1,
    this.maxPick = 1,
    this.sortOrder = 0,
    this.items = const [],
  });

  final String groupKey;
  final String title;
  final int minPick;
  final int maxPick;
  final int sortOrder;
  final List<ComboGroupItemModel> items;

  ComboGroupModel copyWith({
    String? groupKey,
    String? title,
    int? minPick,
    int? maxPick,
    int? sortOrder,
    List<ComboGroupItemModel>? items,
  }) {
    return ComboGroupModel(
      groupKey: groupKey ?? this.groupKey,
      title: title ?? this.title,
      minPick: minPick ?? this.minPick,
      maxPick: maxPick ?? this.maxPick,
      sortOrder: sortOrder ?? this.sortOrder,
      items: items ?? this.items,
    );
  }

  Map<String, Object?> toJson() => {
    'groupKey': groupKey,
    'title': title.trim(),
    'minPick': minPick,
    'maxPick': maxPick,
    'sortOrder': sortOrder,
    'items': items.map((e) => e.toJson()).toList(),
  };

  factory ComboGroupModel.fromJson(Map<String, Object?> json) {
    final itemsRaw = json['items'];
    final itemsList = itemsRaw is List
        ? itemsRaw
              .whereType<Map>()
              .map(
                (e) => ComboGroupItemModel.fromJson(e.cast<String, Object?>()),
              )
              .toList()
        : <ComboGroupItemModel>[];

    return ComboGroupModel(
      groupKey: (json['groupKey'] ?? json['group_key'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      minPick: _asInt(json['minPick'] ?? json['min_pick']) ?? 1,
      maxPick: _asInt(json['maxPick'] ?? json['max_pick']) ?? 1,
      sortOrder: _asInt(json['sortOrder'] ?? json['sort_order']) ?? 0,
      items: itemsList,
    );
  }
}

class ComboMenuDefinitionModel {
  const ComboMenuDefinitionModel({
    this.comboId,
    required this.dishId,
    this.comboType = 'groups',
    this.status = 1,
    this.fixedItems = const [],
    this.groups = const [],
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

  final int? comboId;
  final int dishId;
  final String comboType; // 'groups' | 'fixed'
  final int status; // 0 | 1
  final List<ComboFixedItemModel> fixedItems;
  final List<ComboGroupModel> groups;
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

  bool get isFixedOnly => comboType == 'fixed';

  ComboMenuDefinitionModel copyWith({
    int? comboId,
    int? dishId,
    String? comboType,
    int? status,
    List<ComboFixedItemModel>? fixedItems,
    List<ComboGroupModel>? groups,
    int? limitPerOrder,
    int? limitPerUser,
    String? limitCycle,
    String? startTime,
    String? endTime,
    String? availableDays,
    String? timeRangeStart,
    String? timeRangeEnd,
    String? applyDiningType,
    bool? allowCoupon,
    int? dailyStock,
  }) {
    return ComboMenuDefinitionModel(
      comboId: comboId ?? this.comboId,
      dishId: dishId ?? this.dishId,
      comboType: comboType ?? this.comboType,
      status: status ?? this.status,
      fixedItems: fixedItems ?? this.fixedItems,
      groups: groups ?? this.groups,
      limitPerOrder: limitPerOrder ?? this.limitPerOrder,
      limitPerUser: limitPerUser ?? this.limitPerUser,
      limitCycle: limitCycle ?? this.limitCycle,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      availableDays: availableDays ?? this.availableDays,
      timeRangeStart: timeRangeStart ?? this.timeRangeStart,
      timeRangeEnd: timeRangeEnd ?? this.timeRangeEnd,
      applyDiningType: applyDiningType ?? this.applyDiningType,
      allowCoupon: allowCoupon ?? this.allowCoupon,
      dailyStock: dailyStock ?? this.dailyStock,
    );
  }

  factory ComboMenuDefinitionModel.fromJson(
    Map<String, Object?> json, {
    int? fallbackDishId,
  }) {
    final fixedRaw = json['fixedItems'] ?? json['fixed_items'];
    final fixedList = fixedRaw is List
        ? fixedRaw
              .whereType<Map>()
              .map(
                (e) => ComboFixedItemModel.fromJson(e.cast<String, Object?>()),
              )
              .toList()
        : <ComboFixedItemModel>[];

    final groupsRaw = json['groups'];
    final groupsList = groupsRaw is List
        ? groupsRaw
              .whereType<Map>()
              .map((e) => ComboGroupModel.fromJson(e.cast<String, Object?>()))
              .toList()
        : <ComboGroupModel>[];

    final dishId =
        _asInt(json['dishId'] ?? json['dish_id']) ?? fallbackDishId ?? 0;
    final comboId = _asInt(json['comboId'] ?? json['combo_id'] ?? json['id']);
    final comboType = (json['comboType'] ?? json['combo_type'] ?? 'groups')
        .toString();
    final status = _asInt(json['status']) ?? 1;

    return ComboMenuDefinitionModel(
      comboId: comboId,
      dishId: dishId,
      comboType: comboType,
      status: status,
      fixedItems: fixedList,
      groups: groupsList,
      limitPerOrder: _asInt(json['limitPerOrder'] ?? json['limit_per_order']),
      limitPerUser: _asInt(json['limitPerUser'] ?? json['limit_per_user']),
      limitCycle: (json['limitCycle'] ?? json['limit_cycle'] ?? 'daily')
          .toString(),
      startTime: _asNullableString(json['startTime'] ?? json['start_time']),
      endTime: _asNullableString(json['endTime'] ?? json['end_time']),
      availableDays: _asNullableString(
        json['availableDays'] ?? json['available_days'],
      ),
      timeRangeStart: _asNullableString(
        json['timeRangeStart'] ?? json['time_range_start'],
      ),
      timeRangeEnd: _asNullableString(
        json['timeRangeEnd'] ?? json['time_range_end'],
      ),
      applyDiningType:
          (json['applyDiningType'] ?? json['apply_dining_type'] ?? 'all')
              .toString(),
      allowCoupon:
          (_asInt(json['allowCoupon'] ?? json['allow_coupon']) ?? 1) != 0,
      dailyStock: _asInt(json['dailyStock'] ?? json['daily_stock']),
    );
  }
}

class ComboSaveRequest {
  const ComboSaveRequest({
    required this.dishId,
    this.comboType = 'groups',
    this.status = 1,
    this.fixedItems = const [],
    this.groups = const [],
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

  final int dishId;
  final String comboType; // 'groups' | 'fixed'
  final int status; // 0 | 1
  final List<ComboFixedItemModel> fixedItems;
  final List<ComboGroupModel> groups;
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

  Map<String, Object?> toJson() => {
    'dishId': dishId,
    'comboType': comboType,
    'status': status,
    'fixedItems': fixedItems.map((e) => e.toJson()).toList(),
    'groups': comboType == 'fixed'
        ? <Map<String, Object?>>[]
        : groups.map((e) => e.toJson()).toList(),
    'limitPerOrder': limitPerOrder,
    'limitPerUser': limitPerUser,
    'limitCycle': limitCycle,
    'startTime': startTime,
    'endTime': endTime,
    'availableDays': availableDays,
    'timeRangeStart': timeRangeStart,
    'timeRangeEnd': timeRangeEnd,
    'applyDiningType': applyDiningType,
    'allowCoupon': allowCoupon ? 1 : 0,
    'dailyStock': dailyStock,
  };
}

class ComboDetailResponse {
  const ComboDetailResponse({
    this.combo,
    this.definition,
    this.forAdmin = false,
  });

  final Map<String, Object?>? combo;
  final ComboMenuDefinitionModel? definition;
  final bool forAdmin;

  factory ComboDetailResponse.fromJson(
    Map<String, Object?> json, {
    int? fallbackDishId,
  }) {
    final comboMap = json['combo'] is Map
        ? (json['combo'] as Map).cast<String, Object?>()
        : null;
    final defMap = json['definition'] is Map
        ? (json['definition'] as Map).cast<String, Object?>()
        : null;
    final forAdmin = json['forAdmin'] == true;

    ComboMenuDefinitionModel? definition;
    if (defMap != null) {
      definition = ComboMenuDefinitionModel.fromJson(
        defMap,
        fallbackDishId: fallbackDishId,
      );
    } else if (comboMap != null) {
      definition = ComboMenuDefinitionModel.fromJson(
        comboMap,
        fallbackDishId: fallbackDishId,
      );
    }

    return ComboDetailResponse(
      combo: comboMap,
      definition: definition,
      forAdmin: forAdmin,
    );
  }
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().trim());
}

double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

String? _asNullableString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}
