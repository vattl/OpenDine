# Security Audit — WI-008

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Evidence

- 所有查询都使用拦截器解析后的当前门店 ID；请求 `shopId` 不一致时在数据库查询前拒绝。
- 显式 `date` 或 `startTime/endTime` 查询要求当前 JWT 管理员精确拥有 `admin:super`；权限服务缺失、返回空或抛出运行时异常均失败关闭。
- 自定义范围必须成对、顺序合法、最大 31 天，避免无界历史读取；查询值由 MyBatis 参数绑定，不拼接用户输入。
- 权限迁移清理非 `super_admin` 的 `admin:super` 角色授权，并仅向 `super_admin` 授权。
- 变更文件敏感信息人工复核未发现新增凭据或密钥。
