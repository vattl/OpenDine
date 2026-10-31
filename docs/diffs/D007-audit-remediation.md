# D007 — Audit remediation (2026-09-06)

Classification: CRITICAL. Base: 593c505125eedf57673654e92e36eeae904a0609.

User scope: S02,S03,S05,S06,S07,S08,S09,A01,C01,C02,E01,E02,P01,P02,P03,T01,D01. S01,S04,S10 explicitly excluded: preserve behavior and document exceptions.

| Slice | Findings | Operation | Target / negative acceptance |
|---|---|---|---|
| 1 | S02,P01 | REMOVE/MODIFY | Retire public config-account proxy routes (410, zero remote calls); bounded JSON buffering including chunked input |
| 2 | S05 | MODIFY | Shop-bound unique arrival-time-aware matching; ambiguous/missing-shop events cannot auto-settle including reverse matching |
| 3 | S03,S06,S07,S08,E02 | MIGRATE/MODIFY/ADD | Runtime credentials, no private keys in new JAR/Git index, POI update, sanitized errors/logs, CI gates |
| 4 | S09,P02,P03 | REPLACE/MODIFY | Validated/re-encoded bounded images, bounded thumbnail cache, finite HTTP timeouts |
| 5 | E01,A01 | MIGRATE/MODIFY | Versioned additive schema outside business startup, schema verification; durable workflows and cross-instance recovery |
| 6 | C01,C02 | MOVE/REPLACE | Extract cohesive controller responsibilities; centralized decimal money arithmetic preserving API numbers |
| 7 | T01,D01 | MODIFY/ADD | Regression and database validation harness, accurate OpenAPI/operations/exclusions |

Each slice: targeted tests, review, local commit. API changes require API/OpenAPI sync and JAR packaging. Final: full tests and production artifact inspection. Do not claim provider rotation, production deployment, history cleanup or live MySQL/load verification without evidence. Preserve local credentials outside tracked/build resources. No deletion of production data. Rollback by slice commit; additive tables can remain; never restore leaked credentials as rollback.

Implementation status (2026-09-06): all seven local slices committed through eca32c4; final evidence and remaining external/structural debt in docs/C007-VERIFICATION.md. This is not a declaration that all audit findings or production acceptance are closed.
