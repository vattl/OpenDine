# Test Report — WI-062

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Commands
- `mvnw.cmd -Dtest=AccessDecisionOutcomeTest,AccessDecisionServiceTest,AccessServiceTest,DbApiPermissionMappingSecurityTest,SysInterceptorPermissionMappingSecurityTest,ApiPermissionMappingAuthorityContractTest,SensitivePermissionMappingPolicyTest test` — 37 PASS.
- `mvnw.cmd -Dtest=ApprovalServiceTest,ApprovalPermissionPolicyTest,ApprovalRateLimitServiceTest,AccessDecisionOutcomeTest,AccessDecisionServiceTest,AccessServiceTest,ApiPermissionMappingCompletenessSecurityTest,ApiPermissionMappingAuthorityContractTest,DbApiPermissionMappingSecurityTest,SensitivePermissionMappingPolicyTest,SysInterceptorPermissionMappingSecurityTest,CashierOrderControllerTest test` — 89 PASS.
- `mvnw.cmd -Dtest=AccessDecisionServiceTest test` — 13 PASS（补充跨动作隔离）。
- `python -m unittest scripts.governance.test_governance_scripts` — 5 PASS.
- OpenAPI PyYAML parse — PASS, 517 paths.
- `mvnw.cmd clean package -DskipTests` — PASS, runnable JAR generated.
- `python .ai/scripts/gate.py work --work-item docs/work-items/WI-062 --phase accept` — PASS.
- `python .ai/scripts/gate.py package` — FAIL（仓库级既有 MANIFEST 漂移：`.ai-backup-*`、`target/`、历史 tasks/work-items 未列入，以及大量既有文件 hash/size 不一致；不等同于 Maven package 失败）。

## Notes
第一次 RED 运行因 `Outcome` 尚未实现而编译失败；删除运行时兜底后，一个门店冲突测试因依赖旧兜底提前得到 403，已改为显式提供 DB 映射再验证原场景。两者均为预期测试驱动证据。

2026-10-24 导入缺陷回补：新增 `sensitivePermissionSeedUsesTheBaselineRemarkColumn` 后首次运行按预期失败，复现 `ERROR 1054 Unknown column 'description'`；将 V041 列名更正为 `remark` 后，`ApiPermissionMappingAuthorityContractTest,HighRiskActionRoleMigrationContractTest` 共 4 项全部通过。随后 `mvnw.cmd clean package -DskipTests` 通过并生成新 JAR。

仓库级 package gate 的 MANIFEST 基线修复超出 WI-062 范围，未删除备份、构建产物或历史任务，也未为获得绿色结果而掩盖该失败。

