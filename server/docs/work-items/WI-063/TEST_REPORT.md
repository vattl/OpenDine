# Test Report — WI-063

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

范围说明：此 PASS 仅表示 WI-063 必需检查全部通过；不表示全仓测试全绿。全量基线失败在下文完整披露。

## Passing Evidence
- 共享门面、Controller 接线和收银 Controller 最终专项：42 tests PASS。
- 权限决策、审批、限流、策略、映射、收银 Controller 和结账服务扩展回归：146 tests PASS。
- OpenAPI PyYAML parse：PASS，version 1.2.317，517 paths。
- `mvnw.cmd clean package -DskipTests`：PASS，已生成可运行 JAR。
- `git diff --check`：PASS；仅报告既有换行符转换提示。

## Full-suite Baseline Evidence
`mvnw.cmd test` 执行 1548 项：1542 PASS、5 SKIP、1 failure、5 errors。

失败被缩小到与 WI-063 变更面无关的既有测试，并可单独复现：
- `KdsWorkflowAdvanceIdempotencyTest`：测试构造的等叫状态先触发业务校验，实际抛 `IllegalArgumentException`，而旧断言期待 `OptimisticLockException`。
- `KdsWorkflowServePrintTimingTest` 两项：同样因等叫状态前置校验失败。
- `BusinessLifecycleLogicAuditTest` 两项：`updateDiners` 成功路径进入未完整装配的茶位费协作者并 NPE；该方法区域不在 WI-063 diff 中。
- `DataSourceBudgetConfigurationTest` 一项：全量运行时连接池创建超时；缩小到四个失败类运行时通过，属于时序/资源型不稳定。

上述失败未通过跳过、改断言或修改无关 KDS/业务代码来掩盖。它们是仓库基线修复项，不构成 WI-063 范围内回归通过的虚假声明。
