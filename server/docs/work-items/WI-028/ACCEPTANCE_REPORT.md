# Acceptance Report — WI-028

Decision: ACCEPTED

## Business outcome

Super administrators can reach version policy listing and management endpoints after deployment, while non-super administrators remain denied. The reported 403 caused by missing route configuration is removed at both permission authorities.

## Criteria

- PASS: four built-in mappings require `admin:super`.
- PASS: V030 registers the same database mappings idempotently.
- PASS: public version lookup compatibility is preserved.
- PASS: API docs, full tests and runnable JAR are complete.

## Completion level

INTEGRATED（未部署；生产应用 V030 后验证）。
