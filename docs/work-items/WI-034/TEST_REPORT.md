# Test Report — WI-034

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## RED Evidence

`mvnw.cmd -Dtest=ComboCommercializationMigrationTest test` 在 V034 不存在时按预期失败：资源流为 null。

## GREEN / Regression Evidence

- `mvnw.cmd '-Dtest=ComboCommercializationMigrationTest,ComboCommercialRulesTest' test`
  - Tests run: 7
  - Failures: 0
  - Errors: 0
- `mvnw.cmd test`
  - Tests run: 1461
  - 本次迁移与套餐范围通过。
  - 基线仍有 3 个与本次无关的 KDS 失败：`KdsWorkflowAdvanceIdempotencyTest` 1 项、`KdsWorkflowServePrintTimingTest` 2 项。
- `mvnw.cmd clean package -DskipTests`
  - BUILD SUCCESS
  - 产物：`target/diancan-0.0.1-SNAPSHOT.jar`
- `jar tf target/diancan-0.0.1-SNAPSHOT.jar`
  - 包含 `BOOT-INF/classes/db/migration/V034__combo_commercialization.sql`

## Scope Decision

KDS 失败在修改前已存在，且不涉及套餐实体、迁移或数据库基线，不阻止 WI-034 的范围验收；它们仍阻止声称全仓测试全绿。

## Production Verification

NOT_RUN：本 Work Item 未获生产数据库连接或部署授权。发布时须在启动新 JAR 前执行 V034，并用 `SHOW COLUMNS FROM t_combo` 核验 11 列。
