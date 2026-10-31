# Security Audit — WI-072

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: PASS
SAST: PASS

## 1. 审计范围
本次审计针对全系统 620 个 Controller 路由端点的权限配置完整性、权限颗粒度设计、越权防范与失败关闭策略进行全量评估。

## 2. 检查项与审计结论

| 检查项 | 风险等级 | 防护实现 | 审计结论 |
|---|---|---|---|
| **端点未配权限导致的失败关闭 403 异常** | HIGH | 全系统扫描 102 个 Controller 类，审计识别出的 90+ 个端点全部补齐映射，清零未配置风险。 | PASS |
| **越权访问与权限粗放风险** | HIGH | 细化套餐（`dish:manage:combo`）、发票（`order:invoice:create/view`）、高级库存（`inventory:view/manage`）、首单营销（`marketing:firstorder:view/manage`）、通知规则、系统设置与报表导出等细粒度权限码。 | PASS |
| **老旧角色与既有权限兼容性** | MEDIUM | 采用 `coarse:perm|fine:perm` 管道候选策略，历史粗粒度角色无缝兼容，新角色支持最小特权授权。 | PASS |
| **白名单与历史兼容接口越权风险** | MEDIUM | `/activity/getAllPopup` 纳入 `SysInterceptor.isLegacyAdminPath` 保护；公开端点严格限定为只读配置与 FAQ。 | PASS |

## 3. 自动化用例验证
- `ApiPermissionMappingCompletenessSecurityTest`：断言各业务模块端点映射与权限码；
- `SysInterceptorPermissionMappingSecurityTest`：验证未登记端点失败关闭、已登记端点按权限放行与拒绝。
