import 'dart:convert';

class CashierDishCategory {
  const CashierDishCategory({
    required this.id,
    required this.name,
    this.code = '',
    this.sorting = 0,
  });

  final int id;
  final String name;
  final String code;
  final int sorting;

  String get key => id > 0 ? 'id:$id' : 'cid:$code';

  factory CashierDishCategory.fromJson(Map<String, Object?> json) {
    return CashierDishCategory(
      id: _int(json['id'] ?? json['value']),
      name: _string(json['name'] ?? json['label'] ?? json['value']),
      code: _string(json['cid'] ?? json['value'] ?? json['id']),
      sorting: _int(json['sorting'] ?? json['sort']),
    );
  }

  bool matches(CashierDish dish) {
    final normalizedCode = code.trim();
    final normalizedName = name.trim();
    return (id > 0 && dish.typeId == id) ||
        (normalizedCode.isNotEmpty && dish.categoryCode == normalizedCode) ||
        (id > 0 && dish.categoryCode == id.toString()) ||
        (normalizedCode.isNotEmpty && normalizedCode == dish.typeId.toString()) ||
        (normalizedName.isNotEmpty &&
            dish.categoryName.isNotEmpty &&
            normalizedName == dish.categoryName.trim());
  }
}

enum CashierDishAvailability { sufficient, lowStock, soldOut }

class CashierDish {
  const CashierDish({
    required this.id,
    required this.name,
    required this.specification,
    required this.price,
    required this.unit,
    required this.stock,
    required this.onSale,
    required this.soldOut,
    required this.typeId,
    this.categoryCode = '',
    this.categoryName = '',
    this.image = '',
    this.sorting = 0,
    this.quantity = 0,
    this.servingDurationMinutes = 10,
  });

  final int id;
  final String name;
  final String specification;
  final double price;
  final String unit;
  final int? stock;
  final bool onSale;
  final bool soldOut;
  final int typeId;
  final String categoryCode;
  final String categoryName;
  final String image;
  final int sorting;
  final int quantity;
  final int servingDurationMinutes;

  bool get unavailable => !onSale || soldOut;

  CashierDishAvailability get availability {
    if (unavailable) return CashierDishAvailability.soldOut;
    final value = stock;
    if (value != null && value > 0 && value <= 5) {
      return CashierDishAvailability.lowStock;
    }
    return CashierDishAvailability.sufficient;
  }

  String get availabilityLabel => switch (availability) {
    CashierDishAvailability.sufficient => '库存充足',
    CashierDishAvailability.lowStock => '快售罄',
    CashierDishAvailability.soldOut => onSale ? '已售罄' : '已下架',
  };

  String get stockLabel {
    if (unavailable) return onSale ? '已售罄' : '已下架';
    final value = stock;
    return value == null || value <= 0 ? '不限量' : '剩余 $value';
  }

  factory CashierDish.fromJson(Map<String, Object?> json) {
    final type = json['type'] is Map
        ? (json['type'] as Map).cast<String, Object?>()
        : json['category'] is Map
        ? (json['category'] as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final categoryName = _string(
      json['category_name'] ??
          json['categoryName'] ??
          json['typeName'] ??
          json['type_name'] ??
          type['label'] ??
          type['name'] ??
          type['value'],
    );
    return CashierDish(
      id: _int(json['id']),
      name: _string(json['name']),
      specification: _string(json['specification']),
      price: _double(json['unitprice'] ?? json['unit_price'] ?? json['price']),
      unit: _string(json['unit']).isEmpty ? '份' : _string(json['unit']),
      stock: _nullableInt(json['stock']),
      onSale: _bool(json['onsale'], fallback: true),
      soldOut: _bool(json['sold_out'] ?? json['soldOut']),
      typeId: _int(
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
      categoryName: categoryName,
      image: _string(json['image']),
      sorting: _int(json['sorting']),
      quantity: _int(json['quantity']),
      servingDurationMinutes: _nullableInt(
            json['serving_duration_minutes'] ?? json['servingDurationMinutes'],
          ) ??
          10,
    );
  }

  CashierDish copyWith({
    bool? soldOut,
    int? stock,
    String? categoryName,
    String? categoryCode,
    int? typeId,
  }) => CashierDish(
    id: id,
    name: name,
    specification: specification,
    price: price,
    unit: unit,
    stock: stock ?? this.stock,
    onSale: onSale,
    soldOut: soldOut ?? this.soldOut,
    typeId: typeId ?? this.typeId,
    categoryCode: categoryCode ?? this.categoryCode,
    categoryName: categoryName ?? this.categoryName,
    image: image,
    sorting: sorting,
    quantity: quantity,
    servingDurationMinutes: servingDurationMinutes,
  );

  CashierDishInput toInput({int? nextStock}) => CashierDishInput(
    id: id,
    name: name,
    specification: specification,
    price: price,
    unit: unit,
    stock: nextStock ?? stock,
    onSale: onSale,
    soldOut: soldOut,
    typeId: typeId,
    image: image,
    sorting: sorting,
    quantity: quantity,
  );
}

class CashierDishInput {
  const CashierDishInput({
    this.id,
    required this.name,
    required this.specification,
    required this.price,
    required this.unit,
    required this.stock,
    required this.onSale,
    required this.soldOut,
    required this.typeId,
    this.image = '',
    this.sorting = 0,
    this.quantity = 0,
    this.servingDurationMinutes = 10,
  });

  final int? id;
  final String name;
  final String specification;
  final double price;
  final String unit;
  final int? stock;
  final bool onSale;
  final bool soldOut;
  final int typeId;
  final String image;
  final int sorting;
  final int quantity;
  final int servingDurationMinutes;

  Map<String, Object?> toJson() {
    final effectiveSoldOut = stock != null && stock! > 0 ? false : soldOut;
    return {
      if (id != null) 'id': id,
      'name': name.trim(),
      'typeId': typeId,
      'unitprice': price,
      'unit': unit.trim(),
      'stock': stock ?? -1,
      'onsale': onSale,
      'sold_out': effectiveSoldOut ? 1 : 0,
      'specification': specification.trim(),
      'image': image.trim(),
      'sorting': sorting,
      'quantity': quantity,
      'serving_duration_minutes': servingDurationMinutes,
    };
  }
}

class CashierDishSpecificationGroup {
  const CashierDishSpecificationGroup({
    required this.label,
    required this.options,
  });

  final String label;
  final List<String> options;
}

List<CashierDishSpecificationGroup> parseCashierDishSpecifications(String raw) {
  final source = raw.trim();
  if (source.isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is Map) {
      return decoded.entries
          .map(
            (entry) => CashierDishSpecificationGroup(
              label: '${entry.key}'.trim(),
              options: _specificationOptions(entry.value),
            ),
          )
          .where((group) => group.label.isNotEmpty && group.options.isNotEmpty)
          .toList(growable: false);
    }
    if (decoded is List) {
      final options = _specificationOptions(decoded);
      return options.isEmpty
          ? const []
          : [CashierDishSpecificationGroup(label: '规格', options: options)];
    }
  } on FormatException {
    if (source.startsWith('{') || source.startsWith('[')) return const [];
    final options = source
        .split(RegExp(r'[,，/]'))
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toList(growable: false);
    return options.isEmpty
        ? const []
        : [CashierDishSpecificationGroup(label: '规格', options: options)];
  }
  return const [];
}

String encodeCashierDishSpecifications(
  Iterable<CashierDishSpecificationGroup> groups,
) {
  final result = <String, List<String>>{};
  for (final group in groups) {
    final label = group.label.trim();
    final options = group.options
        .map((option) => option.trim())
        .where((option) => option.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (label.isNotEmpty && options.isNotEmpty) result[label] = options;
  }
  return result.isEmpty ? '' : jsonEncode(result);
}

class CashierDishPage {
  const CashierDishPage({required this.items, required this.total});

  final List<CashierDish> items;
  final int total;
}

/// 合并接口分类列表与菜品中内嵌的分类元数据，确保即便分类列表缺少某些类目或有门店覆盖分类，
/// 也绝不会导致“分类丢失 / 没识别出来”。
List<CashierDishCategory> mergeCashierCategoriesWithDishes({
  required Iterable<CashierDishCategory> categories,
  required Iterable<CashierDish> dishes,
}) {
  final result = <CashierDishCategory>[...categories];
  final existingIds = <int>{for (final c in result) if (c.id > 0) c.id};
  final existingCodes = <String>{
    for (final c in result)
      if (c.code.trim().isNotEmpty) c.code.trim().toLowerCase(),
  };
  final existingNames = <String>{
    for (final c in result)
      if (c.name.trim().isNotEmpty) c.name.trim().toLowerCase(),
  };
  // 服务端 sorting 是 1 起的连续位置值（拖拽 targetIndex 即目标 sorting），
  // 聚合补全的分类沿用「现有最大 sorting + 1」，保持连续并兼容拖拽排序。
  var maxSorting = result.fold<int>(0, (max, c) => c.sorting > max ? c.sorting : max);

  for (final dish in dishes) {
    final typeId = dish.typeId;
    final code = dish.categoryCode.trim();
    final name = dish.categoryName.trim();

    final matchesAny = result.any((category) => category.matches(dish));
    if (matchesAny) continue;

    // 若当前菜品所属分类在列表中未找到，则自动补全该分类
    final resolvedName = name.isNotEmpty
        ? name
        : (code.isNotEmpty ? code : (typeId > 0 ? '分类 $typeId' : '未命名分类'));
    final resolvedId = typeId > 0 ? typeId : 0;
    final resolvedCode = code.isNotEmpty ? code : (resolvedId > 0 ? '$resolvedId' : '');

    final idExists = resolvedId > 0 && existingIds.contains(resolvedId);
    final nameExists = existingNames.contains(resolvedName.toLowerCase());
    if (idExists || nameExists) continue;

    final newCategory = CashierDishCategory(
      id: resolvedId,
      name: resolvedName,
      code: resolvedCode,
      sorting: maxSorting + 1,
    );
    result.add(newCategory);
    maxSorting = newCategory.sorting;
    if (resolvedId > 0) existingIds.add(resolvedId);
    if (resolvedCode.isNotEmpty) existingCodes.add(resolvedCode.toLowerCase());
    existingNames.add(resolvedName.toLowerCase());
  }

  return result..sort((a, b) => a.sorting.compareTo(b.sorting));
}

String _string(Object? value) => value == null ? '' : '$value'.trim();

int _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

int? _nullableInt(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

double _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('$value') ?? 0;
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

List<String> _specificationOptions(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is Map) return _string(item['name'] ?? item['label']);
        return _string(item);
      })
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
