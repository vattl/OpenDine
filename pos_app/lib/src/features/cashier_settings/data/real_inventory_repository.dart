import '../../../core/admin_api_client.dart';
import '../../../core/api_contract.dart';
import '../domain/inventory_models.dart';
import 'inventory_repository.dart';

/// 库存操作仓库实现（基于运营后台 inventory 端点，X-Shop-Id 由 client 注入）。
class RealInventoryRepository implements InventoryRepository {
  const RealInventoryRepository(this.client);

  final AdminApiClient client;

  @override
  Future<List<InventoryPurchase>> listPurchases({
    String? status,
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await client.get(
      settingsInventoryPurchasesEndpoint,
      query: {
        if (status != null && status.trim().isNotEmpty) 'status': status,
        'page': page,
        'pageSize': pageSize,
      },
    );
    return extractInventoryList(response)
        .map(InventoryPurchase.fromJson)
        .toList(growable: false);
  }

  @override
  Future<InventoryPurchase> createPurchase({
    required int supplierId,
    required int warehouseId,
    required List<Map<String, Object?>> items,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('items must not be empty');
    }
    final response = await client.post(
      settingsInventoryPurchaseSaveEndpoint,
      body: {
        'supplierId': supplierId,
        'warehouseId': warehouseId,
        'items': items,
      },
    );
    final map = _objectMap(response);
    if (map.isEmpty && response is Map) {
      // 服务端可能直接回显单据（含 id/status）。
      return InventoryPurchase.fromJson(response.cast<String, Object?>());
    }
    return InventoryPurchase.fromJson(map);
  }

  @override
  Future<void> updatePurchaseStatus({
    required int id,
    required String action,
    String? reason,
  }) async {
    await client.put(
      settingsInventoryPurchaseUpdateEndpoint,
      body: {
        'id': id,
        'action': action,
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason,
      },
    );
  }

  @override
  Future<List<InventoryTransfer>> listTransfers({String? status}) async {
    final response = await client.get(
      settingsInventoryTransfersEndpoint,
      query: {
        if (status != null && status.trim().isNotEmpty) 'status': status,
      },
    );
    return extractInventoryList(response)
        .map(InventoryTransfer.fromJson)
        .toList(growable: false);
  }

  @override
  Future<InventoryTransfer> receiveTransfer({required int id}) async {
    final response = await client.put(settingsInventoryTransferReceiveEndpoint(id));
    final map = _objectMap(response);
    if (map.isEmpty && response is Map) {
      return InventoryTransfer.fromJson(response.cast<String, Object?>());
    }
    return InventoryTransfer.fromJson(map);
  }

  @override
  Future<List<InventoryBom>> listBoms({int? dishId}) async {
    final response = await client.get(
      settingsInventoryBomsEndpoint,
      query: {
        if (dishId != null) 'dishId': dishId,
      },
    );
    return extractInventoryList(response)
        .map(InventoryBom.fromJson)
        .toList(growable: false);
  }

  @override
  Future<InventoryBom> activateBom({required int id}) async {
    final response =
        await client.put(settingsInventoryBomActivateEndpoint(id));
    final map = _objectMap(response);
    if (map.isEmpty && response is Map) {
      return InventoryBom.fromJson(response.cast<String, Object?>());
    }
    return InventoryBom.fromJson(map);
  }

  @override
  Future<List<InventorySupplier>> listSuppliers({String? keyword}) async {
    final response = await client.get(
      settingsInventorySuppliersEndpoint,
      query: {
        if (keyword != null && keyword.trim().isNotEmpty) 'keyword': keyword,
      },
    );
    return extractInventoryList(response)
        .map(InventorySupplier.fromJson)
        .toList(growable: false);
  }

  @override
  Future<InventorySupplier> addSupplier(InventorySupplier supplier) async {
    if (supplier.name.trim().isEmpty) {
      throw ArgumentError('supplier name must not be empty');
    }
    final response = await client.post(
      settingsInventorySupplierSaveEndpoint,
      body: supplier.toSaveJson(),
    );
    return _supplierFrom(response, supplier);
  }

  @override
  Future<InventorySupplier> updateSupplier(
    InventorySupplier supplier,
  ) async {
    if (supplier.id == 0) throw ArgumentError('supplier id required');
    final response = await client.put(
      settingsInventorySupplierUpdateEndpoint,
      body: supplier.toSaveJson(includeId: true),
    );
    return _supplierFrom(response, supplier);
  }

  @override
  Future<void> deleteSupplier({required int id}) async {
    await client.delete(
      settingsInventorySupplierDeleteEndpoint,
      query: {'id': id},
    );
  }

  @override
  Future<List<InventoryWarehouse>> listWarehouses({String? keyword}) async {
    final response = await client.get(
      settingsInventoryWarehousesEndpoint,
      query: {
        if (keyword != null && keyword.trim().isNotEmpty) 'keyword': keyword,
      },
    );
    return extractInventoryList(response)
        .map(InventoryWarehouse.fromJson)
        .toList(growable: false);
  }

  @override
  Future<InventoryWarehouse> addWarehouse(
    InventoryWarehouse warehouse,
  ) async {
    if (warehouse.name.trim().isEmpty ||
        warehouse.legalEntity.trim().isEmpty) {
      throw ArgumentError('warehouse name and legalEntity required');
    }
    final response = await client.post(
      settingsInventoryWarehouseSaveEndpoint,
      body: warehouse.toSaveJson(),
    );
    return _warehouseFrom(response, warehouse);
  }

  @override
  Future<InventoryWarehouse> updateWarehouse(
    InventoryWarehouse warehouse,
  ) async {
    if (warehouse.id == 0) throw ArgumentError('warehouse id required');
    final response = await client.put(
      settingsInventoryWarehouseUpdateEndpoint,
      body: warehouse.toSaveJson(includeId: true),
    );
    return _warehouseFrom(response, warehouse);
  }

  @override
  Future<InventoryBom> createBom({
    required int dishId,
    required List<Map<String, Object?>> items,
    String? effectiveFrom,
  }) async {
    if (items.isEmpty) throw ArgumentError('bom items must not be empty');
    final response = await client.post(
      settingsInventoryBomSaveEndpoint,
      body: {
        'dishId': dishId,
        'items': items,
        if (effectiveFrom != null && effectiveFrom.trim().isNotEmpty)
          'effectiveFrom': effectiveFrom,
      },
    );
    return _bomFrom(response);
  }

  @override
  Future<InventoryBom> updateBom({
    required int id,
    required int dishId,
    required List<Map<String, Object?>> items,
    String? effectiveFrom,
  }) async {
    if (items.isEmpty) throw ArgumentError('bom items must not be empty');
    final response = await client.put(
      settingsInventoryBomUpdateEndpoint,
      body: {
        'id': id,
        'dishId': dishId,
        'items': items,
        if (effectiveFrom != null && effectiveFrom.trim().isNotEmpty)
          'effectiveFrom': effectiveFrom,
      },
    );
    return _bomFrom(response);
  }

  @override
  Future<InventoryTransfer> createTransfer({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<Map<String, Object?>> items,
  }) async {
    if (fromWarehouseId == toWarehouseId) {
      throw ArgumentError('from and to warehouse must differ');
    }
    if (items.isEmpty) throw ArgumentError('transfer items must not be empty');
    final response = await client.post(
      settingsInventoryTransferSaveEndpoint,
      body: {
        'fromWarehouseId': fromWarehouseId,
        'toWarehouseId': toWarehouseId,
        'items': items,
      },
    );
    final map = _objectMap(response);
    if (map.isEmpty && response is Map) {
      return InventoryTransfer.fromJson(response.cast<String, Object?>());
    }
    return InventoryTransfer.fromJson(map);
  }

  @override
  Future<List<InventoryBatch>> listBatches({
    int? materialId,
    int? warehouseId,
  }) async {
    final response = await client.get(
      settingsInventoryBatchesEndpoint,
      query: {
        if (materialId != null) 'material_id': materialId,
        if (warehouseId != null) 'warehouse_id': warehouseId,
      },
    );
    return extractInventoryList(response)
        .map(InventoryBatch.fromJson)
        .toList(growable: false);
  }
}

InventorySupplier _supplierFrom(Object? response, InventorySupplier fallback) {
  final map = _objectMap(response);
  if (map.isEmpty && response is Map) {
    return InventorySupplier.fromJson(response.cast<String, Object?>());
  }
  if (map.isEmpty) return fallback;
  return InventorySupplier.fromJson(map);
}

InventoryWarehouse _warehouseFrom(
  Object? response,
  InventoryWarehouse fallback,
) {
  final map = _objectMap(response);
  if (map.isEmpty && response is Map) {
    return InventoryWarehouse.fromJson(response.cast<String, Object?>());
  }
  if (map.isEmpty) return fallback;
  return InventoryWarehouse.fromJson(map);
}

InventoryBom _bomFrom(Object? response) {
  final map = _objectMap(response);
  if (map.isEmpty && response is Map) {
    return InventoryBom.fromJson(response.cast<String, Object?>());
  }
  return InventoryBom.fromJson(map);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  return const {};
}
