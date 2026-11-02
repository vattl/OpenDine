# Completion Evidence — WI-062

Status: ACCEPTED

## Delivered
- `AccessDecision` 明确输出互斥 `ALLOW / REQUIRE_APPROVAL / DENY`。
- `AccessService.evaluate` 有无 context 均调用统一决策器并兼容旧响应字段。
- `ActionPermissionVocabulary` 冻结退款、改价、优惠、反结账的入口/执行/审批权限。
- 普通收银可发起动作审批；有效严格绑定令牌才可覆盖动作权限；跨动作权限不扩散。
- `SysInterceptor` 只读取 `t_api_permission`；缺失失败关闭。
- DB 重载失败保留最后成功快照，首次失败为空并失败关闭；启动时输出清单漂移计数。
- V041、`init_api_permission.sql`、OpenAPI、API.md 与前端适配指南已同步。
- V041 权限种子使用基线字段 `remark`；契约测试禁止再次写入不存在的 `description` 字段。

## Verification summary
- Focused authorization suite: 37 tests PASS.
- Expanded approval/permission/controller suite: 89 tests PASS.
- Cross-action follow-up: 13 tests PASS.
- Governance scripts: 5 tests PASS.
- OpenAPI YAML: parsed, version 1.2.316, 517 paths.
- Full package: `mvnw.cmd clean package -DskipTests` PASS.
- Work acceptance gate: PASS.
- Repository package-manifest gate: FAIL on pre-existing broad MANIFEST/unlisted-file drift; recorded in `TEST_REPORT.md`, not treated as a product build failure.
- 2026-10-24 migration regression: 4 focused tests PASS（含先红后绿证据）。
- JAR: `target/diancan-0.0.1-SNAPSHOT.jar`, 74,260,956 bytes.
- SHA-256: `859C73E7F88C1AE608FD7F12C88D20B62A633C3DE948829974A78B7085BC5E9C`.

## Boundary
本项没有把四个高风险业务 Controller 切换到统一决策器；该端到端迁移属于 WI-063。本项已提供其词汇、决策与映射权威基础。
