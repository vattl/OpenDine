# Security Audit — WI-007

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Evidence

- 排序 SQL 全部使用 MyBatis 参数绑定，无动态 SQL 拼接。
- 写操作仅使用拦截器解析后的门店上下文，并验证菜品与当前门店的挂载关系。
- 缺失或无效门店上下文 fail closed；跨门店写入条件同时包含 `shop_id` 与资源 ID。
- 本次新增/修改范围的敏感信息模式扫描无命中。
