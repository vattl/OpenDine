# Security Audit — WI-063

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Findings Addressed
- Controller 不再直接组合宽泛 RBAC、密码和 token 校验，六个入口统一进入动作级决策服务。
- 仅精确 execute 可直接执行；入口权限只产生 `REQUIRE_APPROVAL`，不提升为执行权。
- 显式 DENY 不尝试现场审批，防止凭证路径绕过策略拒绝。
- 现场凭证必须生成 bindingVersion=2 token，并按动作、订单、金额、操作者、门店、终端单次核销。
- 畸形 `authorization` 明确返回 401 `ACCESS_CREDENTIALS_REQUIRED`，不会循环产生 REQUIRE_APPROVAL。
- 改价先校验订单和明细，再消费审批令牌，避免无效资源消耗一次性授权。
- V042 不向 cashier 和自定义角色扩散高风险执行权。

## Residual Risk
- 部署若未先执行 V042，角色权限结果可能仍受旧数据影响；必须按“数据库迁移 → 新 JAR”顺序发布。
- 前端在完成三态适配前仍可读取旧 `code/msg`，但无法获得比服务端更多的权限；体验可能退化为普通错误提示。
