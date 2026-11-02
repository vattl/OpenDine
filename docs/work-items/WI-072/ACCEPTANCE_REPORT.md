# Acceptance Report — WI-072

Decision: ACCEPTED

## 1. 验收结论
- **状态**: ACCEPTED
- **决议**: 经过全系统 620 个控制器端点的全面审计与补全、细粒度权限码分类与字典完善、Flyway 增量与全量初始化 SQL 同步、全量安全回归测试通过、OpenAPI 与 API 文档同步以及可执行 JAR 包打包成功，WI-072 符合全部验收准则。

## 2. 验收清单核对

| 准则项 | 状态 | 验证说明 |
|---|---|---|
| 完成全系统 Controller 端点扫描并消除未配置隐患 | PASS | 扫描 102 个控制器类 620 个端点，UNMAPPED 数量归零 |
| 细粒度权限码分类设计与实现 | PASS | 细化套餐管理、发票开具/查询、高级库存、营销活动、通知规则等细粒度分类 |
| 历史角色向后兼容性 | PASS | 采用 `coarse:perm|fine:perm` 管道候选，已有粗粒度角色权限完全兼容 |
| Flyway 迁移脚本 V049 创建 | PASS | 创建 `V049__api_permission_granularity_and_audit.sql` 并同步 `init_api_permission.sql` |
| 接口白名单与历史兼容端点安全收口 | PASS | `WebAppConfigurer.java` 放行只读 FAQ 与配置，`SysInterceptor.java` 保护 `/activity/getAllPopup` |
| 自动化安全测试全部通过 | PASS | `ApiPermissionMappingCompletenessSecurityTest` 等 15 个测试 100% PASS |
| API 文档与 OpenAPI 契约同步 | PASS | `docs/API.md` 与 `docs/openapi.yaml`（v1.2.335 / WI-072）已更新 |
| Maven 打包产出可执行 JAR | PASS | `mvn clean package -DskipTests` 生成 `target/diancan-0.0.1-SNAPSHOT.jar` |
