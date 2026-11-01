# Task Review — WI-080 / T01

Task ID: T01
Review Type: CODE_QUALITY
Reviewer Session: /root/deployment_quality_reviewer
Provider / Model: OpenAI / inherited Codex model
Dispatch Receipt: .ai-runtime/agent-dispatch/wi080-t01-quality-review.md
Dispatch Receipt SHA256: 8111d24b264f8bc93036b2ce9e3a2abb2fd3a9585a999d03d49118088150455f
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

| Criterion | Verdict | Evidence / rationale |
| --- | --- | --- |
| Bootstrap correctness | PASS | `FreshInstallBootstrap` validates operator input, requires MySQL 8 plus an explicitly selected database, serializes bootstrap with a named lock, checks emptiness before the first write, applies ordered migrations, seeds identity transactionally, and runs payment/KDS/report readiness checks. The isolated MySQL evidence records a complete bootstrap and real HTTP login path. |
| Migration and data safety | PASS | The bootstrap is not attached to application startup; nonempty databases fail closed before mutation. SQL errors are not ignored. Documentation accurately states that MySQL DDL can leave a partial fresh database and requires rebuilding only a confirmed disposable new-install database rather than offering an automatic cleanup path. |
| Secrets and security | PASS | No usable secret or default administrator password is committed. Compose requires separate secret variables, uses a non-root application DB identity, does not publish MySQL/Redis ports, isolates payment-key storage from the public volume/Nginx, and runs the Java image as an unprivileged user. Bootstrap failure output avoids raw SQL/connection exception text. |
| Compose and container reliability | PASS | MySQL and Redis have persistent volumes and health checks; server startup depends on healthy state stores; bootstrap is an explicit `tools` profile and is not a restart side effect. The guide truthfully records that Compose parsing was tested but Docker Engine execution was unavailable. |
| Tests and verification | FAIL | Focused test design and deployment-contract coverage are relevant, and the reviewer reran the four Python deployment tests successfully with `git diff --check` passing. However, the retained Java 8 package log predates the exact six-test head and the repeated-bootstrap evidence does not retain the asserted before/after counts, so the required exact-head verification is not independently reproducible. |
| Documentation reproducibility | PASS | README and the current guide cover prerequisites, build, environment injection, fresh bootstrap, clients, verification, backup, upgrade/recovery and unsupported integrations/platforms. The historical guide is clearly demoted and linked only as compatibility context. |
| Java 8 compatibility | PASS | The new Java code uses Java 8-compatible language/library features, the container build/runtime use Temurin 8, and the recorded focused tests/package/runtime smoke used portable Temurin 8. |
| Unsupported claims and preserved invariants | FAIL | Documentation correctly withholds claims for Docker runtime, Flutter/WeChat target devices, payment and hardware; KDS authority and HTTP/UI invariants are preserved. The current guide nevertheless makes an exact verification claim that is not fully supported by the retained artifacts described below. |

## Findings

### 🟡 High — Exact-head Java 8 and nonempty-count claims are not retained as reproducible evidence

`server/docs/DEPLOYMENT.md:225` states that the published guide was verified with Java 8, including the fresh bootstrap and an unchanged-data repeated-bootstrap check. `server/docs/work-items/WI-080/RUNTIME_VERIFICATION.md:11-28` and the implementer receipt further claim six focused tests and unchanged administrator/shop/migration counts. The retained `.local/mysql-smoke/package-bom.log` instead records only five `FreshInstallBootstrapTest` tests, while the reviewed head contains six tests in `server/src/test/java/com/lanf/database/FreshInstallBootstrapTest.java:17-86`. The retained `.local/mysql-smoke/bootstrap.log` proves the second bootstrap was refused but contains no before/after counts; the committed Scenario Matrix at head `b8990e0...` still records S1-S7 as `NOT_RUN`.

**Why:** Static code inspection supports the intended behavior, but a stale test log and an assertion-only count claim do not establish that the exact reviewed snapshot passed the required Java 8 suite or that repeated initialization left the seeded rows unchanged. This makes the deployment guide's verification statement stronger than the durable evidence.

**Suggestion:** On the exact reviewed head, rerun the focused test and full package commands under Java 8 and retain complete output showing all six tests. Capture administrator, shop and migration counts immediately before and after the expected failing second bootstrap, together with the nonzero exit code and Git head/source hashes. Update the Scenario Matrix and runtime evidence to point to those artifacts, reseal the snapshots, and dispatch fresh reviews.

### 🟡 Medium — Segment the public proxy from unauthenticated Redis

`deploy/docker-compose.yml:28-38` starts Redis without authentication, while no explicit networks are declared, so Redis, MySQL, Nginx and the application all share Compose's default network. The stores are correctly not published to the host, satisfying the reviewed acceptance criterion, but a compromise of the public Nginx container would still provide network reachability to Redis.

**Why:** Network segmentation limits lateral movement from the only internet-facing container. Redis may hold transient authorization or application state even though it is not the business source of truth.

**Suggestion:** Add an edge network for Nginx ↔ server and an `internal: true` data network for server ↔ MySQL/Redis. Consider Redis authentication/TLS when the deployment topology extends beyond one trusted host, and extend `deploy/tests/test_deployment.py` to assert the intended network membership.

### 🟡 Medium — Pin deployable image inputs more tightly

`deploy/docker-compose.yml:11,29,95` and `deploy/Dockerfile:1,7` use moving major/minor tags (`mysql:8.0`, `redis:7-alpine`, `nginx:stable-alpine`, Maven/Temurin tags without digests). The deployment steps are executable today, but rebuilding the same Git commit later can silently select different OS packages or image contents.

**Why:** The change presents a reproducible onboarding path; mutable image inputs weaken repeatability and complicate rollback or incident reconstruction.

**Suggestion:** Pin tested patch tags and preferably image digests, document the refresh cadence, and validate updated pins with the same bootstrap/login smoke before advancing them.

## Positive Notes

- The empty-database guard is placed before schema mutation and reinforced by a MySQL advisory lock; this is the right fail-closed shape for a one-shot installer.
- Identity seeding uses prepared parameters and a bounded transaction, and password validation respects BCrypt's 72-byte input boundary.
- The guide is unusually candid about partial DDL, unsupported environments and what login verification does not prove; those limitations materially reduce operator error.
