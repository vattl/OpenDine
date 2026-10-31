# Implementation Design — WI-014

## Root Fix / Owner

日结核心服务 `DailyCloseServiceImpl` 与控制层 `AdminDailyController`。

## Minimal Change

1. `IDailyCloseService` & `DailyCloseServiceImpl`：
   - 丰富 `precheck`：查询当前营业日内未结订单列表，筛选出 `PaymentDiningTypeUtil.isPackOrDeliveryType(order.getDineInOrTakeOut())` 且 `order_time <= now - 30 minutes` 的订单集合；
   - 在返回结果中增加 `voidable_stale_pack_takeout` 汇总对象，并在 `OPEN_ORDERS` blocker 内部增加 `voidable_pack_takeout` 统计；
   - 增加方法：
     `Map<String, Object> voidStalePackTakeoutOrders(Integer shopId, Integer adminId, String statDate, Integer minutesThreshold)`；
     在 `@Transactional(rollbackFor = Exception.class)` 内查询符合条件的未结打包/外卖单，对每笔订单：
     - CAS 更新 `transac_status = 'cancelled'`, `order_receiving = 'cancelled'`；
     - 调用 `dishShopStockService.restoreForDetail(od, shopId)` 恢复未退菜库存；
     - 调用 `kdsOrderHook.afterOrderCancelled(order)` 通知厨房；
     - 调用 `takeoutDeliveryService.markCancelledIfPresent(orderNo)` 取消配送；
     - 调用 `collectionIntentService.cancelAllPending(shopId, orderNo)` 取消意向；
     - 记录特权审计日志 `securityAuditService.recordPrivilegedAction`；
2. 控制层 `AdminDailyController`：
   - 新增 `POST /admin/daily/void-stale-takeout-orders`；
   - 接收可选参数 `minutes`（默认 30）与 `stat_date`；
3. `ApiPermissionMapping`：
   - 注册 `add(METHOD_POST, "/admin/daily/void-stale-takeout-orders", "daily:settle|order:operate");`。

## Verification Strategy

编写单元测试 `DailyCloseVoidStaleTakeoutTest`：
- 场景 1：预检识别出超时打包单并统计金额与笔数；
- 场景 2：堂食单和未满 30 分钟打包单不进入作废列表；
- 场景 3：执行一键作废后状态变为 cancelled，库存与 KDS 副作用正确触发；
- 场景 4：作废后再预检，超时打包单阻断解除。
运行全量打包与验证。
