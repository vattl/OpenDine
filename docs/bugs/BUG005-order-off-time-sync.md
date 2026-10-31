# Bug Report BUG005 — 订单完成生命周期 off_time 缺失更新审计与修复

## Status
- **Bug ID**: BUG005
- **Status**: FIXED
- **Severity**: HIGH
- **Found**: 2026-08-31
- **Root Cause**: 
  1. `com.lanf.entity.Order` 实体中缺失 `private Date off_time;` 字段定义与序列化注解，导致 MyBatis-Plus 的所有单表操作均无法读写 `t_order.off_time` 列。
  2. 订单在完成生命周期节点（KDS 厨显整单完成联动自动清台、收银端桌台清台 `POST /cashier/table/clear`、换桌新单覆盖旧单、管理后台手动修改接单状态为 `off_order`、外卖履约状态变更为 `completed`）时，未对 `off_time` 进行赋值或写入 `NOW()`。

---

## 1. 审计与现象 (Symptom & Audit)

- 数据库表结构 `t_order` 存在 `off_time datetime NULL DEFAULT NULL COMMENT '订单完成时间'` 字段。
- OpenAPI 契约中已声明 `Order.off_time` 属性。
- 实际运行时，订单完成后（`order_receiving = 'off_order'`）数据库中的 `off_time` 始终为 `NULL`。

---

## 2. 修复方案 (Fix Execution)

1. **实体映射补全**：在 `Order.java` 中增加 `@JsonSerialize(using=CustomDateTimeSerializer.class) private Date off_time;` 属性。
2. **KDS 厨显整单完成清台**：
   - `KdsLegacySyncService.markOrderCompleted`：设置 `order_receiving = "off_order"` 时同步 `order.setOff_time(new Date())`。
   - `KdsReplicationService.syncFromLocalEvent`：更新 SQL 增加 `off_time = IFNULL(off_time, NOW())`。
3. **收银端桌台清台**：
   - `CashierTableOperationMapper` 增加 `finishSettledOrdersOnTable`：在清台成功时批量将该桌已结账未完结订单更新为 `order_receiving = 'off_order'`，并写入 `off_time = IFNULL(off_time, NOW())`。
   - `CashierTableOperationTransactionalService.clear`：清台成功后联动触发更新。
4. **开台/新单入座覆盖前一单**：
   - `OrderController.create`：将上一张单标记为 `off_order` 时，写入 `previousOrder.setOff_time(new Date())`。
5. **管理后台手动接单状态调整**：
   - `AdminOrderController.receiving`：若将 `order_receiving` 调整为 `off_order`，补全 `resultOrder.setOff_time(new Date())`。
6. **外卖履约完成**：
   - `TakeoutDeliveryServiceImpl.updateDispatchStatus` 与 `TakeoutZsqIntegrationServiceImpl`：外卖状态推进至 `completed` 时，联动更新订单 `order_receiving = 'off_order'` 与 `off_time = new Date()`。
7. **回归测试验证**：
   - 编写 `OrderOffTimeAuditTest` 覆盖上述全部完成路径；
   - 运行全量单元测试（613 个测试用例 100% PASS）；
   - 执行 `mvn clean package -DskipTests` 完成 JAR 包打包构建。
