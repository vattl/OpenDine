# WORK ITEM — WI-059

## Request

落实审计方案阶段 1 的第一切片：审批上下文严格绑定，同时保留可观测、可关闭的旧客户端兼容窗口。

## Type
REPAIR / SECURITY

## State
ACCEPTED

## Requirement Contract

### Goal
新签发的 v2 审批令牌必须精确绑定动作、资源类型/ID、金额、操作者、门店和终端，任一不匹配拒绝且不核销。

### Current behavior
占位 `bizId` 可绕过资源绑定；金额允许额外 50 元；空上下文可跳过绑定；终端未参与核销。

### Target behavior
- `bindingVersion=2` 的签发请求要求完整业务对象与终端；金额按“双方均空或数值完全相等”匹配。
- v2 核销缺少任一强绑定字段即失败，失败不改变 APPROVED 状态。
- 未声明版本的旧请求暂按 v1 兼容并记录安全告警；响应明确返回 `bindingVersion=1`、`legacyBinding=true`。
- 文档给出 v2 客户端迁移契约；兼容移除由后续 Work Item 决定。

### Must preserve
- Token 120 秒过期与 CAS 单次核销。
- 普通收银员仍能发起审批。
- v1 兼容窗口内现有客户端流程可用。

### Acceptance criteria
- [ ] v2 占位/空资源、空终端拒绝签发。
- [ ] 动作、对象、金额、操作者、门店或终端不一致均拒绝且不消费。
- [ ] 完全一致仅一次成功。
- [ ] v1 调用有明确兼容标记与日志。
- [ ] OpenAPI、API.md、迁移与 Contract Handoff 同步，完整 JAR 构建成功。

### Open product questions
无；v1 关闭日期由 WI-061 根据客户端采用率确定。

## Impact Summary
Link: `IMPACT_MAP.md`

## Design Summary
Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices
- [x] RED tests
- [x] schema/model and strict validation
- [x] caller context propagation
- [x] API/docs/handoff
- [x] verify/review/accept/package

## Verification Evidence
See `TEST_REPORT.md`, `SECURITY_AUDIT.md` and `COMPLETION_EVIDENCE.md`.

## Review
PASS

## Acceptance Decision
ACCEPTED

## Consumer Handoffs
`CONTRACT_HANDOFF.md`

## Integration / Release
Repository acceptance only; coordinated client rollout required before v1 removal.

## Business Invariants
- Applicable invariant IDs: INV-APPROVAL-001
- New invariant candidates: NONE

## Impact Map Authority
- Impact map path: `docs/work-items/WI-059/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix
- Scenario matrix path: `docs/work-items/WI-059/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready
- Status: `YES`
- Blockers: NONE

## Completion Level
`ACCEPTED`
