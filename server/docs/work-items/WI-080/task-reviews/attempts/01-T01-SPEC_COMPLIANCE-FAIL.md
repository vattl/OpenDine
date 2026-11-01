# Task Review — WI-080 / T01

Task ID: T01
Review Type: SPEC_COMPLIANCE
Reviewer Session: /root/deployment_spec_reviewer
Provider / Model: OpenAI / inherited Codex model
Dispatch Receipt: .ai-runtime/agent-dispatch/wi080-t01-spec-review.md
Dispatch Receipt SHA256: 09cc2c9f382ca2b6e2191af2362ff2506278b71a747795484d84cb66ebb9c78f
Fresh Context: YES
Read Only: YES
Review Decision: FAIL
Open Critical: 0
Open High: 1
Diff Evidence Mode: GIT_RANGE
Git Base: 9037d3729393976fd0cb77f64a74d45ed397a1e1
Git Head: b8990e0b5555d4be28c2b702929b2a52900aa4c4
Spec Snapshot: server/docs/work-items/WI-080/review-snapshots/T01-SPEC.md
Spec SHA256: fe827e60a5430bbbefc48f868f5e1cb782ab722ce90709490399c0328b876ab6
Diff Snapshot: server/docs/work-items/WI-080/review-snapshots/T01.diff
Diff SHA256: 9f72339ee38c3f3b5bf3c83d3dc84a685c89aad52b964d134243a6dcfba66d35

## Criterion Verdicts

| Criterion | Verdict | Evidence |
| --- | --- | --- |
| AC1 | PASS | `README.md` describes concrete merchant problems, repository modules, operator responsibilities, and limitations for availability, prediction, reconciliation, third-party services, and the older public runtime stack. |
| AC2 | PASS | `server/docs/DEPLOYMENT.md` covers prerequisites, container/native builds, environment-variable injection and rotation, empty-database initialization, the initial administrator/shop, all three client families, login verification, HTTPS/files/external services, upgrades, backups, restore drills, and troubleshooting. Local relative-link validation passed. |
| AC3 | PASS | `FreshInstallBootstrap` requires explicit confirmation, acquires a lock, rejects any schema containing a table before writes, applies the baseline/RBAC/API catalog and ordered V007–V055 migrations, creates an operator-selected BCrypt administrator and a closed first shop, and runs payment/KDS readiness checks. Retained isolated-MySQL results report 49 migration checksums, 155 tables, BCrypt storage, 104 permissions, and a closed shop; the repeated run was refused. |
| AC4 | PASS | Compose fail-closes on the database, JWT, approval, payment, and bootstrap inputs; the application uses a non-root database account; MySQL and Redis have no published host ports; payment keys use a separate private volume not mounted by Nginx. `python deploy/tests/test_deployment.py` passed all four checks during this review. |
| AC5 | FAIL | Static deployment checks, link checks, isolated MySQL bootstrap, backend login/permission lookup, wrong-password rejection, and truthful unavailable-platform statements are present. However, the exact-head verification packet is incomplete as detailed in the High finding below. |

### Preserved invariants

| Invariant | Verdict | Evidence |
| --- | --- | --- |
| No production data or credentials accessed | PASS | The execution notes identify an isolated MySQL 8.0.42 datadir and ignored generated credentials; no production target is introduced by the diff. |
| Existing/nonempty databases never silently initialized | PASS | The empty-schema check precedes all bootstrap writes, and the retained second-run log shows fail-closed refusal. |
| KDS cloud remains sole business authority | PASS | The first shop is seeded with `authority_mode='cloud'`; README and deployment guidance explicitly preserve cloud authority and reject dual-primary interpretation. |
| Existing HTTP contracts and client UI unchanged | PASS | The Git range changes no controller, OpenAPI/API contract, or client production source. |
| No default administrator password or usable example secret | PASS | `.env.example` leaves secrets empty and Compose uses required-value expressions; the bootstrap accepts only an operator-provided 16–72-byte password. |
| Unavailable platforms are stated truthfully | PASS | The guide explicitly says Docker Engine, Redis multi-instance delivery, Flutter/WeChat devices, real payment, and hardware were not runtime-verified. |

## Findings

🟡 **High — The retained verification does not prove the exact reviewed head passed every required check**

The immutable specification requires the Java 8 package/focused tests to pass and requires the second bootstrap to leave seeded counts unchanged (`review-snapshots/T01-SPEC.md:24-29`). The implementation receipt claims six tests and unchanged counts (`task-receipts/T01-IMPLEMENTER.md:29`), but the retained package log `.local/mysql-smoke/package-bom.log:93-109` records only five `FreshInstallBootstrapTest` tests, while Git head `b8990e...` contains six. The retained repeat-bootstrap log proves refusal but contains no before/after seeded counts, and `SCENARIO_MATRIX.md:5-9` still records the affected scenarios as `NOT_RUN`. Thus the receipt assertion is not independently reproducible evidence for the exact snapshot.

**Why:** A stale package result can miss a regression in the sixth test or its production dependency, and refusal output alone does not establish the explicit no-count-change requirement. The workflow requires evidence rather than implementer assertion.

**Suggestion:** On the exact reviewed head with Java 8, rerun the focused test and full package command and retain the command, exit code, head/hash, and complete six-test output. Around the nonempty rerun, capture the same seeded table counts before and after, plus the expected nonzero bootstrap exit. Update the Scenario Matrix/TDD evidence to point to those artifacts, then reseal the snapshots and dispatch fresh specification and quality reviews because evidence-bound review inputs will have changed.

## Review Notes

- Snapshot SHA256 values and both Git endpoints were independently verified.
- No API endpoint changed, so the server-specific OpenAPI/API documentation-sync and API-change JAR rule are not triggered; the Java package requirement still applies through the T01 specification itself.
- No production or lifecycle files were modified by this reviewer other than this assigned review artifact.
