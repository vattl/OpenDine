# WORK ITEM — WI-061

## Request

落实审计方案下一阶段：将审批授权收紧到具体动作权限，并为现场授权、二维码创建/确认及凭据失败增加跨实例一致的持久化频率限制；输出前端适配交接。

2026-10-24 生产缺陷回补：`POST /cashier/access/authorize` 在数据库未完整落地审批表、严格绑定字段或 V040 限流表时返回数据访问 500；增加高版本收敛迁移与全量建库基线覆盖。

## Type
REPAIR / SECURITY / API

## State
ACCEPTED

## Requirement Contract

### Goal
审批必须由拥有目标动作审批权的人员执行；高频请求和凭据猜测必须被稳定拒绝并留下审计证据。

### Current behavior
- 现场授权和二维码同意接受 `access:approve`、`order:operate`、`admin:manage` 等宽泛权限。
- 二维码拒绝未执行同等级权限校验。
- PIN 失败计数采用读改写，存在并发丢失更新；密码授权和二维码入口没有跨实例限流。
- 客户端无法从标准错误数据得知剩余等待时间。

### Target behavior
- 现场授权及二维码 AGREE/REJECT 均要求精确的 `<业务权限>:approve`，超级管理员保持受控旁路。
- 既有角色通过迁移获得与当前业务权限对应的精确审批权限，避免部署后意外失权。
- 现场授权、二维码创建和二维码确认使用数据库作为多实例统一限流权威。
- PIN/密码失败按门店和账号哈希建立独立防爆破窗口；成功后清零。
- 超限统一返回 HTTP 429、`ACCESS_APPROVAL_RATE_LIMITED`、`retryAfterSeconds` 和 `rateLimitScope`，拒绝原因进入安全审计。
- 不记录 PIN、密码、审批 token 或原始账号限流键。

### Must preserve
- INV-APPROVAL-001 的业务对象、金额、终端绑定与一次性核销。
- 二维码 120 秒有效期、轮询状态机和加密信封。
- 超级管理员能力，但不得绕过限流和凭据校验。
- 现有接口路径及成功响应字段。

### Acceptance criteria
- [x] 宽泛权限不能批准或拒绝具体动作；精确审批权限和超级管理员可以。
- [x] 同一限流键跨两个服务实例共享计数，超限返回标准 429 数据。
- [x] PIN/密码错误累计到阈值后锁定窗口内拒绝，成功校验会清零失败窗口。
- [x] AGREE 与 REJECT 权限行为一致，所有拒绝均可审计且无敏感值。
- [x] 权限迁移、OpenAPI、API.md 和前端交接同步。
- [x] 聚焦测试与完整 JAR 打包通过。

### Open product questions
无。安全绑定 v1 的关闭仍以客户端 v2 使用证据为前提，不在本 Work Item 强制切断。

## Impact Summary
Link: `IMPACT_MAP.md`

## Design Summary
Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices
- [x] T01 RED：精确权限、AGREE/REJECT、限流和凭据失败测试。
- [x] T02 实现权限策略、持久化限流、原子失败计数与审计。
- [x] T03 增加权限/限流迁移，同步 API 文档和前端交接。
- [x] T04 验证、复核、验收和完整打包。
- [x] T05 RED：证明当前迁移链缺少可独立收敛的审批最新结构。
- [x] T06 增加 V043 审批结构收敛迁移并同步全量/增量建库基线。
- [x] T07 验证迁移契约、相关回归、JAR 与接受门禁。

## Verification Evidence
见 `TEST_REPORT.md`、`SECURITY_AUDIT.md` 和 `COMPLETION_EVIDENCE.md`。

## Review
PASS

## Acceptance Decision
ACCEPTED

## Consumer Handoffs
客户端改造见 `CONTRACT_HANDOFF.md` 和 `FRONTEND_ADAPTATION_GUIDE.md`。

## Integration / Release
目标为仓库 ACCEPTED；不宣称已部署、INTEGRATED 或 RELEASED。

## Business Invariants
- Applicable invariant IDs: INV-APPROVAL-001
- New invariant candidates: NONE

## Impact Map Authority
- Impact map path: `docs/work-items/WI-061/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix
- Scenario matrix path: `docs/work-items/WI-061/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0（计划场景均映射到待执行测试）

## Implementation Ready
- Status: `YES`
- Blockers: NONE

## Completion Level
`ACCEPTED`
