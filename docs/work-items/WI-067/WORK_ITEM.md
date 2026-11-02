# WORK ITEM — WI-067

## Request

基于日结流程审计修复跨营业日跳结问题：昨天未日结时，日结中心必须展示并只能结算昨天；完成后才能推进到下一营业日。

## Type

BUG / API / DATA-INTEGRITY

## State

ACCEPTED

## Requirement Contract

### Goal

建立由后端强制执行的门店日结时序，使任何客户端、脚本或并发请求都不能跳过更早未结营业日。

### Current behavior

- 日结日期缺省时按当前活动营业日计算。
- 客户端按本机时间计算营业日并显式传入，昨天未结时仍展示今天。
- 预检和正式日结只校验请求日期自身，不校验更早未结日期。
- 历史补结会被其他营业日的活动钱箱及全局水位干扰。
- 已结日期可被任意重开，且重结会与 `(shop_id, business_day)` 唯一键冲突。

### Target behavior

- 后端返回唯一权威 `next_close_business_day`，其定义为门店日结序列中最早未结营业日。
- 后端提供权威待结日期，并拒绝任何更晚营业日的预检令牌和关账写入。
- `pre-check`、`settle` 和一键作废等写入链路只允许目标日期等于权威待结日期；跳日请求返回 409 `DAILY_CLOSE_OUT_OF_SEQUENCE`。
- 完成 D 日结后，下一次查询推进到 D+1；零销售营业日也必须生成零值快照后才能推进。
- 目标营业日的钱箱与窗口水位独立校验，不受后续营业日的正常经营干扰。
- 只允许重开最新已结营业日；重结复用该营业日记录并保留审计信息。

### Must preserve

- 已结快照查询、历史 Z 报表及显式历史只读查询继续使用请求日期，不被待结日重定向。
- 门店隔离、`daily:settle` 权限、预检令牌、资金一致性、幂等与二次授权规则不降低。
- 现有 `(shop_id, business_day)` 唯一约束保留。
- 无历史快照门店采用兼容启动规则，不追溯强迫补结系统启用前的全部历史。

### Acceptance criteria

- [x] 昨天未结时，后端日结上下文与预检返回昨天；生产页面不在用户限定的后端范围内。
- [x] 显式请求今天执行日结时，后端返回 409 并指出 expected/requested 日期。
- [x] 昨天日结成功后，下一次上下文推进至今天。
- [x] 连续漏结多日时逐日推进，不能跳跃；零销售日亦不能跳过。
- [x] 补结昨天不被今天的钱箱及今天新增交易错误阻断。
- [x] 重开非最新已结日被拒绝；最新日重开后可再次日结。
- [x] 为 Flutter 消费者留下明确交接契约，但本 Work Item 不修改前端代码。
- [x] OpenAPI 与 `docs/API.md` 同步，API 变更后完成全量 JAR 打包。

### Open product questions

无。兼容启动规则确定为：已有快照从最新快照连续推进；没有任何快照时从当前活动营业日开始建立序列。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 TDD 复现最早未结日选择、跳日拒绝和逐日推进。
- [x] T02 实现后端权威日结序列与窗口级预检/水位。
- [x] T03 修复最新日重开与重结状态机。
- [x] T04 同步 API 契约并交付前端消费者迁移说明（不改前端）。
- [x] T05 全量回归、JAR 打包、独立复核与接受门禁。

## Verification Evidence

见 `TEST_REPORT.md`、`SECURITY_AUDIT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

PASS；无 HIGH/CRITICAL 发现。全仓 5 个已知基线失败与本变更无关，专项 27/27 通过。

## Acceptance Decision

ACCEPTED（仅后端范围）；前端消费者适配保留在 `API_CONSUMER_HANDOFF.md`，未声称完成。

## Consumer Handoffs

`API_CONSUMER_HANDOFF.md`

## Integration / Release

工程完成目标为 ACCEPTED；部署与 RELEASED 不在本 Work Item 自动声明。

## Related IDs

Workstream: current checkout

UI: NOT_APPLICABLE（用户明确限定仅后端；既有原型保留为非生产参考）

Capability: BCR-DAILY-SEQUENCE-001

Commits: PENDING

## Business Invariants

- Applicable invariant IDs: INV-PAY-003, INV-CLOSE-001, INV-CLOSE-SEQ-001, INV-CLOSE-SEQ-002
- New invariant candidates: INV-CLOSE-SEQ-001, INV-CLOSE-SEQ-002

## Impact Map Authority

- Impact map path: `docs/work-items/WI-067/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-067/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: none; executable ready gate evidence recorded in `DELIVERY_GATE.md`.

## Completion Level

`ACCEPTED`
