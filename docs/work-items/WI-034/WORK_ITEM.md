# WORK ITEM — WI-034

## Request

修复套餐商业化字段已被 Java 实体查询、但生产 `t_combo` 表尚未创建对应列而导致菜单接口抛出 `Unknown column 'limit_per_order'` 的故障。

## Type

BUG

## State

ACCEPTED

## Requirement Contract

### Goal

部署套餐商业化代码时，数据库迁移必须先以无损、幂等方式补齐 `t_combo` 的全部商业化字段，使套餐查询、管理与下单不因数据库结构漂移失败。

### Current behavior

- `Combo` 实体已声明 `limit_per_order` 等 11 个字段，MyBatis-Plus 自动把它们加入查询列。
- 正式版本迁移目录没有对应迁移，生产查询因此在第一列缺失处失败。
- 工作区只有依赖外部存储过程的手工 SQL，不能证明可由正式迁移链独立执行。

### Target behavior

- 新增正式 V034 迁移，独立、可重复地补齐全部 11 个字段，不依赖预先存在的存储过程。
- 全量建库基线与增量同步脚本包含同一字段集合和兼容默认值。
- 自动化测试验证迁移资源、完整字段集合和幂等保护。

### Must preserve

- 存量 `t_combo` 数据不删除、不重建。
- 旧套餐在新增字段默认值下保持原有可售行为。
- 不修改现有 API 路径、请求或响应结构。
- 不覆盖当前工作区内尚未提交的套餐商业化实现。

### Acceptance criteria

- [x] V034 能为旧 `t_combo` 表补齐全部商业化列。
- [x] 对已存在字段重复执行不会报重复列错误。
- [x] V034 不依赖 `p_add_col_if_missing` 等外部过程。
- [x] `docs/db_diancan.sql` 与 `docs/db_schema_additive_sync.sql` 同步。
- [x] 迁移回归测试及相关套餐测试通过，JAR 可成功打包。

### Open product questions

无。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 用测试锁定迁移资源与字段完整性。
- [x] T02 添加独立幂等 V034 迁移。
- [x] T03 同步全量建库与增量同步基线。
- [x] T04 运行迁移、套餐专项测试和完整打包。

## Verification Evidence

见 `TEST_REPORT.md`、`REVIEW_REPORT.md`、`SECURITY_AUDIT.md`、`ACCEPTANCE_REPORT.md` 和 `COMPLETION_EVIDENCE.md`。

## Review

PASS。

## Acceptance Decision

ACCEPTED（仓库修复完成；生产执行 V034 属于发布步骤，尚未执行）。

## Consumer Handoffs

无 API 合同变化；部署方必须在启用包含新实体字段的 JAR 前执行 V034。

## Business Invariants

- INV-COMBO-034-01：应用读取的套餐持久化字段必须先存在于数据库。
- INV-COMBO-034-02：迁移只能增量加列，不得损坏或重建存量套餐。
- INV-COMBO-034-03：旧套餐在默认值下保持不限购、全时段、全用餐方式、允许叠券。

## Completion Level

ACCEPTED（非 INTEGRATED、非 RELEASED）
