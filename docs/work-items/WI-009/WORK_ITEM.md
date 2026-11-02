# WORK ITEM — WI-009

## Request

修复加菜操作错误更新订单原始下单时间的问题。

## Type

BUG

## State

ACCEPTED

## Requirement Contract

### Goal

加菜只更新订单金额、加菜轮次、明细及相关状态，不改变订单首次创建时的 `order_time`。

### Current behavior

共享加菜入口 `OrderController.addDishes` 在持久化整单更新前把 `order_time` 设置为当前时间，导致账单排序、最近三小时查询及依赖下单时间的统计口径漂移。

### Target behavior

- 任意入口对既有订单加菜后，订单主表 `order_time` 保持原值。
- 新增明细、金额、服务费、优惠、加菜轮次、接单/KDS 行为保持不变。

### Must preserve

- 小程序、收银端与 AI 加菜均继续汇聚到同一共享入口。
- 现有门店、订单身份、库存、套餐、优惠及事务校验不变。
- API 请求与响应结构不变。

### Acceptance criteria

- [x] 成功加菜后 `order_time` 与加菜前完全相同。
- [x] 金额和 `orderNumber` 仍按原规则更新。
- [x] 现有加菜相关测试与完整回归通过。
- [x] `docs/openapi.yaml` 与 `docs/API.md` 明确 `order_time` 为首单创建时间。
- [x] 生成新的可运行 JAR。

### Open product questions

NONE。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 添加可复现下单时间被改写的失败测试。
- [x] T02 移除共享加菜入口对 `order_time` 的重新赋值。
- [x] T03 同步 API 文档，完成定向/全量测试、打包与验收。

## Verification Evidence

见 `TEST_REPORT.md`、`SECURITY_AUDIT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

PASS：五轴复核确认修复位于共享 owner，无接口破坏、权限变化、额外查询或性能回归。

## Acceptance Decision

ACCEPTED（工程验收，不代表已集成或已发布）。

## Consumer Handoffs

NONE。请求/响应兼容，所有既有调用者自动获得修复。

## Integration / Release

目标状态为 ACCEPTED；不在本 Work Item 内部署。

## Related IDs

Workstream: preserve-order-created-time-on-add-dishes
UI: NONE
Capability: order-add-dishes
Commits: PENDING

## Business Invariants

- INV-ORDER-TIME-01：`t_order.order_time` 表示首单创建时间，订单后续加菜不得改变。
- INV-ADD-DISH-01：加菜金额、明细、库存与加菜轮次必须在同一事务内保持一致。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-009/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-009/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`
