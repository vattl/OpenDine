# 系统设置接口开发规范（子代理共享规格）

本规范约束《系统设置后端协调文档》（`G:\Mini Program\my_project_admin_panel\admin_panel_flutter\docs\backend_coordination_system_settings.md`）各模块的云端实现。**先读参考实现再动手**：
- 参考模块：`src/main/java/com/lanf/settings/**`（entity/mapper/service/controller）
- 参考测试：`src/test/java/com/lanf/settings/ShopSettingsServiceTest.java`
- 参考 SQL：`docs/db_migration_system_settings.sql`

## 0. 硬性约束
- 工作目录：`G:\Mini Program\my_project_server\server`（repo 根为其上一级）。
- **只允许新建文件**（自己的包 + 自己的 `docs/db_migration_<module>.sql` + 自己的测试）。
- **禁止修改**：`Application.java`、`GlobalApiExceptionHandler.java`、`ApiPermissionMapping.java`、`WebAppConfigurer.java`、`SysInterceptor.java`、`pom.xml`、其他模块的任何文件。
- 不要 git commit；不要跑全量测试套件；只跑自己的测试类。
- 构建命令：`.\mvnw.cmd -q "-Dtest=<你的测试类名>" test`（`-Dtest` 必须带引号）。

## 1. 技术栈与模式
- Spring Boot 2.3 + MyBatis-Plus 3.3.2（BaseMapper 即可，分页插件已配）。JDK8 语法。
- 实体：`@TableName("t_xxx")` + `@TableId(type = IdType.AUTO)` + Lombok `@Data`；**字段用 snake_case 时 Lombok 生成 snake_case 访问器**（`updated_by` → `getUpdated_by()/setUpdated_by(...)`）——这是本项目惯例，勿改成驼峰。
- Mapper：`public interface XxxMapper extends BaseMapper<Xxx> {}` 放 `com.lanf.<module>.mapper`（**已加入 @MapperScan，无需注册**）。
- 时间：库内 `LocalDateTime`；响应一律转 ISO8601 带时区字符串：`LocalDateTime.now(ZoneId.of("+08:00")).atZone(ZONE).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME)`。

## 2. 响应与错误
- 成功：返回 `com.lanf.entity.R`（默认 code=0），`r.put(k, v)` 填充。
- 列表：R 顶层放 `page/pageSize/total/items`（工具 `com.lanf.common.PageResult.of(page,pageSize,total,items)`，取其字段逐个 put）。
- 业务失败：抛 `com.lanf.common.ApiException(httpStatus, "STABLE_ERROR_CODE", msg, data)`——全局处理器已接好，会以真实 HTTP 状态码 + body `{code, error, msg, data}` 返回。常用：400 参数/校验、403 权限、404 不存在、409 冲突。
- 文档 §4 的稳定错误码必须原样使用（如 `SETTINGS_VERSION_CONFLICT`）。

## 3. 鉴权与上下文（拦截器已统一处理，控制器直接取）
- 当前管理员：`currentRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID)`（Integer）。
- 当前门店：`currentRequest.getAttribute(SysInterceptor.ATTR_RESOLVED_SHOP_ID)`（Integer；/admin/** 除豁免前缀外强制存在）。注入方式：`@Autowired private HttpServletRequest currentRequest;`（见 AdminSettingsController）。
- 缺失防御：取不到时抛 `ApiException(4001, "SHOP_CONTEXT_MISSING", ...)`。
- 写操作审计：`securityAuditService.recordPrivilegedAction(currentRequest, shopId, "<module>", "<action>", targetId, adminId, snapshotMap, reason)`，包 try/catch 失败不阻断（见 AdminSettingsController.audit）。

## 4. 权限码与接口映射（SQL 注册）
在 `docs/db_migration_<module>.sql` 中（参考 db_migration_system_settings.sql 第 3-5 节）：
1. `INSERT IGNORE INTO t_permission (permission_code, permission_name, module, remark, sort_order) VALUES ...`
2. `INSERT IGNORE INTO t_api_permission (method, path_pattern, permission_code) VALUES ...`（GET 可用 `a:view|a:manage` 双码；写接口只给 manage 码）
3. `INSERT IGNORE INTO t_role_permission ... WHERE r.role_code='super_admin'` + 门店角色（`shop_manager','shop_admin','store_manager'`）按需。
- 权限码分配表：printing→`printing:view/printing:manage`；通知→`notifications:view/notifications:manage`；首单→`marketing:firstorder:view/marketing:firstorder:manage`；权限→`access:view/access:manage`；库存→`inventory:view/inventory:manage`；报表→`report:view/report:export`；日志→`log:view/log:archive/log:export`；支付→`payment:view/payment:manage`。
- SQL 要求幂等（IF NOT EXISTS / INSERT IGNORE）、utf8mb4、全列 COMMENT。

## 5. 通用业务约束（文档 §1）
- 配置类表带 `version` 乐观锁：`UPDATE ... WHERE id=? AND version=?` 影响 0 行 → `ApiException(409, "<MODULE>_VERSION_CONFLICT", "配置已被他人修改", 最新版本摘要)`（参考 ShopSettingsService.versionConflict）。
- 敏感字段（密钥/凭据/商户号）读取时脱敏（如只回 `****` + 尾 4 位），绝不明文回传。
- 所有新表：id 自增主键、`shop_id` 隔离维度、`created_at/updated_at`（DEFAULT CURRENT_TIMESTAMP / ON UPDATE）。

## 6. 测试要求
- JUnit5 + Mockito 纯单测（不起 Spring 容器）：`mock(XxxMapper.class)` + `ReflectionTestUtils.setField(service, "fieldName", mock)`（参考 ShopSettingsServiceTest）。
- 至少覆盖：正常路径、版本冲突 409、参数校验 400、（如适用）脱敏与幂等。类放 `src/test/java/com/lanf/<module>/`。
- 完成前必须让自己测试类全绿。
