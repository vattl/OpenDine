# Security Audit — WI-067

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Review Findings

- 门店范围始终来自已解析 `shopId`，所有新增序列与水位查询均限定 `shop_id`。
- 未新增认证入口或权限绕过；`daily:settle` 入口权限保持不变。
- `force` 不允许绕过日结时序，避免通过高权限参数制造财务序列空洞。
- 409 错误只返回营业日元数据，不泄露凭据、密码或资金明细。
- 重开仍要求二次密码；历史重开被服务端拒绝。
- 变更未引入密钥、令牌、动态 SQL 字符串拼接或新的第三方依赖。

## Residual Risk

- 并发保证依赖当前数据库对 Spring `SERIALIZABLE` 事务的实现；上线后应监控 409 冲突率与数据库重试情况。
