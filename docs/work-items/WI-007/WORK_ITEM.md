# WORK ITEM — WI-007

## Request

完善菜品分类排序与菜品排序接口，消除多门店数据下的跨店干扰、分类混排和并发不确定性。

## Type
BUG / REPAIR

## State
ACCEPTED

## Requirement Contract
### Goal
排序结果必须按当前门店隔离、稳定、原子，并与菜单实际展示层级一致。

### Current behavior
- 分类排序重写全局 `t_category.sorting`，任一门店操作都会影响其他门店。
- 门店菜品排序虽然写 `t_dish_shop.sorting_override`，但把全店所有分类的菜品放入同一排序空间。
- 两个接口逐行更新且无事务/门店级串行化，并发请求可能交错或留下部分结果。

### Target behavior
- `POST /admin/category/sort` 在当前门店的独立分类排序空间内重排。
- `POST /admin/dish/sort` 只在当前门店、被拖菜品的生效分类内重排。
- 同一门店排序串行、全量连续化为 `1..n`，相同旧排序值以主键兜底形成稳定全序。
- 请求/响应字段保持兼容；缺失门店上下文或资源不属于当前门店时明确失败。

### Must preserve
- `id`、`targetIndex` 请求字段和 `R` 响应结构不变。
- 菜品门店排序只写门店覆盖，不改总部 `t_dish.sorting`。
- 排序成功后继续发送 `dish_catalog_changed(action=sort)`。

### Acceptance criteria
- [x] 两家门店可对同一分类集合独立排序，互不改写。
- [x] 菜品只在当前门店及其生效分类内排序，不影响其他分类或门店。
- [x] 重复/NULL/越界排序输入得到唯一连续结果。
- [x] 排序过程具备事务原子性与同店并发串行化。
- [x] OpenAPI、API.md、数据库迁移说明同步。
- [x] 回归测试、完整测试与 `mvn clean package -DskipTests` 通过。

### Open product questions
NONE。按现有连锁约束，`/admin/category/*` 与 `/admin/dish/*` 均必须已有门店上下文。

## Impact Summary
Link: `IMPACT_MAP.md`

## Design Summary
Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices
- [x] T01 以失败测试固化门店分类隔离、分类内菜品排序和缺失上下文行为。
- [x] T02 实现门店分类排序覆盖、事务锁与读取排序传播。
- [x] T03 完善菜品分类内稳定重排和事务锁。
- [x] T04 同步数据库/API 文档并完成验证、审查与接受。

## Verification Evidence
见 `TEST_REPORT.md`、`SECURITY_AUDIT.md`、`COMPLETION_EVIDENCE.md`。

## Review
五轴复核（正确性、安全性、性能、可维护性、部署）PASS；无 HIGH/CRITICAL 未决项。

## Acceptance Decision
ACCEPTED

## Consumer Handoffs
请求/响应结构兼容；语义变更记录于 `CONTRACT_DELTA.md`，无需消费者改造。

## Integration / Release
本 Work Item 目标到 ACCEPTED；部署/发布不在本次授权范围。

## Related IDs
Workstream: category-dish-shop-sort
UI: NONE
Capability: shop-scoped-menu-ordering
Commits: PENDING

## Business Invariants

- Applicable invariant IDs: INV-SORT-01, INV-SORT-02, INV-SORT-03, INV-SORT-04
- New invariant candidates: 门店菜单排序不得修改其他门店或总部排序空间。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-007/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-007/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`

