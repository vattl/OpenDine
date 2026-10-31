# Security Audit — WI-035

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Review

- 加菜桌台金额查询限定当前门店与当前桌号未结订单，且使用参数化 MyBatis-Plus 查询，无 SQL 注入风险。
- 店内用户权限与加菜越权校验（checkOrderPermission）依然严格生效，未破坏多租户门店隔离。
- 无敏感凭证或私钥暴露。
- 事务一致性保持：addDishes 异常时回滚全部订单与桌台变更。
