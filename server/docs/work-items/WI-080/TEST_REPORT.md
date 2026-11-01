# Test Report — WI-080

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Risk-derived minimum matrix

| Surface / Risk | Required Check | Command / Method | Result | Evidence |
|---|---|---|---|---|
| Java 8 compatibility | Focused bootstrap tests | `mvn -B -Pprod -Dtest=FreshInstallBootstrapTest test` | PASS, 6/6 | RUNTIME_VERIFICATION.md |
| Runnable artifact | Full package | `mvn -B -Pprod clean package -DskipTests` | PASS | RUNTIME_VERIFICATION.md |
| Deployment safety | Static contract | `python -m unittest discover -s deploy/tests -v` | PASS, 6/6 | EXECUTION_JOURNAL.jsonl; RUNTIME_VERIFICATION.md |
| Empty-database migration | Real isolated MySQL 8 bootstrap | CLI plus DB assertions | PASS, 49 checksums / 155 tables | RUNTIME_VERIFICATION.md |
| Authentication | Packaged server HTTP smoke | login, permissions, wrong password | PASS | RUNTIME_VERIFICATION.md |
| Existing-data guard | Repeat bootstrap | expected exit 1; before/after counts | PASS, unchanged 1/1/49 | RUNTIME_VERIFICATION.md |
| Environment injection | Compose config positive/negative | all keys then JWT omitted | PASS, exit 0 / exit 1 | RUNTIME_VERIFICATION.md |
| Documentation integrity | Local link resolution and source cross-check | README/current/historical guides | PASS | RUNTIME_VERIFICATION.md |

## Requirement and Scenario Coverage

| Requirement / Scenario | Test Level | Evidence | Result |
|---|---|---|---|
| AC1 merchant-first accurate README | specification/document review | README.md; T01-SPEC.md | PASS |
| AC2 executable deployment guide | source cross-check + link check | server/docs/DEPLOYMENT.md; RUNTIME_VERIFICATION.md | PASS |
| AC3 fresh bootstrap and nonempty refusal | unit + real integration + HTTP | RUNTIME_VERIFICATION.md | PASS |
| AC4 Compose secret/network/file isolation and immutable images | automated configuration contract | deploy/tests/test_deployment.py; SECURITY_AUDIT.md | PASS |
| AC5 supported path and honest limitations | package/integration/doc review | RUNTIME_VERIFICATION.md | PASS |

## Environment / Browser / Device Matrix

Verified: Java 8, MySQL 8.0.42, packaged Spring Boot service, Python deployment checks, standalone Compose parser. Not executed: Docker Engine/container runtime, Redis multi-instance behavior, Flutter Windows/Android, WeChat developer tools and devices, real payment/printing/delivery/hardware. These are target-host acceptance items and are explicitly disclosed.

## Migration Forward / Rollback

Fresh forward initialization and nonempty refusal passed. Bootstrap is intentionally not a rollback or upgrade mechanism. Existing installations require backup and version-specific reviewed migration; restoration requires a verified database/file/key backup.

## Flaky, Skipped and Pre-existing Failures

No required check failed. Early discovery attempts exposed and then fixed an incomplete baseline ALTER, UTF-8 BOM execution, an index/FK conflict and four unversioned readiness prerequisites; these are recorded in EXECUTION_NOTES.md. Docker/runtime/device checks were unavailable, not silently reported as passed.
