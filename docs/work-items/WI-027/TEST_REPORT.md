# Test Report — WI-027

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Regression

- `mvnw.cmd "-Dtest=CashierReceivableControllerRouteTest,ReceivableServiceTest,ApiPermissionMappingCompletenessSecurityTest" test` — 22 tests, 0 failures/errors.
- `mvnw.cmd "-Dtest=CashierOrderControllerTest,MultiStoreIsolationAndCrossShopWalletTest" test` — 40 tests, 0 failures/errors.
- `mvnw.cmd test` — 1411 tests, 0 failures, 0 errors, 5 skipped, BUILD SUCCESS.

## Contract and persistence

- Flyway migration version uniqueness check — PASS; V027/V028/V029 present.
- Python `yaml.safe_load(docs/openapi.yaml)` — PASS.

## Package

- `mvnw.cmd clean package -DskipTests` — BUILD SUCCESS.
- JAR: `target/diancan-0.0.1-SNAPSHOT.jar`.
- SHA-256: `1CC50554DD472B35C8D979CF741E37EAC232549EEE58896D88DB94E431CDA139`.
