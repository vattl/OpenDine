# Test Report — WI-064

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

此 PASS 表示 WI-064 必需检查通过，不表示全仓测试全绿。

## Passing Evidence
- `OrderRevisionServiceTest`、`OrderRevisionControllerContractTest`、`KdsOrderRevisionOwnershipTest`：13 tests PASS。
- 订单加菜、收银订单、高风险动作接线、套餐与同桌加菜扩展回归：55 tests PASS。
- 陈旧退菜、改价、优惠均验证在审批/支付/明细副作用前抛 409；未授权 C 端请求不执行版本比较。
- OpenAPI PyYAML parse：PASS，version 1.2.318，518 paths。
- `git diff --check`：PASS；仅既有换行符提示。
- `mvnw.cmd clean package -DskipTests`：PASS，可运行 JAR 已生成。

## Full-suite Baseline Evidence
`mvnw.cmd test`：1561 tests，1551 PASS、5 SKIP、1 failure、4 errors。

5 个失败与前一阶段记录一致，且不在 WI-064 修改面：
- `KdsWorkflowAdvanceIdempotencyTest`：1 failure，旧断言期望 `OptimisticLockException`，现有业务前置校验抛 `IllegalArgumentException`。
- `KdsWorkflowServePrintTimingTest`：2 errors，现有等叫状态前置校验阻断测试构造。
- `BusinessLifecycleLogicAuditTest`：2 errors，`updateDiners` 测试夹具未装配茶位费协作者导致 NPE。

本轮另发现上一阶段 `/admin/table/update` 在 Java 权限清单存在、但 V041 与初始化 SQL 漏项；已同步修复，权限映射审计 16/16 PASS，不再计入基线失败。

未跳过、改断言或修改无关业务来掩盖这些失败。
