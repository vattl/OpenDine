# WORK ITEM — WI-064

## Request
继续审计整改下一阶段：为第一批订单写动作建立 `expectedVersion`、事务内版本校验和单调 revision，并提供前端兼容交接。

## Type
REPAIR / API / CONCURRENCY

## State
ACCEPTED

## Requirement Contract

### Goal
多终端基于同一订单快照并发修改时，陈旧请求不得覆盖较新的订单状态；每次成功的加菜、退菜、改价或优惠必须使云端订单 revision 单调增加。

### Target behavior
- `/order/addDishes`、`/cashier/order/addDishes|refundDish|updatePrice|discount` 接受可选 `expectedVersion`（兼容 `expected_version`）。
- 携带版本且与锁定后的权威订单不一致时，返回 HTTP 409、`ORDER_VERSION_CONFLICT` 和最新订单摘要，且订单、明细、库存、桌台金额、支付尝试和 KDS 投影均不变化。
- 未携带版本的旧客户端在兼容窗口内仍可执行，但成功写入也必须递增 revision。
- 成功响应返回最新 `revision`，供客户端下一次写入使用。
- KDS 仍以云端为唯一权威；POS 加菜复用订单业务写链后不得重复递增同一业务 revision。

### Must preserve
- INV-ORDER-001、INV-TABLE-001、INV-COMBO-001、INV-APPROVAL-001 和 WI-063 动作授权顺序。
- 陈旧请求在审批 token 消耗及任何业务副作用之前拒绝。
- KDS command_id 幂等、ticket/kds-order 局部 revision 与云端事件顺序不变。
- 本项不强制旧客户端提供 expectedVersion；强制截止与全写链覆盖在后续迁移阶段裁决。

### Acceptance criteria
- [x] 第一批五个 HTTP 入口支持 expectedVersion/expected_version。
- [x] 相同版本的两次顺序写入仅第一次成功，第二次稳定返回 409 和最新摘要。
- [x] 冲突请求不消费审批 token、不更新明细/订单/库存/桌台/KDS。
- [x] 未带版本的兼容写入成功且 revision 增加 1。
- [x] 成功响应均返回最新 revision。
- [x] KDS POS 加菜只增加一次 t_order revision。
- [x] OpenAPI、API.md、前端交接、测试和完整 JAR 同步完成。

## Business Invariants
- Applicable: INV-ORDER-001, INV-ORDER-002, INV-TABLE-001, INV-COMBO-001, INV-APPROVAL-001
- Target promotion after acceptance: INV-ORDER-002 from TARGET to ENFORCED for the first mutation slice only; full invariant remains PARTIAL until later write slices migrate.

## Impact Map Authority
`docs/work-items/WI-064/IMPACT_MAP.md`，Material UNKNOWN = 0。

## Scenario Matrix
`docs/work-items/WI-064/SCENARIO_MATRIX.md`。

## Implementation Ready
`IMPLEMENTATION_READY = YES`

## Tasks / Vertical Slices
- [x] T01 RED：版本解析、冲突、无副作用、成功递增和 KDS 单次递增测试。
- [x] T02 GREEN：共享订单 revision 守卫与第一批 Controller 接入。
- [x] T03 契约同步、KDS 投影复核和前端交接。
- [x] T04 回归、审查、验收与完整 JAR 打包。

## Integration / Release
目标为仓库 ACCEPTED；不宣称已部署、INTEGRATED 或 RELEASED。

## Acceptance Decision
ACCEPTED
