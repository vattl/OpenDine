# Security Audit — WI-014

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Threat Model

- Asset: 订单状态机、菜品库存扣减/恢复、KDS 厨房工单生命周期、外卖履约配送状态。
- Trust boundary: 管理端 `POST /admin/daily/void-stale-takeout-orders`。
- Boundary defenses:
  - 接口权限强制绑定 `daily:settle|order:operate`；
  - 严禁作废堂食订单（`PaymentDiningTypeUtil.isPackOrDeliveryType` 过滤，堂食必须走清台/收银结账）；
  - 严禁作废已结订单（`transac_status = 'unsettled'` 条件限定，CAS 更新）；
  - 严格 30 分钟超时窗口防护（未满超时时长的订单不作废，防止误伤刚下的正常打包单）；
  - 事务级原子操作联动：释放菜品可售库存（`dishShopStockService.restoreForDetail`）、取消外卖履约配送（`takeoutDeliveryService.markCancelledIfPresent`）、通知 KDS 厨房屏（`kdsOrderHook.afterOrderCancelled`）、取消占用收款意向（`collectionIntentService.cancelAllForOrder`）；
  - 特权操作安全审计（`securityAuditService.recordPrivilegedAction`，记录操作人、门店、营业日、作废订单量与订单号集合）。

## Findings

- 权限映射与鉴权拦截正常运行。
- 敏感信息扫描无泄漏。
