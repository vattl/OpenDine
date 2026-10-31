# Implementation Design — WI-013

## Root Fix / Owner

收银结账服务 `CashierCheckoutService` 与意向服务 `CashierCollectionIntentService`。

## Minimal Change

1. `CashierCollectionIntentService`：
   - 增加 `completeAllForOrder(int shopId, String orderNo)`，将订单下所有 `PENDING` 和 `CONFIRMED` 意向标记为 `COMPLETED`；
   - `validateCheckout` 支持 `boolean force` 参数，当 `force=true` 时放行并记录 warn 日志。
2. `CashierCheckoutService`：
   - 解析 `force` 标识；
   - 结账前/中校验 `admin:manage` 权限；
   - 结账成功后调用 `collectionIntentService.completeAllForOrder`；
   - 记录 `securityAuditService.recordPrivilegedAction`。
3. `CashierOrderController` & `AdminOrderController`：
   - 支持 `force` 参数及 `/force-checkout` 端点；
   - 接入 `SensitiveOperationAuthorizationService` 现场授权支持。
4. `ApiPermissionMapping`：
   - 注册 `/cashier/order/force-checkout` 与 `/admin/order/force-checkout` 权限码。

## Verification Strategy

编写专项单元测试 `CashierForceCheckoutTest`：
- 场景 1：无权限发起 force 结账抛出 403；
- 场景 2：具备 `admin:manage` 发起 force 结账成功绕过意向锁定；
- 场景 3：意向全部收敛为 COMPLETED，订单状态变为 success；
- 场景 4：生成安全审计日志。
运行全量测试及 Maven 打包。
