# WORK ITEM — WI-072

## Request

新开发的接口没配置权限，请审计所有接口，分类补全权限码，颗粒度要细

## Type

SECURITY / RBAC / PERMISSION_AUDIT

## State

ACCEPTED

## Requirement Contract

### Goal

1. 全面审计系统所有 Controller 端点（覆盖后台管理端 `/admin/**`、收银台 `/cashier/**`、移动/桌面 POS 别名 `/api/pos/**`、历史兼容接口及 C 端公开接口）；
2. 识别并消灭所有由于未登记权限导致的 403 `接口权限未配置` 风险，补全全部遗漏端点的接口-权限映射（`ApiPermissionMapping.java` 与数据库 `t_api_permission`）；
3. 权限细粒度化（Fine-Grained Permission）：
   - 按业务领域与操作维度细化分类（如套餐管理 `dish:manage:combo`、电子发票 `order:invoice:create` / `order:invoice:view`、库存扩展 `inventory:view` / `inventory:manage`、首单活动 `marketing:firstorder:view` / `marketing:firstorder:manage`、日志归档与导出 `log:archive` / `log:export`、通知规则 `notifications:view` / `notifications:manage`、设置管理 `settings:view` / `settings:manage`、对账操作 `reconciliation:view` / `reconciliation:operate` 等）；
   - 使用多权限候选语法（`coarse:perm|fine:perm`）确保向后完全兼容已有角色（超管/店长/收银），同时赋予新角色细粒度最小特权授权能力；
4. 数据与代码权威同步：
   - 编写 Flyway 数据库迁移脚本 `V049__api_permission_granularity_and_audit.sql`，录入所有补全映射与权限字典项；
   - 同步更新 `ApiPermissionMapping.java`、`docs/init_api_permission.sql`；
   - 同步更新 `WebAppConfigurer.java` 确保公开公共配置/帮助接口显式放行；
5. 编写并运行自动化安全与完整性回归测试，确保 100% 通过；
6. 严格履行硬性交付要求：同步更新 `docs/API.md`、`docs/openapi.yaml`，并执行 `.\mvnw.cmd clean package -DskipTests` 生成可运行 JAR。

### Current behavior

1. 近期新增与重构的多个模块（如营销首单活动、高级库存管理 BOM/采购/供应商/调拨/仓库、日志归档检索与导出、报表导出、通知规则、系统设置门店覆盖、支付渠道测试与停用影响判定、POS别名路径等）未在 `ApiPermissionMapping.java` 与 `t_api_permission` 中配置权限；
2. 管理员访问未配置端点时，`SysInterceptor` 执行失败关闭，返回 403 `接口权限未配置`；
3. 部分既有端点仅映射到宽泛的大粗粒度权限（如 `dish:manage`、`order:operate`），无法针对套餐、发票等细分业务进行细粒度授权。

### Target behavior

1. 所有后台及收银 Controller 端点 100% 具备确切的权限映射或白名单豁免；
2. 细粒度权限码定义完善，支持 `coarse:perm|fine:perm` 双向兼容；
3. `ApiPermissionMapping.inventory()` 与数据库 `t_api_permission` 保持严格一致，杜绝漂移；
4. 自动化安全测试与单元测试覆盖全部新增端点与细粒度权限判定；
5. OpenAPI 与 API 文档同步更新，Maven 打包成功。

### Acceptance criteria

- [x] 完成全系统 Controller 端点静态与动态扫描，查漏补缺；
- [x] `ApiPermissionMapping.java` 补齐所有遗漏的 `/admin/**`、`/cashier/**`、`/api/pos/**` 接口映射；
- [x] 套餐管理、电子发票、高级库存、日志归档导出、通知规则、报表导出、设置管理、渠道对账等完成细粒度权限分类；
- [x] 创建 Flyway 迁移脚本 `V049__api_permission_granularity_and_audit.sql`，包含 `t_permission` 与 `t_api_permission`；
- [x] 同步更新 `docs/init_api_permission.sql`；
- [x] 更新 `ApiPermissionMappingCompletenessSecurityTest.java` 覆盖全部新增与细粒度接口映射；
- [x] `.\mvnw.cmd test` 相关安全与鉴权测试 100% PASS；
- [x] 同步更新 `docs/API.md` 与 `docs/openapi.yaml`；
- [x] 执行 `.\mvnw.cmd clean package -DskipTests` 打包成功生成可运行 JAR。

## Impact Summary

见 `IMPACT_MAP.md`。

## Design Summary

见 `IMPLEMENTATION_DESIGN.md`。

## Tasks / Vertical Slices

- [x] T01 审计全量 Controller 端点并设计细粒度权限码分类表。
- [x] T02 更新 `ApiPermissionMapping.java` 补齐端点映射与细粒度多权限候选。
- [x] T03 创建 Flyway 迁移脚本 `V049__api_permission_granularity_and_audit.sql` 并同步 `docs/init_api_permission.sql`。
- [x] T04 更新 `WebAppConfigurer.java` 显式放行公共配置与帮助接口，完善 `SysInterceptor` legacy 路径保护。
- [x] T05 编写与扩充自动化测试（`ApiPermissionMappingCompletenessSecurityTest.java` 等）。
- [x] T06 同步 `docs/API.md`、`docs/openapi.yaml` 并执行全量 Maven 打包。

## Acceptance Decision

ACCEPTED

## Business Invariants

- 失败关闭（Fail-Closed）：任何未显式配置权限或未在公开白名单的后台/收银接口必须严格拒绝访问（403 接口权限未配置）；
- 权限兼容性（Backward Compatibility）：已分配粗粒度权限的角色（如超管、店长）绝不能因为细粒度权限化而丧失原有功能访问权限；
- 权威一致性（Authority Consistency）：`ApiPermissionMapping.java` 代码清单必须与数据库 `t_api_permission` 和 OpenAPI 契约保持完全一致。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-072/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-072/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: none

## Completion Level

ACCEPTED
