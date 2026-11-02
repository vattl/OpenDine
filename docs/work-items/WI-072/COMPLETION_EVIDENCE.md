# Completion Evidence — WI-072

## 1. 交付产物

| 类型 | 路径 / 标识 | 说明 |
|---|---|---|
| 接口映射中心 | `src/main/java/com/lanf/config/ApiPermissionMapping.java` | 补全遗漏的 90+ 端点映射，注入细粒度多权限候选 |
| 路由放行配置 | `src/main/java/com/lanf/config/WebAppConfigurer.java` | 显式放行 `/config/contact`、`/config/subscribe-templates`、`/config/app`、`/help/**` |
| 拦截器保护 | `src/main/java/com/lanf/interceptor/SysInterceptor.java` | 扩展 `isLegacyAdminPath` 保护历史 `/activity/getAllPopup` |
| 数据库迁移 | `src/main/resources/db/migration/V049__api_permission_granularity_and_audit.sql` | 增量维护 `t_permission` 与 `t_api_permission` 并赋权管理角色 |
| 数据库初始化 | `docs/init_api_permission.sql` | 全量同步最新接口映射规则 |
| 自动化安全测试 | `src/test/java/com/lanf/config/ApiPermissionMappingCompletenessSecurityTest.java` | 扩展测试覆盖全部新增细粒度端点映射 |
| API 契约文档 | `docs/API.md`<br>`docs/openapi.yaml` | 同步记录 `v1.2.335 / WI-072` 全量接口权限审计与细粒度权限码规范 |
| 构建产物 | `target/diancan-0.0.1-SNAPSHOT.jar` | 由 Maven clean package 构建的可执行应用 Jar |

## 2. 验证记录

### 2.1 端点审计扫描验证
- 扫描 102 个 Controller 类，共计 620 个端点；
- 193 个端点公开免签（`EXCLUDE_PATHS`）；
- 6 个端点管理员登录态专属（`AUTHENTICATED_ONLY_PATHS`）；
- 421 个端点严格映射细粒度权限码；
- 0 个未保护或未配置端点（UNMAPPED = 0）。

### 2.2 自动化测试
- `ApiPermissionMappingCompletenessSecurityTest`：2 个测试全部通过；
- `DbApiPermissionMappingSecurityTest`：3 个测试全部通过；
- `SysInterceptorPermissionMappingSecurityTest`：10 个测试全部通过。
