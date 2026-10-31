import '../domain/dining_table.dart';

abstract class TableRepository {
  Future<TableOverview> loadTableOverview();

  /// 新增桌台（POST /admin/table/add，权限 table:manage）。
  ///
  /// [number] 为桌台号，如 A01、1。成功后调用方应静默刷新桌台列表。
  Future<void> createTable(String number);

  /// 删除桌台（GET /admin/table/delete?id=，权限 table:manage）。
  ///
  /// [id] 为桌台主键 t_table.id，物理删除、不可恢复。
  /// 建议仅对空闲桌台调用（占用/待清台桌台应先清台释放）。
  /// 成功后调用方应静默刷新桌台列表。
  Future<void> deleteTable(int id);

  Future<FulfillmentOrderDetail> loadFulfillmentOrderDetail(
    FulfillmentOrder order,
  );

  Future<void> updateFulfillmentStatus(
    FulfillmentOrder order,
    FulfillmentStatus status,
  );
}
