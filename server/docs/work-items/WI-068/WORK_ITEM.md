# WORK ITEM — WI-068

## Request

扩展历史 Z 报表接口：按连续营业日时序返回已结、未结和重开状态，使前端可从历史报表进入权威的最早待日结营业日。

## Type

CHANGE / API / DATA-INTEGRITY

## State

ACCEPTED

## Requirement Contract

### Goal

让 `GET /admin/daily/z-reports` 返回与 WI-067 日结序列一致的连续营业日日历，而不是只返回已有 `CLOSED` 快照。

### Target behavior

- 列表按营业日倒序、逐日连续返回，分页条数以营业日为单位。
- 每项返回 `close_state`：`CLOSED`、`PENDING` 或 `REOPENED`。
- 每项返回 `can_close` 与 `is_next_close_business_day`；只有权威最早待结日为 `true`。
- 已结项继续返回原有快照、金额、经办人与水位字段；无快照的 `PENDING` 项对应字段为 `null` 或空摘要。
- 不返回当前权威营业日之后的未来日期，也不把门店首张快照之前的历史强制定义为待结。
- `cursor` 保持不透明 long 契约，但新响应使用 `yyyyMMdd` 营业日值；请求游标为排他上界。

### Must preserve

- 门店隔离和 `daily:settle` 权限不变。
- WI-067 的严格时序不变量不变；展示状态不能赋予跳日权限。
- `limit` 仍为 1~100，默认 20；日期范围仍为包含边界。
- 已结项原有字段名和金额口径不变。

### Acceptance criteria

- [x] 存在日期缺口时，响应中出现相应 `PENDING` 行。
- [x] `REOPENED` 快照显示为 `REOPENED` 且仅当它是最早待结日时可操作。
- [x] 只有 `next_close_business_day` 对应行 `can_close=true`。
- [x] 页面可使用 `business_day` 跳转日结页，无需从快照 ID 推导日期。
- [x] 连续日期分页无遗漏、无重复，并兼容旧快照 ID 游标输入。
- [x] OpenAPI、API.md、专项测试与完整 JAR 构建完成。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 以失败测试定义连续日期、状态、唯一可操作日与分页。
- [x] T02 实现营业日游标列表并保持旧游标输入兼容。
- [x] T03 同步 API 契约和消费者交接。
- [x] T04 专项回归、全量披露、JAR 打包与接受门禁。

## Business Invariants

- Applicable invariant IDs: INV-CLOSE-SEQ-001, INV-CLOSE-SEQ-002
- New invariant candidates: none

## Impact Map Authority

- Impact map path: `docs/work-items/WI-068/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-068/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: none; executable gate pending.

## Acceptance Decision

ACCEPTED：后端范围的实现、专项测试、契约同步和完整 JAR 打包均已完成。未声明前端已集成或已发布。

## Completion Level

`ACCEPTED`
