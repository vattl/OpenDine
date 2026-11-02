# WORK ITEM — WI-026

## Request

在日结预检中增加订单与权威资金流水的逐单比对；发现异常订单时阻断日结，并返回可直接定位问题的异常原因与差额明细。

## Type

CHANGE

## State

ACCEPTED

## Requirement Contract

### Goal

让收银或财务人员在日结前不仅知道“有差异”，还能够从预检响应中确认是哪一笔订单、哪种渠道、缺少或多出多少钱，以及异常类型。

### Current behavior

日结已经比较成功非挂账订单的渠道实收投影与成功资金流水净额，但异常明细只返回订单号及两组渠道金额，调用方需要自行推断原因。

### Target behavior

- 每笔异常返回稳定的原因码、中文原因、订单/流水总额与差额。
- 每个不一致渠道返回渠道级原因码、期望金额、流水金额与差额。
- 日结阻断项返回按原因码汇总的异常笔数，明细最多保留 50 笔。
- 差额统一定义为 `ledger - order projection`：负数表示流水少，正数表示流水多。

### Must preserve

- `t_payment_ledger` 仍为资金权威事实，预检保持只读。
- 仅核对成功、非挂账订单，多门店和营业日边界不变。
- 任何差异继续阻断日结且不签发预检令牌。
- 原有 `expected_by_channel_fen`、`ledger_by_channel_fen` 字段保持兼容。

### Acceptance criteria

- [x] 缺失流水、意外渠道、渠道金额不足/超额均返回明确原因。
- [x] 返回订单总额、流水净额及有符号差额。
- [x] 日结阻断项提供原因汇总和最多 50 笔异常明细。
- [x] 原有一致订单、挂账订单行为不变。
- [x] 专项与全量测试、OpenAPI 校验和可运行 JAR 构建通过。

### Open product questions

NONE

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 以失败测试锁定异常原因契约。
- [x] T02 扩展一致性审计和日结汇总。
- [x] T03 同步 API 文档并完成验证。

## Verification Evidence

见 `TEST_REPORT.md`、`SECURITY_AUDIT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

`REVIEW_REPORT.md`：PASS，无 Critical/High/Required 未解决项。

## Acceptance Decision

ACCEPTED

## Consumer Handoffs

服务端以兼容方式增加响应字段；消费端可渐进展示 `reason`、`reason_summary` 和 `channel_differences`。

## Integration / Release

本次目标到 ACCEPTED，不包含部署。

## Related IDs

Workstream: `codex/jsapi-settlement-integrity`
UI: NONE
Capability: daily-close / order-ledger-consistency
Commits: PENDING

## Business Invariants

- INV-FIN-004：成功非挂账订单的渠道余额必须等于成功流水按渠道净额。
- INV-FIN-005：任何读模型不得创建权威资金事实。
- INV-FIN-006：存在资金差异时不得签发日结预检令牌或完成日结。
- INV-FIN-007：异常解释必须由同一次比对结果生成，差额口径固定为流水净额减订单投影。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-026/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-026/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

ACCEPTED
