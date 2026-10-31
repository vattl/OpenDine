# Security Audit — WI-064

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Findings Addressed
- 收银端订单按已解析 `shop_id` 查询并加行锁，版本冲突摘要不会跨门店返回。
- C 端加菜先验证 openid/同桌权限、门店归属与订单状态，再比较版本，避免用陈旧版本探测未授权订单金额。
- 退菜、改价和优惠在动作审批令牌消费前拒绝陈旧版本；自动化测试验证审批器及下游协作者零调用。
- `expectedVersion` 必须为非负整数；Map 入口的两个别名同时出现时必须一致。
- CAS 只按已授权订单主键和锁定版本推进，失败抛 409 并由事务回滚业务副作用。
- 未引入依赖、动态 SQL 值或敏感信息日志。

## Residual Risk
- 兼容期允许旧客户端省略 `expectedVersion`，此时数据库行锁仍保证写入串行和 revision 单调，但客户端无法获得“基于旧快照操作”的主动冲突提示。
- `/order/addDishes` 的 JSON DTO 兼容两个字段名；客户端应只发送规范字段 `expectedVersion`，避免同时发送两个别名产生解析顺序歧义。
