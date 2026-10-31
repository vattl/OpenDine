# WORK ITEM — WI-063

## Request
继续下一阶段：将退款/退菜、改价/赠送、优惠与反结账真实业务入口迁移到统一动作级授权决策器，并完成角色权限迁移、API 契约与前端交接。

## Type
REPAIR / SECURITY / API

## State
ACCEPTED

## Requirement Contract

### Goal
四类高风险动作只能由精确执行权限或严格绑定的一次性审批授权放行；Controller 不再自行组合 RBAC、现场密码与审批令牌校验。

### Target behavior
- 收银入口继续由 `cashier:operate` 控制。
- 业务执行统一消费 `ALLOW / REQUIRE_APPROVAL / DENY`。
- `order:operate:refund|changePrice|discount|reopen` 只放行对应动作。
- 仅入口权限返回稳定的 `REQUIRE_APPROVAL`；现场凭证和扫码令牌均复用严格绑定审批链。
- 反结账补齐 `order:operate:reopen` 授权。
- 运营端微信退款复用同一动作决策门面。

### Must preserve
- INV-APPROVAL-001：动作、对象、金额、操作者、门店、终端严格绑定且令牌单次核销。
- 订单门店隔离、资金流水、日结封账、退款和金额业务规则不变。
- 既有嵌套 `authorization` 与 `approvalToken` 请求字段兼容。
- 超级管理员旁路仍受账号状态、门店范围和显式 DENY 约束。

### Acceptance criteria
- [x] 五个实际入口（退款、退菜、改价、优惠、反结账）均调用共享动作授权门面。
- [x] 运营端微信退款使用同一门面。
- [x] 单动作执行权限不能放行其他三类动作。
- [x] 仅 `cashier:operate` 时返回 REQUIRE_APPROVAL，业务不执行。
- [x] 严格绑定令牌/现场凭证可完成一次放行，错动作/错订单/错金额/错终端拒绝。
- [x] 角色迁移只授予明确管理角色，不向 cashier/order operator 扩散。
- [x] OpenAPI、API.md、前端交接、测试及完整 JAR 同步完成。

## Business Invariants
- Applicable: INV-APPROVAL-001, INV-AUTHZ-001, INV-AUTHZ-002
- New candidate: INV-AUTHZ-003（动作权限不可横向扩散）

## Impact Map Authority
`docs/work-items/WI-063/IMPACT_MAP.md`，Material UNKNOWN = 0。

## Scenario Matrix
`docs/work-items/WI-063/SCENARIO_MATRIX.md`。

## Implementation Ready
`IMPLEMENTATION_READY = YES`

## Tasks / Vertical Slices
- [x] T01 RED：共享门面、Controller 接线、跨动作隔离和反结账测试。
- [x] T02 GREEN：实现统一动作授权门面并迁移入口。
- [x] T03 角色/权限数据迁移及契约同步。
- [x] T04 回归、打包、安全审计、前端交接与验收。

## Integration / Release
目标为仓库 ACCEPTED；不宣称已部署、INTEGRATED 或 RELEASED。

## Acceptance Decision
ACCEPTED
