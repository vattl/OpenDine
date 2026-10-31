# Test Report — WI-026

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## TDD evidence

- RED: `OrderLedgerConsistencyServiceTest` 新增原因契约后，旧实现因缺少 `getReasonCodes()` 产生 4 个编译错误。
- GREEN: `mvnw.cmd "-Dtest=OrderLedgerConsistencyServiceTest,DailyCloseServiceTest" test` — 22 tests，0 failures，0 errors，0 skipped。

## Regression and contract

- `mvnw.cmd test` — 1364 tests，0 failures，0 errors，5 skipped，BUILD SUCCESS。
- Python `yaml.safe_load(docs/openapi.yaml)` — PASS。
- `git diff --check` — PASS。

## Package

- `mvnw.cmd clean package -DskipTests` — BUILD SUCCESS。
- JAR: `target/diancan-0.0.1-SNAPSHOT.jar`
- SHA-256: `d1291f59aa62a64e34ccbeeaf4f3a61821422ce140f1302e45c07d7467cadb64`
