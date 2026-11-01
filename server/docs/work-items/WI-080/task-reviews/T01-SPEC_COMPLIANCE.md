# Task Review — WI-080 / T01

Task ID: T01
Review Type: SPEC_COMPLIANCE
Reviewer Session: /root/deployment_spec_reviewer_02
Provider / Model: OpenAI / inherited Codex model
Dispatch Receipt: .ai-runtime/agent-dispatch/wi080-t01-spec-review-02.md
Dispatch Receipt SHA256: 3b585acc52de08fc74bfb3d2c477c9c4cdf83dfb8076859fca596bb9243986fc
Fresh Context: YES
Read Only: YES
Review Decision: PASS
Open Critical: 0
Open High: 0
Diff Evidence Mode: GIT_RANGE
Git Base: 9037d3729393976fd0cb77f64a74d45ed397a1e1
Git Head: afe877d104b6450d6d2e1c5d4ca71b714b2ffe65
Spec Snapshot: server/docs/work-items/WI-080/review-snapshots/T01-SPEC.md
Spec SHA256: fe827e60a5430bbbefc48f868f5e1cb782ab722ce90709490399c0328b876ab6
Diff Snapshot: server/docs/work-items/WI-080/review-snapshots/T01.diff
Diff SHA256: 00e4a535affa86207ca26673a6a9a8ea63cc0cd3e39c070d94be9ed9392f6cf6

## Criterion Verdicts

| Criterion | Verdict | Evidence |
| --- | --- | --- |
| AC1 | PASS | `README.md` now leads with concrete merchant problems, maps them to the actual server/admin/KDS/mini-program/deploy modules, and explicitly withholds guarantees for availability, forecasts, reconciliation, third-party authorization, production security, and target-device behavior. |
| AC2 | PASS | `server/docs/DEPLOYMENT.md` covers Docker and native prerequisites/builds, the purpose and injection behavior of environment variables, empty-database bootstrap, operator-selected administrator/closed first shop, admin/KDS/mini-program setup, login and operational verification, external-service boundaries, backup/restore drills, and upgrade handling. The runtime report records local documentation-link validation as PASS. |
| AC3 | PASS | `FreshInstallBootstrap` validates operator inputs, requires an explicitly confirmed MySQL 8 database, obtains a bootstrap lock, checks schema emptiness before writes, applies the baseline/RBAC/API catalog/current migrations and readiness prerequisites, stores the operator-selected administrator with BCrypt, and creates a cloud-authoritative first shop with ordering closed. `RUNTIME_VERIFICATION.md` records 49 matching migration checksums, 155 tables, BCrypt storage, 104 permissions, real login/permission/wrong-password checks, and an expected second-run refusal. `remediation-evidence/nonempty-bootstrap-refusal.md` binds the refusal to head `afe877d...` and records unchanged before/after counts `(1, 1, 49)`. |
| AC4 | PASS | `deploy/docker-compose.yml` fails closed on required database, JWT, approval, payment, public-base-URL and bootstrap inputs; uses a non-root application database identity; publishes neither MySQL nor Redis; isolates MySQL/Redis/bootstrap on an internal data network; keeps Nginx on the edge network; and mounts payment keys only into the server's private volume. The six deployment contract checks cover required secrets, storage/key exposure, network segmentation, digest pinning, explicit bootstrap, and selected-database safety. |
| AC5 | PASS | Exact-head evidence records Java 8 focused tests at 6/6, full Maven packaging with a runnable JAR, six deployment contract checks, positive/negative Compose parsing, pristine isolated MySQL 8 bootstrap, packaged-server login/permission/wrong-password verification, and unchanged-data nonempty refusal. `RUNTIME_VERIFICATION.md` and `TEST_REPORT.md` truthfully identify Docker Engine, Redis multi-instance behavior, Flutter/WeChat targets, real integrations, and hardware as unavailable rather than verified. |

### Preserved invariants

| Invariant | Verdict | Evidence |
| --- | --- | --- |
| No production data or credentials accessed | PASS | Runtime evidence identifies a task-local MySQL 8 datadir/listener and generated task-only credentials; durable evidence omits credentials and connection strings. |
| Existing/nonempty databases never silently initialized | PASS | The emptiness check occurs before schema writes, and the exact-head remediation record shows expected exit 1 with administrator/shop/migration counts unchanged. |
| KDS cloud remains sole business authority | PASS | The bootstrap seeds `t_kds_shop_authority.authority_mode='cloud'`; README/deployment guidance explicitly retains cloud authority and rejects local state as cloud success. |
| Existing HTTP contracts and client UI remain unchanged | PASS | The Git range changes no controller, `docs/openapi.yaml`, `docs/API.md`, or client production source. |
| No default administrator password or usable example secret | PASS | `.env.example` contains blank operator inputs, Compose uses required-value expressions, and the bootstrap requires an operator-selected 16–72-byte password. |
| Unavailable platforms stated truthfully | PASS | README, deployment guidance, runtime verification, and test report consistently disclose the unexecuted Docker runtime, device/client, Redis multi-instance, real payment/integration, and hardware checks. |

## Findings

No Critical or High specification-compliance findings remain.

The archived cycle-one High finding is closed by the exact-head Java 8 six-test record and the durable nonempty-bootstrap before/after count record. The remediated Git range also adds the requested internal edge/data network boundary, digest-pinned upstream images, corresponding contract tests, and operator documentation. Snapshot hashes, dispatch receipt hash, full Git endpoints, reviewed-head ancestry, and absence of post-head changes on reviewed production paths were independently checked.

No API endpoint changed, so the project-specific OpenAPI/API documentation synchronization and API-change packaging trigger do not apply. The package still passed because it is expressly required by the T01 specification.
