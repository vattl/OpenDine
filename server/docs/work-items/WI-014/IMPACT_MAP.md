# Impact Map — WI-014

## Authoritative Owner

日结核心服务（`DailyCloseServiceImpl`）与订单服务（`IOrderService`）是日结预检及订单作废副作用的权威 Owner。

## Change Propagation Path

```text
GET /admin/daily/pre-check
→ AdminDailyController.precheck
→ DailyCloseServiceImpl.precheck (识别超时未支付打包外卖单，组装 voidable_stale_pack_takeout 提示)

POST /admin/daily/void-stale-takeout-orders
→ AdminDailyController.voidStaleTakeoutOrders
→ DailyCloseServiceImpl.voidStaleTakeoutOrders
→ 事务内逐笔更新 Order (transac_status='cancelled', order_receiving='cancelled')
→ 释放库存 (dishShopStockService.restoreForDetail)
→ 取消配送 (takeoutDeliveryService.markCancelledIfPresent)
→ 通知 KDS 作废 (kdsOrderHook.afterOrderCancelled)
→ 清理意向 (collectionIntentService.cancelAllForOrder)
→ 审计日志 (securityAuditService.recordPrivilegedAction)
```

## Consumer Coverage

| Consumer | Classification | Handling |
|---|---|---|
| 日结预检接口 `GET /admin/daily/pre-check` | AFFECTED | 增加 voidable_stale_pack_takeout 字段与 OPEN_ORDERS 结构体丰富化 |
| 管理后台/收银一键作废端点 | AFFECTED | 新增 POST /admin/daily/void-stale-takeout-orders |
| 库存服务 | AFFECTED | 作废订单时自动回退未退菜明细库存 |
| KDS 厨显系统 | AFFECTED | 同步发送作废事件通知厨房 |
| 权限系统 | AFFECTED | ApiPermissionMapping 注册 daily:settle |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 本次仅服务端 API 与日结预检结构契约实现 |
| API Client | VERIFIED_UNAFFECTED | 预检响应向下兼容追加字段，新增作废端点 |
| Request Contract | AFFECTED | 新增 void-stale-takeout-orders 端点入参 |
| Backend/Domain | AFFECTED | 预检统计与批量作废副作用闭环 |
| Persistence | VERIFIED_UNAFFECTED | 无 schema 变更 |
| Response Contract | AFFECTED | precheck 响应增加 voidable_stale_pack_takeout |
| Security | AFFECTED | 鉴权校验 daily:settle / admin:manage 并审计 |
| Tests | AFFECTED | 新增 DailyCloseVoidStaleTakeoutTest 专项测试 |

## UI Semantic Impact

NONE。

## Risks

- 严防误伤堂食订单：必须使用 `PaymentDiningTypeUtil.isPackOrDeliveryType` 严格过滤。
- 严防误取消刚下的打包单：必须基于 `order_time` 严格校验超过 30 分钟。
