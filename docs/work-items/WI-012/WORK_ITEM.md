# WORK ITEM — WI-012

## Request

修复桌台金额与实际订单金额不一致：套餐 108 元加一串菇 8 元时，桌台错误显示 124 元。桌台金额必须绑定实际订单应付金额。

## Type

BUG

## State

ACCEPTED

## Requirement Contract

### Goal

桌台待结账金额以当前桌全部未结订单的持久化实际应付金额为唯一来源，不再从订单明细二次推导并覆盖订单金额。

### Current behavior

`GET /admin/table/status` 使用 `TableStatusAmountCalculator` 从明细重新汇总商品金额，并按当前服务费配置重算服务费。明细重复、历史套餐结构或配置变化均会导致桌台显示与订单主表金额漂移。

### Target behavior

- 单订单桌台金额等于该订单实际应付净额。
- 合并桌台金额等于全部未结订单实际应付净额之和。
- 套餐子行、重复历史明细或当前服务费配置变化不得改变已落库订单金额。
- 明细仍返回用于展示和审计，但不再成为桌台金额权威源。

### Must preserve

- 门店隔离、桌号/订单号解析和合并桌订单返回行为不变。
- 优惠、退款、礼品支付继续计入净应付公式。
- 已结账历史订单查询不得覆盖当前复用桌台金额。

### Acceptance criteria

- [x] 订单实际金额 116 元时，即使明细重算为 124 元，桌台仍显示 116 元。
- [x] 多个未结订单按各自实际应付净额求和。
- [x] API 文档明确订单主表为金额真源。
- [x] 专项与完整回归通过并生成新 JAR。

### Open product questions

NONE。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 添加套餐/重复明细导致桌台金额漂移的失败测试。
- [x] T02 将桌台状态金额切换为订单实际净应付口径。
- [x] T03 同步 OpenAPI/API 文档，运行专项、全量测试和打包。

## Verification Evidence

完成后写入 `TEST_REPORT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

PASS。五轴审查无未解决的 Critical/Required 发现。

## Acceptance Decision

ACCEPTED。

## Consumer Handoffs

现有响应字段保持兼容；`amountAudit.calculation_source` 语义更新并同步文档。

## Integration / Release

目标为本地 ACCEPTED；不含推送或部署。

## Business Invariants

- INV-TABLE-AMOUNT-01：桌台金额等于当前桌全部未结订单实际净应付金额之和。
- INV-ORDER-AMOUNT-01：已持久化订单金额不得被只读桌台查询按明细重新解释。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-012/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-012/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`
