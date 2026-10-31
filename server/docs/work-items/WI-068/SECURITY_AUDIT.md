# Security Audit — WI-068

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Findings

- HTTP 入口继续使用 `AdminShopRequest` 解析授权门店，权限仍为 `daily:settle`。
- 日结序列查询始终限定 `shop_id`；旧快照 ID 游标只有在快照属于当前门店时才可转换日期，避免跨门店侧信道。
- `can_close` 只是展示提示，不能绕过 pre-check/settle 的服务端 409 时序守卫。
- PENDING 项不伪造快照、金额、经办人或水位数据，财务事实字段保持 null/空摘要。
- 无新增动态 SQL、密钥、依赖、认证入口或数据库迁移。

## Residual Risk

客户端若错误地把新增 PENDING 行当成已结快照会产生展示问题；通过 `close_state`、nullable 契约和消费者 handoff 管理，不影响后端资金写入安全。
