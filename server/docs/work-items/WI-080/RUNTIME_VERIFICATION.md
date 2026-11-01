# Runtime Verification — WI-080

Verification Date: 2026-11-02 (Asia/Shanghai)
Decision: PASS
Environment: isolated local MySQL 8.0.42 on `127.0.0.1:33380`; portable Temurin Java 8; generated task-only credentials; no production services or data.

## Java and deployment checks

| Check | Command / method | Observed result |
|---|---|---|
| Bootstrap unit tests | `mvn -B -Pprod -Dtest=FreshInstallBootstrapTest test` | PASS, 6/6 |
| Runnable package | `mvn -B -Pprod clean package -DskipTests` | PASS; runnable JAR produced under `server/target` |
| Deployment contract | `python -m unittest discover -s deploy/tests -v` | PASS, 6/6 |
| Login verifier syntax | `python -m py_compile deploy/verify-login.py` | PASS |
| Compose positive configuration | Official standalone Compose v5.6.1, populated task-only environment, `config --quiet` | exit 0 |
| Compose missing JWT secret | Same command after removing `AUTH_JWT_CURRENT_SECRET` | exit 1, required-variable guard observed |
| Documentation links | Resolve local Markdown targets in README, current guide and historical notice | PASS |
| Git whitespace check | `git diff --check` | PASS |

The final Compose contract also verifies an internal data network that excludes Nginx, and SHA-256 digest pinning for all five upstream images used by Compose/Dockerfile. The digests were resolved through live official Docker Hub registry responses before the final commit.

## Pristine database and actual server startup

Before reset, the test harness verified both the target database name `wi080_fresh` and `@@datadir` against the task-local `.local/mysql-smoke/data`. Only that isolated schema was dropped and recreated.

1. `python .local/mysql-smoke/run_bootstrap.py` exited 0 without manual SQL assistance.
2. All four explicit unversioned prerequisites were applied by the bootstrap itself.
3. `python .local/mysql-smoke/check_db.py` reported 49 matching migration checksums, 155 tables, one ACTIVE BCrypt administrator, one first shop with ordering closed, retained combo FK/index, zero orders, and 104 permission atoms.
4. `python .local/mysql-smoke/run_http_smoke.py` started the packaged service on loopback, then passed administrator login, HQ/super-admin permission and first-shop lookup, and wrong-password rejection.
5. A second bootstrap invocation against the now nonempty database exited 1 with the explicit nonempty refusal. Counts before and after remained one administrator, one shop and 49 migration rows.

The isolated MySQL PID, executable path, port and data directory were rechecked and the instance was shut down gracefully after verification.

## Honest boundaries

Docker Engine was unavailable, so container image build/start was not executed; Compose parsing and image-tag reachability do not replace that target-host check. Redis multi-instance delivery, Flutter/Windows/Android builds, WeChat tooling and real devices, actual payment/printing/delivery integrations and hardware were not exercised. The README and guide disclose these boundaries and require target-environment verification.
