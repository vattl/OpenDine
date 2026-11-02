# WORK ITEM — WI-027

## Request

修复线上 `GET /cashier/receivables/eligible-accounts` 返回 Spring 404 的问题，将已验收的商户、挂账、权威流水和日结能力安全集成到当前主集成分支并生成可部署 JAR。

## Type

REPAIR

## State

INTEGRATED

## Requirement Contract

### Goal

当前集成版本必须真实注册挂账接口，使收银端能够查询当前门店可用授信账户；同时不得因重复 Flyway 版本、文档冲突或支付逻辑回退导致应用启动或财务一致性失败。

### Current behavior

线上请求命中标准 Spring 404。仓库证据显示当前集成分支不包含挂账 Controller；相关实现仅存在于 `codex/jsapi-settlement-integrity` 的两笔已验收提交中，且其 `V024/V025/V026` 与集成分支现有迁移号冲突。

### Target behavior

- 集成商户/挂账、JSAPI 结算、权威资金流水与日结一致性提交。
- `/cashier/receivables/eligible-accounts` 被 Spring 注册并受 `receivable:view` 权限与门店范围保护。
- 将待集成的三份数据库迁移顺延为当前未占用的 `V027/V028/V029`，保持执行顺序。
- 解决 API 文档与现有版本中心变更的冲突，不丢失任一侧契约。
- 全量测试、迁移唯一性检查、OpenAPI 解析和可运行 JAR 构建通过。

### Must preserve

- 当前集成分支已有会员钱包、版本中心、报表和 Native 支付修复。
- Cloud/KDS 架构不受影响。
- 不直接部署线上，不伪造 RELEASED 状态。

### Acceptance criteria

- [x] Controller、权限映射、OpenAPI 与初始化权限 SQL 均包含目标路由。
- [x] Flyway 迁移版本唯一，新增迁移为 V027/V028/V029。
- [x] 两侧功能通过编译和全量回归。
- [x] 生成新的可运行 JAR，并明确部署/迁移要求。

## Acceptance Decision

ACCEPTED

## Business Invariants

- INV-INT-001：同一仓库不得存在重复 Flyway 迁移版本。
- INV-INT-002：已验收的订单、支付、会员和版本能力不得在集成时被静默覆盖。
- INV-REC-001：挂账可用账户必须按当前门店、状态和授信范围筛选。
- INV-FIN-001：权威流水仍先于订单资金投影写入。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-027/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-027/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

INTEGRATED
