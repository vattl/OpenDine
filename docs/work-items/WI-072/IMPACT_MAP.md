# Impact Map — WI-072

## Authoritative Owner

`ApiPermissionMapping` / `DbApiPermissionMapping` / `SysInterceptor` (鉴权拦截器与接口权限中心)。

## Layer Coverage

| 层级 | 路径 / 文件 | 影响类型 | 说明 |
|---|---|---|---|
| 配置清单 | `src/main/java/com/lanf/config/ApiPermissionMapping.java` | MODIFY | 补充遗漏接口映射，注入细粒度权限码候选 |
| 路由配置 | `src/main/java/com/lanf/config/WebAppConfigurer.java` | MODIFY | 补充公共只读端点至排除清单 |
| 拦截器 | `src/main/java/com/lanf/interceptor/SysInterceptor.java` | MODIFY | 完善 legacy 后台路由匹配（`/activity/getAllPopup`） |
| 数据库迁移 | `src/main/resources/db/migration/V049__api_permission_granularity_and_audit.sql` | CREATE | 新增权限字典项与全量补全映射 |
| 数据库初始化 | `docs/init_api_permission.sql` | MODIFY | 全量同步最新接口权限映射 |
| 安全测试 | `src/test/java/com/lanf/config/ApiPermissionMappingCompletenessSecurityTest.java` | MODIFY | 扩充测试用例覆盖新增分类与细粒度权限 |
| 契约文档 | `docs/openapi.yaml` | MODIFY | 增加权限码说明与版本记录（v1.2.335 / WI-072） |
| 接口文档 | `docs/API.md` | MODIFY | 同步最新接口权限码与说明 |

## 外部依赖与兼容性
- 向后兼容：所有细粒度权限均采用 `coarse:perm|fine:perm` 组合支持，已有粗粒度角色权限完全兼容不受影响。
- 数据库表：通过 Flyway `V049` 向 `t_permission` 与 `t_api_permission` 执行增量插入与更新，无需重建表结构。
