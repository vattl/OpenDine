# Completion Evidence — WI-027

Status: INTEGRATED

## Implementation

- `81d44360` integrates merchant routing and receivables (WI-020~023).
- `1e4572cf` integrates JSAPI settlement, authoritative ledger and daily-close consistency (WI-024~026).
- `GET /cashier/receivables/eligible-accounts` is registered by `CashierReceivableController`, protected by `receivable:view`, and resolves the authorized shop from request context.
- Incoming migrations were renumbered to V027/V028/V029 to avoid collisions with the integration branch's existing V024/V025/V026.
- API contracts were synchronized in `docs/API.md` and `docs/openapi.yaml`.

## Verification

- Focused route/permission/receivable tests: 22 tests, 0 failures/errors.
- Integration regression fixes: tests now model an open shop explicitly and provide the JSAPI state-convergence dependency; production business guards remain unchanged.
- Full regression: 1411 tests, 0 failures, 0 errors, 5 skipped.
- Flyway migration version uniqueness: PASS; V027/V028/V029 present.
- OpenAPI YAML parse: PASS.
- Package: `mvnw.cmd clean package -DskipTests` — BUILD SUCCESS.
- Runnable JAR: `target/diancan-0.0.1-SNAPSHOT.jar`.
- SHA-256: `1CC50554DD472B35C8D979CF741E37EAC232549EEE58896D88DB94E431CDA139`.

## Release boundary

This work is integrated and accepted locally, not deployed. Production must deploy the generated JAR and allow Flyway to apply V027, V028 and V029 before the reported 404 is considered released.
