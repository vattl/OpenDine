# Completion Evidence — WI-014

## 变更概述

在日结预检（`GET /admin/daily/pre-check`）中增加对超时（默认超过 30 分钟）未支付打包单/外卖单的智能识别与结构化提示，并新增专用端点（`POST /admin/daily/void-stale-takeout-orders`），实现超时未支付打包外卖单的一键全部作废，包含订单状态流转、菜品库存回退、KDS 厨房工单作废、外卖配送单取消、收款意向清理与特权安全审计的完整闭环。

## 修改清单

1. **服务接口与实现扩展**：
   - `IDailyCloseService.java`：声明 `precheck(shopId, adminId, statDate, staleMinutesThreshold)` 及 `voidStalePackTakeoutOrders(shopId, adminId, statDate, minutesThreshold)`；
   - `DailyCloseServiceImpl.java`：
     - 在 `precheck` 中筛选就餐方式属于打包/外卖（`PaymentDiningTypeUtil.isPackOrDeliveryType`）且 `order_time <= now - minutes` 的未结订单，组装 `voidable_stale_pack_takeout` 结构并在 `OPEN_ORDERS` 阻断项中补充提示；
     - 实现 `voidStalePackTakeoutOrders` 事务内原子作废（`transac_status = 'cancelled'`, `order_receiving = 'cancelled'`），级联调用：
       - `dishShopStockService.restoreForDetail` 回退未退菜库存；
       - `takeoutDeliveryService.markCancelledIfPresent` 取消配送单；
       - `kdsOrderHook.afterOrderCancelled` 通知厨房作废工单；
       - `collectionIntentService.cancelAllForOrder` 清理未完成收款意向；
       - `securityAuditService.recordPrivilegedAction` 写入特权操作审计日志；
   - `CashierCollectionIntentService.java`：新增 `cancelAllForOrder(shopId, orderNo)` 方法，用于整单作废时释放未完成的 `PENDING` 收款意向。
2. **控制层与路由权限映射**：
   - `AdminDailyController.java`：
     - `GET /admin/daily/pre-check` 支持传入可选 `minutes` 参数；
     - 增加 `POST /admin/daily/void-stale-takeout-orders` 一键作废端点；
   - `ApiPermissionMapping.java`：注册 `/admin/daily/void-stale-takeout-orders` 权限映射（`daily:settle|order:operate`）。
3. **单元测试与门禁验证**：
   - 新增 `DailyCloseVoidStaleTakeoutTest`：覆盖超时打包外卖单识别、堂食排除、未超时排除、一键作废及全部副作用（库存、KDS、配送、意向、审计）；
   - 回归测试：`DailyCloseVoidStaleTakeoutTest,DailyCloseServiceTest` 16 tests 全部 PASS；
   - 全量编译打包完成：`target/diancan-0.0.1-SNAPSHOT.jar` 生成完成（73,931,437 bytes，SHA-256 `0498EDD8E9D625D67F0508B33A8C20980308B82068752A29C4D0AB3D348F50CA`）；
   - 门禁决策通过。
4. **契约文档同步**：
   - `docs/openapi.yaml`：版本更新记录 v1.2.289；
   - `docs/API.md`：新增《日结预检提示可作废打包外卖单与一键全部作废契约（v1.2.289 / WI-014）》。
