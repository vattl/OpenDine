# WORK ITEM — WI-060

## Request

落实审计方案阶段 1 的第二切片：消除二维码审批令牌明文落库，同时保持多实例轮询和现有客户端响应契约可用。

## Type
REPAIR / SECURITY

## State
ACCEPTED

## Requirement Contract

### Goal
二维码审批的一次性令牌不得以可直接使用的明文持久化；任意应用实例仍能安全取回已批准令牌并完成原子核销。

### Current behavior
店长同意后，服务将原始 `approvalToken` 与哈希同时写入 `t_access_approval.token_value`，数据库读权限或备份泄露即可直接获得有效令牌。

### Target behavior
- 新令牌仅以 SHA-256 哈希和 AES-256-GCM 加密信封持久化，信封使用审批号作为认证附加数据。
- 所有实例使用同一独立部署密钥解密，轮询接口响应字段保持不变。
- 密钥缺失、密文篡改、审批号错配或哈希不一致均 fail closed，不返回令牌。
- 迁移使历史明文审批失效并清空；数据库无可继续使用的历史明文。
- 修正 WI-059 新增迁移与既有 `V036` 的版本冲突。

### Must preserve
- 120 秒有效期、状态机和 CAS 单次核销。
- `/cashier/access/qr/status` 成功响应仍返回 `approvalToken`。
- 凭证现场授权和非二维码审批不额外持久化原始令牌。
- INV-APPROVAL-001 的严格上下文绑定不回退。

### Acceptance criteria
- [x] 同意二维码审批后持久化值不是原始 token，且使用认证加密。
- [x] 两个使用同一密钥的实例可从数据库信封取回同一 token。
- [x] 不同审批号、篡改信封、错误密钥、缺失密钥或哈希不一致均不泄露 token。
- [x] 历史明文由迁移失效并清空，迁移版本唯一。
- [x] OpenAPI、API.md、部署配置和迁移说明同步。
- [x] 聚焦测试与完整 JAR 打包通过。

### Open product questions
无。方案保持现有客户端接口形态，部署必须为所有实例配置同一独立密钥。

## Impact Summary
Link: `IMPACT_MAP.md`

## Design Summary
Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices
- [x] T01 RED：密码学、跨实例、篡改与服务契约测试。
- [x] T02 实现加密信封、服务接入和迁移清理。
- [x] T03 同步配置/API/运维文档。
- [x] T04 验证、复核、验收和完整打包。

## Verification Evidence
见 `TEST_REPORT.md`、`SECURITY_AUDIT.md` 和 `COMPLETION_EVIDENCE.md`。

## Review
PASS

## Acceptance Decision
ACCEPTED

## Consumer Handoffs
部署配置交接见 `CONTRACT_HANDOFF.md`；客户端无字段或流程变更。

## Integration / Release
目标为仓库 ACCEPTED；不宣称已部署或 RELEASED。

## Business Invariants
- Applicable invariant IDs: INV-APPROVAL-001
- New invariant candidates: NONE

## Impact Map Authority
- Impact map path: `docs/work-items/WI-060/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix
- Scenario matrix path: `docs/work-items/WI-060/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0（计划阶段场景均已映射到待执行验证）

## Implementation Ready
- Status: `YES`
- Blockers: NONE

## Completion Level
`ACCEPTED`
