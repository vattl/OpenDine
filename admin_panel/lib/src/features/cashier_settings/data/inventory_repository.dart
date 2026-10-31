import '../domain/inventory_models.dart';

/// 库存操作仓库（M-E 库存增强）。
/// 覆盖采购单（创建/审核/收货）、调拨收货、BOM 版本激活三类运营动作。
abstract interface class InventoryRepository {
  /// 采购单列表（status 可选过滤）。
  Future<List<InventoryPurchase>> listPurchases({
    String? status,
    int page = 1,
    int pageSize = 20,
  });

  /// 创建采购单（创建即 PENDING_REVIEW，进入审核流）。
  Future<InventoryPurchase> createPurchase({
    required int supplierId,
    required int warehouseId,
    required List<Map<String, Object?>> items,
  });

  /// 采购单状态流转：action = approve | reject | receive。
  Future<void> updatePurchaseStatus({
    required int id,
    required String action,
    String? reason,
  });

  /// 调拨单列表（status 可选过滤）。
  Future<List<InventoryTransfer>> listTransfers({String? status});

  /// 调拨收货（仅 IN_TRANSIT 可收货，目标仓生成新批次）。
  Future<InventoryTransfer> receiveTransfer({required int id});

  /// BOM 版本列表（dishId 可选过滤）。
  Future<List<InventoryBom>> listBoms({int? dishId});

  /// 激活 BOM 版本（同菜品仅一个 ACTIVE，原 ACTIVE 转 HISTORY）。
  Future<InventoryBom> activateBom({required int id});

  /// 供应商列表（keyword 可选过滤）。
  Future<List<InventorySupplier>> listSuppliers({String? keyword});

  /// 新增供应商（name 必填）。
  Future<InventorySupplier> addSupplier(InventorySupplier supplier);

  /// 更新供应商（body 必含 id）。
  Future<InventorySupplier> updateSupplier(InventorySupplier supplier);

  /// 删除供应商（DELETE ?id=）。
  Future<void> deleteSupplier({required int id});

  /// 仓库列表（keyword 可选过滤）。
  Future<List<InventoryWarehouse>> listWarehouses({String? keyword});

  /// 新增仓库（name/legalEntity 必填）。
  Future<InventoryWarehouse> addWarehouse(InventoryWarehouse warehouse);

  /// 更新仓库（body 必含 id）。
  Future<InventoryWarehouse> updateWarehouse(InventoryWarehouse warehouse);

  /// 新建 BOM 版本（version_no 自动递增；dishId/items 必填）。
  Future<InventoryBom> createBom({
    required int dishId,
    required List<Map<String, Object?>> items,
    String? effectiveFrom,
  });

  /// 更新 BOM（body 必含 id，items 结构同新建）。
  Future<InventoryBom> updateBom({
    required int id,
    required int dishId,
    required List<Map<String, Object?>> items,
    String? effectiveFrom,
  });

  /// 创建调拨单（源/目标仓经营主体一致；默认 FEFO 批次扣减）。
  Future<InventoryTransfer> createTransfer({
    required int fromWarehouseId,
    required int toWarehouseId,
    required List<Map<String, Object?>> items,
  });

  /// 批次列表（materialId/warehouseId 可选过滤；含 FEFO 建议）。
  Future<List<InventoryBatch>> listBatches({
    int? materialId,
    int? warehouseId,
  });
}
