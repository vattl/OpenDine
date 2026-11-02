# Impact Map — WI-013

## Authoritative Owner

收银结账（`CashierCheckoutService`）与收款意向服务（`CashierCollectionIntentService`）是订单结账与收款占用的权威 Owner。

## Change Propagation Path

```text
POST /cashier/order/checkout (force=true) 或 /force-checkout
→ CashierOrderController (校验 admin:manage 权限)
→ CashierCheckoutService (force 模式放行)
→ CashierCollectionIntentService.validateCheckout(..., force=true)
→ Order落库 success + completeAllForOrder(shopId, orderNo)
→ securityAuditService.recordPrivilegedAction
```

## Consumer Coverage

| Consumer | Classification | Handling |
|---|---|---|
| 收银结账接口 | AFFECTED | 支持 force 参数与鉴权 |
| 后台结账接口 | AFFECTED | 支持 force 参数与鉴权 |
| 收款意向服务 | AFFECTED | 支持 completeAllForOrder 与 force 放行 |
| 既有普通结账 | VERIFIED_UNAFFECTED | force=false 时行为完全不变 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 本次仅服务端 API 与鉴权实现 |
| API Client | VERIFIED_UNAFFECTED | 兼容既有参数，新增可选参数与端点 |
| Request Contract | AFFECTED | 结账请求体增加 force/授权字段 |
| Backend/Domain | AFFECTED | 强制结账与意向清理逻辑 |
| Persistence | VERIFIED_UNAFFECTED | 无 schema 变更 |
| Response Contract | VERIFIED_UNAFFECTED | 结账成功响应格式不变 |
| Security | AFFECTED | 严格校验 admin:manage 权限并审计 |
| Tests | AFFECTED | 新增 CashierForceCheckoutTest 专项测试 |

## UI Semantic Impact

NONE。

## Risks

- 确保无权限用户不可通过 force 绕过收款校验。
- 强制结账后必须将该订单所有意向收敛为 COMPLETED，防止残留。
