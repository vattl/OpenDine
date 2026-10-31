# Test Report — WI-014

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## TDD Evidence

- 预检识别：在营业日包含超时打包单、未超时打包单和超时堂食单时，日结预检（`GET /admin/daily/pre-check`）正确识别仅超时打包单为可作废，并在顶层及 `OPEN_ORDERS` blocker 中输出结构化统计（笔数、金额、明细）。
- 一键全部作废：调用 `voidStalePackTakeoutOrders` 仅对超过 30 分钟未支付的打包/外卖单执行作废（`transac_status = 'cancelled'`, `order_receiving = 'cancelled'`），堂食单完好保留。
- 副作用验证：
  - 恢复菜品占用库存（`dishShopStockService.restoreForDetail`）；
  - 通知 KDS 厨显作废工单（`kdsOrderHook.afterOrderCancelled`）；
  - 取消外卖配送单（`takeoutDeliveryService.markCancelledIfPresent`）；
  - 取消收款意向（`collectionIntentService.cancelAllForOrder`）；
  - 写入特权操作审计日志（`securityAuditService.recordPrivilegedAction`）。

## Regression

- 专项测试：`DailyCloseVoidStaleTakeoutTest,DailyCloseServiceTest`，16 tests，0 failures，0 errors。
- 打包构建：`.\mvnw.cmd clean package -DskipTests`，BUILD SUCCESS。

## Artifact

- `target/diancan-0.0.1-SNAPSHOT.jar`
- Size: 73,931,437 bytes
- SHA-256: `0498EDD8E9D625D67F0508B33A8C20980308B82068752A29C4D0AB3D348F50CA`
