/// 库存域模型（M-E 库存增强）：采购单、调拨单、BOM 版本。
/// 字段按 openapi v1.2.278 定义，解析对 snake_case 与 camelCase 双形态容错。
import 'dart:convert';

/// 供应商（列表行/编辑对象）。settlementInfo 仅 inventory:manage 可见。
class InventorySupplier {
  const InventorySupplier({
    required this.id,
    required this.name,
    this.contactName,
    this.contactPhone,
    this.supplyScope,
    this.settlementInfo,
  });

  final int id;
  final String name;
  final String? contactName;
  final String? contactPhone;
  final String? supplyScope;
  final String? settlementInfo;

  static InventorySupplier fromJson(Map<String, Object?> json) => InventorySupplier(
        id: _int(json['id']) ?? 0,
        name: _str(json, 'name') ?? '',
        contactName: _str(json, 'contactName') ?? _str(json, 'contact_name'),
        contactPhone: _str(json, 'contactPhone') ?? _str(json, 'contact_phone'),
        supplyScope: _str(json, 'supplyScope') ?? _str(json, 'supply_scope'),
        settlementInfo: _str(json, 'settlementInfo') ?? _str(json, 'settlement_info'),
      );

  Map<String, Object?> toSaveJson({bool includeId = false}) => {
        if (includeId) 'id': id,
        'name': name,
        if (contactName != null && contactName!.isNotEmpty) 'contactName': contactName,
        if (contactPhone != null && contactPhone!.isNotEmpty)
          'contactPhone': contactPhone,
        if (supplyScope != null && supplyScope!.isNotEmpty)
          'supplyScope': supplyScope,
        if (settlementInfo != null && settlementInfo!.isNotEmpty)
          'settlementInfo': settlementInfo,
      };
}

/// 仓库（列表行/编辑对象）。legalEntity 为经营主体（调拨禁止跨主体）。
class InventoryWarehouse {
  const InventoryWarehouse({
    required this.id,
    required this.name,
    required this.legalEntity,
    this.address,
  });

  final int id;
  final String name;
  final String legalEntity;
  final String? address;

  static InventoryWarehouse fromJson(Map<String, Object?> json) =>
      InventoryWarehouse(
        id: _int(json['id']) ?? 0,
        name: _str(json, 'name') ?? '',
        legalEntity: _str(json, 'legalEntity') ?? _str(json, 'legal_entity') ?? '',
        address: _str(json, 'address'),
      );

  Map<String, Object?> toSaveJson({bool includeId = false}) => {
        if (includeId) 'id': id,
        'name': name,
        'legalEntity': legalEntity,
        if (address != null && address!.isNotEmpty) 'address': address,
      };
}

/// 库存批次（列表行，FEFO 按到期日升序）。
class InventoryBatch {
  const InventoryBatch({
    required this.id,
    this.batchNo,
    this.materialId,
    this.materialName,
    this.warehouseId,
    this.qty = 0,
    this.expiryDate,
    this.available,
  });

  final int id;
  final String? batchNo;
  final int? materialId;
  final String? materialName;
  final int? warehouseId;
  final double qty;
  final String? expiryDate;
  final double? available;

  static InventoryBatch fromJson(Map<String, Object?> json) => InventoryBatch(
        id: _int(json['id']) ?? 0,
        batchNo: _str(json, 'batchNo') ?? _str(json, 'batch_no'),
        materialId: _int(json['materialId']) ?? _int(json['material_id']),
        materialName: _str(json, 'materialName') ?? _str(json, 'material_name'),
        warehouseId: _int(json['warehouseId']) ?? _int(json['warehouse_id']),
        qty: _num(json['qty']) ?? 0,
        expiryDate: _str(json, 'expiryDate') ?? _str(json, 'expiry_date'),
        available: _num(json['available']),
      );
}

/// 采购单明细行（创建采购单请求项）。
class InventoryPurchaseItem {
  const InventoryPurchaseItem({
    required this.materialId,
    required this.qty,
    required this.price,
  });

  final int materialId;
  final double qty;
  final double price;

  Map<String, Object?> toJson() => {
        'materialId': materialId,
        'qty': qty,
        'price': price,
      };
}

/// 采购单（列表行/创建结果）。status: DRAFT/PENDING_REVIEW/APPROVED/REJECTED/RECEIVED。
class InventoryPurchase {
  const InventoryPurchase({
    required this.id,
    required this.status,
    this.supplierId,
    this.supplierName,
    this.warehouseId,
    this.warehouseName,
    this.itemCount = 0,
    this.totalAmount = 0,
    this.reason,
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final String status;
  final int? supplierId;
  final String? supplierName;
  final int? warehouseId;
  final String? warehouseName;
  final int itemCount;
  final double totalAmount;
  final String? reason;
  final String? createdAt;
  final String? updatedAt;

  static InventoryPurchase fromJson(Map<String, Object?> json) {
    final rawItems = _extractList(json['items']) ?? const [];
    var itemCount = 0;
    var totalAmount = 0.0;
    for (final row in rawItems) {
      itemCount += 1;
      totalAmount +=
          (_num(row['qty']) ?? 0) * (_num(row['price']) ?? 0);
    }
    if (itemCount == 0 && json.containsKey('itemCount')) {
      itemCount = _int(json['itemCount']) ?? 0;
    }
    if (totalAmount == 0 && json.containsKey('totalAmount')) {
      totalAmount = _num(json['totalAmount']) ?? 0;
    }
    return InventoryPurchase(
      id: _int(json['id']) ?? 0,
      status: _str(json, 'status') ?? 'DRAFT',
      supplierId: _int(json['supplierId']) ?? _int(json['supplier_id']),
      supplierName: _str(json, 'supplierName') ?? _str(json, 'supplier_name'),
      warehouseId: _int(json['warehouseId']) ?? _int(json['warehouse_id']),
      warehouseName: _str(json, 'warehouseName') ?? _str(json, 'warehouse_name'),
      itemCount: itemCount,
      totalAmount: totalAmount,
      reason: _str(json, 'reason'),
      createdAt: _str(json, 'createdAt') ?? _str(json, 'created_at'),
      updatedAt: _str(json, 'updatedAt') ?? _str(json, 'updated_at'),
    );
  }
}

/// 调拨单（列表行/收货结果）。status: OUTBOUND/IN_TRANSIT/RECEIVED。
class InventoryTransfer {
  const InventoryTransfer({
    required this.id,
    required this.status,
    this.fromWarehouseId,
    this.fromWarehouseName,
    this.toWarehouseId,
    this.toWarehouseName,
    this.materialId,
    this.materialName,
    this.qty = 0,
    this.batchNo,
    this.createdAt,
  });

  final int id;
  final String status;
  final int? fromWarehouseId;
  final String? fromWarehouseName;
  final int? toWarehouseId;
  final String? toWarehouseName;
  final int? materialId;
  final String? materialName;
  final double qty;
  final String? batchNo;
  final String? createdAt;

  static InventoryTransfer fromJson(Map<String, Object?> json) {
    return InventoryTransfer(
      id: _int(json['id']) ?? 0,
      status: _str(json, 'status') ?? 'OUTBOUND',
      fromWarehouseId: _int(json['fromWarehouseId']),
      fromWarehouseName: _str(json, 'fromWarehouseName') ??
          _str(json, 'from_warehouse_name'),
      toWarehouseId: _int(json['toWarehouseId']),
      toWarehouseName: _str(json, 'toWarehouseName') ??
          _str(json, 'to_warehouse_name'),
      materialId: _int(json['materialId']),
      materialName: _str(json, 'materialName') ?? _str(json, 'material_name'),
      qty: _num(json['qty']) ?? 0,
      batchNo: _str(json, 'batchNo') ?? _str(json, 'batch_no'),
      createdAt: _str(json, 'createdAt') ?? _str(json, 'created_at'),
    );
  }
}

/// BOM 版本（列表行/激活结果）。status: DRAFT/ACTIVE/HISTORY。
class InventoryBom {
  const InventoryBom({
    required this.id,
    required this.dishId,
    required this.versionNo,
    required this.status,
    this.dishName,
    this.effectiveFrom,
    this.itemCount = 0,
    this.updatedAt,
  });

  final int id;
  final int dishId;
  final String versionNo;
  final String status;
  final String? dishName;
  final String? effectiveFrom;
  final int itemCount;
  final String? updatedAt;

  static InventoryBom fromJson(Map<String, Object?> json) {
    final rawItems =
        _extractList(json['itemsJson']) ?? _extractList(json['items']) ?? const [];
    return InventoryBom(
      id: _int(json['id']) ?? 0,
      dishId: _int(json['dishId']) ?? 0,
      versionNo: _str(json, 'versionNo') ?? _str(json, 'version_no') ?? 'v1',
      status: _str(json, 'status') ?? 'DRAFT',
      dishName: _str(json, 'dishName') ?? _str(json, 'dish_name'),
      effectiveFrom: _str(json, 'effectiveFrom') ?? _str(json, 'effective_from'),
      itemCount: rawItems.length,
      updatedAt: _str(json, 'updatedAt') ?? _str(json, 'updated_at'),
    );
  }
}

/// 从响应中提取列表：接受 `{items:[...]}`、`{data:[...]}` 或裸数组。
List<Map<String, Object?>> extractInventoryList(Object? response) {
  if (response is List) {
    return response
        .whereType<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList(growable: false);
  }
  if (response is Map) {
    final map = response.cast<String, Object?>();
    for (final key in const ['items', 'data', 'list', 'records']) {
      final raw = map[key];
      if (raw is List) {
        return raw
            .whereType<Map>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false);
      }
    }
  }
  return const [];
}

List<Map<String, Object?>>? _extractList(Object? value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((row) => row.cast<String, Object?>())
        .toList(growable: false);
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((row) => row.cast<String, Object?>())
            .toList(growable: false);
      }
    } catch (_) {
      // 忽略无法解析的 itemsJson 字符串。
    }
  }
  return null;
}

int? _int(Object? value) => value is int
    ? value
    : value is num
        ? value.toInt()
        : value is String
            ? int.tryParse(value)
            : null;

double? _num(Object? value) => value is num
    ? value.toDouble()
    : value is String
        ? double.tryParse(value)
        : null;

String? _str(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  return value is String ? value : '$value';
}
