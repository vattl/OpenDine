# Security Audit — WI-020

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Threats reviewed

- 明文凭据落库：生产默认 fail closed；只有 debug profile 可显式写入兼容 `plain:` 值。
- 跨门店商户使用：运行时默认只解析订单门店；全局模板必须由该门店策略明确启用。
- 配置轮换导致错用新密钥：创建交易时持久化配置 ID/版本，后续动作读取当前或历史快照。
- 删除破坏在途交易：删除改为 RETIRED，历史凭据保留；恢复为显式动作。
- 客户端越权路由：merchantKey 由服务端规则与订单属性决定，不接受客户端跨店覆盖。
- 敏感输出：管理响应只返回掩码和私钥路径引用；示例 SQL 不写入真实密钥。

## Scan notes

对变更后的文档、资源和支付模块执行凭据关键词与高熵值人工复核；命中均为字段名、路径、掩码、迁移列或受控 debug 兼容逻辑，未发现新增可用密钥、PEM 私钥或付款码数据。
