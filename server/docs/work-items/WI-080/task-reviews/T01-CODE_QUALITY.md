# Task Review — WI-080 / T01

Task ID: T01
Review Type: CODE_QUALITY
Reviewer Session: /root/deployment_quality_reviewer_02
Provider / Model: OpenAI / inherited Codex model
Dispatch Receipt: .ai-runtime/agent-dispatch/wi080-t01-quality-review-02.md
Dispatch Receipt SHA256: bbd206a756c873c3f174e69c40a930417743c706e539287ddad75c323274a4c3
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

## Review Summary

The remediated snapshot is coherent, fail-closed and maintainable for the stated fresh-install scope. The first-cycle High evidence-integrity blocker is resolved by exact-head Java 8 test/package evidence and durable before/after nonempty-database counts. The two earlier Medium hardening suggestions are also implemented: Nginx is isolated on `edge`, MySQL/Redis are confined to the internal `data` network, and all five upstream image inputs are pinned to verified SHA-256 manifests. No Critical or High code-quality issue remains.

## Criterion Verdicts

| Criterion | Verdict | Evidence / rationale |
| --- | --- | --- |
| Correctness and bootstrap behavior | PASS | `FreshInstallBootstrap` validates operator-controlled identity inputs before connection use, requires MySQL 8 and an explicitly selected catalog, acquires a named advisory lock, checks database emptiness before the first write, applies the complete ordered bootstrap inputs, creates the administrator/shop transactionally, and runs schema-readiness checks. The focused suite passed 6/6 during this review. |
| Data safety and failure behavior | PASS | A nonempty or unknown table count fails closed. The durable exact-head refusal record captures expected exit 1 and unchanged administrator/shop/schema-version counts `(1, 1, 49)` before and after. The bootstrap is an explicit `tools` profile and is not a server startup/restart dependency. Documentation truthfully warns that MySQL DDL can leave a partially initialized disposable database and does not offer unsafe automatic cleanup. |
| Network and secret isolation | PASS | MySQL, Redis and bootstrap join only `data`; `data` is `internal: true`; Nginx joins only `edge`; the server is the sole bridge. MySQL/Redis publish no host ports. Application secrets use required-value interpolation, the application does not use MySQL root, payment keys use a private volume not mounted by Nginx, and the Java image runs as an unprivileged user. The six deployment contract tests passed during this review. |
| Immutable image inputs and reproducibility | PASS | MySQL, Redis, Nginx, Maven/Temurin build and Temurin Java 8 runtime references all use SHA-256 digest pins. Live official Docker Hub registry manifest queries during review matched every committed tag/digest pair. The guide documents controlled digest refresh and retesting rather than unreviewed pulls. Docker Engine execution remains explicitly unclaimed. |
| Java 8 and Compose compatibility | PASS | Review execution used Java `1.8.0_171`; `mvn -B -Pprod -Dtest=FreshInstallBootstrapTest test` passed 6/6 and `mvn -B -Pprod clean package -DskipTests` completed with `BUILD SUCCESS` and produced the repackaged JAR. The implementation uses Java 8-compatible syntax/APIs. The retained evidence separately records Temurin Java 8 and standalone Compose v5.6.1 positive/negative parsing. |
| Security and dependency discipline | PASS | No new Maven/client dependency is introduced. SQL values controlled by the operator are parameterized, BCrypt's byte boundary is enforced, raw SQL/URLs/passwords are excluded from failure output, and no usable default credential is committed. `SECURITY_AUDIT.md` reports zero open Critical/High findings and accurately scopes DAST/container-runtime work as unavailable. |
| Readability and maintainability | PASS | The bootstrap stages are explicit, migration special cases are bounded and documented, tests exercise credential rejection, empty-database refusal, rollback, mapping preservation, BOM handling and delimiter/error behavior. Compose ownership and network boundaries are straightforward and covered by focused contract assertions. |
| Documentation accuracy | PASS | README and `server/docs/DEPLOYMENT.md` describe actual modules, prerequisites, build/environment injection, fresh installation, client setup, verification, backup/upgrade recovery, KDS cloud authority and unsupported environments without unsupported availability or platform claims. The exact-head runtime/test/remediation artifacts support the published Java 8, MySQL bootstrap/login and nonempty-refusal statements. |

## Findings

No Critical or High findings.

### 🟡 Medium — Retire the one-shot bootstrap password from the shared Compose environment after first login

`deploy/docker-compose.yml` uses required interpolation for `BOOTSTRAP_ADMIN_PASSWORD`, and `server/docs/DEPLOYMENT.md` correctly explains that Compose validates it even when the tools profile is inactive. The documented mitigation is to retain the value in a restricted `.env` and change the administrator password after installation, making the retained value unusable.

**Why:** This is safe for authentication after password rotation, but it leaves stale sensitive material in the long-lived general Compose environment and makes ordinary maintenance commands depend on bootstrap-only variables.

**Suggestion:** In a follow-up, consider a bootstrap-specific environment file or an explicit one-shot invocation contract so normal server lifecycle commands no longer require bootstrap credentials. Document deletion of that file after the initial password has been changed. This is non-blocking because the current value is not injected into the business server, `.env` is ignored/restricted, and the guide requires post-bootstrap password invalidation.

## Verification Performed

- Independently verified the supplied spec, diff and dispatch SHA-256 values.
- Inspected Git range `9037d3729393976fd0cb77f64a74d45ed397a1e1..afe877d104b6450d6d2e1c5d4ca71b714b2ffe65`, the archived cycle-one findings, `REVIEW_REMEDIATION.md`, `RUNTIME_VERIFICATION.md`, `TEST_REPORT.md`, `SECURITY_AUDIT.md`, Scenario Matrix and both durable remediation records.
- `python -m unittest discover -s deploy/tests -v`: PASS, 6/6.
- `mvn -B -Pprod -Dtest=FreshInstallBootstrapTest test`: PASS, 6/6 under Java 8.
- `mvn -B -Pprod clean package -DskipTests`: PASS; runnable Spring Boot JAR produced under `server/target`.
- `git diff --check 9037d3729393976fd0cb77f64a74d45ed397a1e1..afe877d104b6450d6d2e1c5d4ca71b714b2ffe65`: PASS.
- Official Docker Hub manifest heads matched all five committed tag/digest pairs at review time.

## Positive Notes

- The remediation addressed both required evidence gaps and the defense-in-depth suggestions rather than treating the earlier review as a documentation-only exercise.
- Keeping Nginx off the internal data network materially limits lateral movement from the sole host-facing container.
- The bootstrap combines a pre-write empty-schema guard, serialization lock, transactional identity seed and explicit post-migration readiness checks; that is a strong fail-closed shape for a one-shot fresh installer.
- The deployment guide is candid about partial DDL, unavailable Docker/device/runtime validation and third-party configuration boundaries, which makes the operational contract substantially safer.
