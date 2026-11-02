import '../domain/dining_table.dart';
import '../domain/takeout_delivery.dart';

abstract class TableRepository {
  Future<TableOverview> loadTableOverview();

  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  );

  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  );

  /// 新建桌台
  Future<void> createTable({
    required String number,
    int peopleCount = 4,
    String? areaCode,
    String? areaName,
  });

  /// 修改桌台信息
  Future<void> updateTable({
    required int id,
    required String number,
    int? peopleCount,
    String? areaCode,
    String? areaName,
  }) async {}

  /// 删除桌台
  Future<void> deleteTable(int id);

  /// 校验管理账号密码（用于删除桌台等高危操作的二次验证）
  Future<void> verifyPassword({
    required String username,
    required String password,
  }) async {}

  /// 获取桌台分区列表
  Future<List<Map<String, dynamic>>> loadTableAreas() async => const [];

  /// 批量清台
  Future<void> batchClearTables({
    List<int>? tableIds,
    List<String>? tableNumbers,
    String? operatorAccount,
  }) async {}

  /// 更新订单/桌台就餐人数
  Future<void> updateTableDiners({
    required String orderNo,
    required String tableNumber,
    required int diners,
    String? operatorAccount,
  }) async {}

  /// 查询实时经营脉搏指标
  Future<Map<String, dynamic>?> loadTablePulse() async => null;
}

abstract class TakeoutDeliveryRepository {
  Future<TakeoutDeliverySnapshot?> loadTakeoutDelivery(FulfillmentOrder order);

  Future<TakeoutDeliverySnapshot> dispatchTakeoutRider(
    FulfillmentOrder order, {
    bool redispatch = false,
  });

  Future<TakeoutDeliverySnapshot> cancelTakeoutDelivery(FulfillmentOrder order);
}
