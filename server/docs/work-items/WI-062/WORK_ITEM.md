# WORK ITEM — WI-062

## Request
继续审计整改下一阶段：冻结权限词汇与统一授权决策三态，并消除接口权限映射的运行时双权威。

## Type
REPAIR / SECURITY / API

## State
ACCEPTED

## Requirement Contract

### Goal
授权调用方只消费 `ALLOW / REQUIRE_APPROVAL / DENY` 三态结果；接口入口权限仅由数据库映射决定，代码映射退化为可审计清单。

### Current behavior
- `AccessDecision` 依赖 `allow`、`approvalRequired` 多个布尔值组合表达状态，可能产生歧义。
- `/admin/access/evaluate` 在无 context 时走旧实现，有 context 时走新决策器，同一接口存在两套语义。
- `SysInterceptor` 在数据库未命中时静默回退 `ApiPermissionMapping`，不同环境可能产生不同授权结果。

### Target behavior
- 决策结果显式输出枚举 `outcome=ALLOW|REQUIRE_APPROVAL|DENY`，旧布尔字段保留兼容。
- `/admin/access/evaluate` 所有请求统一进入 `AccessDecisionService`。
- 高风险动作词汇记录入口权限、执行权限和精确审批权限；普通收银拥有入口权限时得到 `REQUIRE_APPROVAL`，没有有效审批不能得到 `ALLOW`。
- `t_api_permission` 是唯一运行时权威；数据库加载失败或路由缺失时失败关闭，不再使用代码清单授权。
- 代码清单保留为迁移/CI 比对输入，并新增自动差异测试。

### Must preserve
- `cashier:operate` 仍允许进入敏感操作和发起审批。
- INV-APPROVAL-001 的上下文绑定与一次性核销。
- 超级管理员、门店范围、账号状态、显式 DENY 优先级。
- 现有接口路径和旧响应布尔字段。

### Acceptance criteria
- [x] 三态结果与旧布尔字段始终一致。
- [x] 普通收银可得到 REQUIRE_APPROVAL，但无有效审批令牌不能得到 ALLOW。
- [x] 单动作权限不隐式授予其他动作。
- [x] 数据库未命中时拦截器失败关闭，代码清单不参与运行时放行。
- [x] DB 初始化数据与代码清单的路由/权限零差异测试通过。
- [x] OpenAPI、API.md、前端交接和完整 JAR 同步完成。

## Business Invariants
- Applicable invariant IDs: INV-APPROVAL-001
- New invariant candidates: INV-AUTHZ-001（三态互斥）、INV-AUTHZ-002（DB 映射单一权威）

## Impact Map Authority
- Impact map path: `docs/work-items/WI-062/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix
- Scenario matrix path: `docs/work-items/WI-062/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0（均已映射到待实现自动化测试）

## Implementation Ready
- Status: `YES`
- Blockers: NONE

## Tasks / Vertical Slices
- [x] T01 RED：三态、发起审批、无效令牌和数据库单一权威测试。
- [x] T02 实现权限词汇、三态决策与统一 evaluate 路径。
- [x] T03 移除运行时内置映射兜底，增加 DB/清单差异门禁。
- [x] T04 同步 API 文档、前端交接、验证与验收。
- [x] T05 导入缺陷回补：V041 权限种子字段由不存在的 `description` 更正为基线字段 `remark`，并增加迁移列契约测试。

## Integration / Release
目标为仓库 ACCEPTED；不宣称已部署、INTEGRATED 或 RELEASED。

## Acceptance Decision
ACCEPTED

