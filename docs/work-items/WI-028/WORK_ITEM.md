# WORK ITEM — WI-028

## Request

修复 `GET /admin/app/versions` 返回 403「接口权限未配置」，并完整登记版本策略管理端点权限。

## Type

BUG

## State

INTEGRATED

## Requirement Contract

### Goal

让具备 `admin:super` 的管理员能够进入版本管理中心，同时保持非超管失败关闭。

### Current behavior

Controller 已实现列表、保存、启停和删除，但统一权限映射及数据库种子未登记这些路由，请求在进入 Controller 前返回 403。

### Target behavior

- 四个版本管理端点均映射到 `admin:super`。
- 内置映射与数据库 `t_api_permission` 迁移一致。
- 公开版本查询 `/admin/app/version` 保持既有兼容语义。
- API 文档同步，回归测试及可运行 JAR 构建通过。

### Must preserve

- Controller 内部二次 `admin:super` 校验。
- 非超管不得查询或修改全平台版本策略。
- 不直接修改已执行的 V026，使用新的纠正迁移。

### Acceptance criteria

- [x] 四个管理端点有显式内置权限映射。
- [x] V030 幂等补齐数据库权限映射。
- [x] 权限完整性测试覆盖四个端点。
- [x] API 文档、全量回归与 JAR 构建通过。

## Acceptance Decision

ACCEPTED

## Business Invariants

- INV-SEC-001：未配置的后台接口必须失败关闭。
- INV-SEC-002：版本发布与策略修改仅允许 `admin:super`。
- INV-DB-001：已发布迁移不可改写，纠错必须追加新版本。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-028/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-028/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

INTEGRATED
