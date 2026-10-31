# Scenario Matrix — WI-072

## 1. 测试用例矩阵

| 场景编号 | 场景描述 | 输入条件 | 预期结果 | 验证状态 |
|---|---|---|---|---|
| SC-001 | 新增营销首单活动端点权限校验 | 请求 `/admin/marketing/first-order/campaigns` 等接口 | 正确匹配 `marketing:firstorder:view` / `manage` | VERIFIED |
| SC-002 | 高级库存端点权限校验 | 请求 `/admin/inventory/*` 系列接口 | 正确匹配 `inventory:view` / `inventory:manage` | VERIFIED |
| SC-003 | 归档日志与导出权限校验 | 请求 `/admin/logs/archive-search`、`/admin/logs/exports` | 正确匹配 `log:archive`、`log:export` | VERIFIED |
| SC-004 | 报表导出权限校验 | 请求 `/admin/reports/exports` | 正确匹配 `report:export` | VERIFIED |
| SC-005 | 通知规则管理端点权限校验 | 请求 `/admin/notifications/rules` 等 | 正确匹配 `notifications:view` / `manage` | VERIFIED |
| SC-006 | 系统设置概览与覆盖端点权限校验 | 请求 `/admin/settings/store` 等 | 正确匹配 `settings:view` / `manage` | VERIFIED |
| SC-007 | 套餐与发票细粒度权限校验 | 请求 `/admin/combo/*`、`/admin/order/invoice/*` | 支持细粒度权限与粗粒度双向命中 | VERIFIED |
| SC-008 | POS 别名接口权限校验 | 请求 `/api/pos/*` 系列别名路由 | 正确匹配收银与桌台权限 | VERIFIED |
| SC-009 | 未知未登记端点失败关闭 | 请求未登记的 `/admin/unmapped-path` | 严格拦截并返回 403 `接口权限未配置` | VERIFIED |
