# WORK ITEM — WI-013

## Request

增加强制结账功能，需要具备 admin:manage 权限。

## Type

FEATURE

## State

IMPLEMENTING

## Requirement Contract

### Goal

在收银结账与后台结账流程中支持强制结账（force checkout）：
当订单存在收款意向会话锁定（如已有其他会话确认到账、会话丢失、金额/渠道冲突等）且常规结账被拦截时，持有 `admin:manage` 权限的管理员（或具备该权限的店长授权）可强制完成订单结账入账，并原子清理该订单名下残留的收款意向。

### Current behavior

- `POST /cashier/order/checkout` 在遇到数据库中存在 `CONFIRMED` 意向但 `session_id` 不匹配或未传时，严格抛出异常并拦截结账。
- 无强制结账通道，遇到异常卡单必须手动修改数据库清理意向表。
- 无针对强制结账的 `admin:manage` 权限拦截与特权安全审计。

### Target behavior

1. 结账接口（`/cashier/order/checkout`、`/cashier/table/checkout`、`/admin/order/checkout`）支持 `force: true` 参数，并新增专用端点 `POST /cashier/order/force-checkout` 与 `POST /admin/order/force-checkout`。
2. 权限校验：
   - 当 `force=true` 时，校验当前操作人是否具备 `admin:manage` 权限或为 `super_admin`；
   - 若操作人无该权限，支持通过 `approvalToken` 或主管账号密码现场授权；若仍不具备则拒绝并返回 403；
   - 未传 `force` 时保持原有普通收银结账行为。
3. 业务放行与收敛：
   - 当 `force=true` 且权限校验通过时，跳过收款会话强一致性阻断；
   - 订单结账落库成功后，原子调用 `completeAllForOrder` 将该订单名下所有 `PENDING` / `CONFIRMED` 意向标记为 `COMPLETED`，彻底解锁订单；
   - 记录特权安全审计日志。

### Must preserve

- 普通非强制结账（`force=false`）的严格资金安全校验不受影响。
- 会员余额支付时的余额扣减正确性。
- 桌台状态更新、打印机驱动、流水对账记录正常触发。

### Acceptance criteria

- [ ] 操作人无 `admin:manage` 权限时尝试 `force=true` 强制结账被 403 拦截。
- [ ] 操作人具备 `admin:manage` 权限时，即使存在其他已确认会话冲突也能成功强制结账。
- [ ] 强制结账成功后，订单主表变为 `success`，桌台正常释放，`t_cashier_collection_intent` 所有未结记录收敛为 `COMPLETED`。
- [ ] 触发 `securityAuditService.recordPrivilegedAction` 特权审计记录。
- [ ] 同步更新 `docs/openapi.yaml` 与 `docs/API.md`。
- [ ] Maven 全量打包生成最新 JAR 产物。

### Open product questions

NONE。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [ ] T01 实现 `CashierCollectionIntentService.completeAllForOrder` 与 `validateCheckout(..., force)`
- [ ] T02 在 `CashierCheckoutService` 与 `CashierOrderController` / `AdminOrderController` 实现 `force` 与 `admin:manage` 鉴权、放行和审计
- [ ] T03 配置 `ApiPermissionMapping` 路由与权限映射
- [ ] T04 编写 `CashierForceCheckoutTest` 单元测试并通过验证
- [ ] T05 同步 OpenAPI / API 契约文档并执行 Maven clean package

## Verification Evidence

完成后写入 `TEST_REPORT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

待实现后执行五轴审查。

## Acceptance Decision

PENDING。

## Consumer Handoffs

现有收银与后台结账接口向后兼容，新增可选 `force` 参数及 `/force-checkout` 端点。

## Integration / Release

目标为本地 ACCEPTED。

## Business Invariants

- INV-CHECKOUT-01：非强制结账必须保证收款会话一致性。
- INV-CHECKOUT-FORCE-01：强制结账必须持有 `admin:manage` 权限或超管授权并计入特权审计。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-013/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-013/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 5

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`IMPLEMENTING`
