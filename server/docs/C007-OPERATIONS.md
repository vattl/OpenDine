# C007 deployment and verification

## Scope and retained exceptions
S01 legacy identity compatibility, S04 personal callback signing/default key and S10 printing HTTP are explicitly retained at the user's request. Their audit risks remain accepted exceptions, not fixed findings. Do not weaken unrelated controls to accommodate them.

## Credential migration — before deploying
Repository/JAR credentials have been removed. Existing local copies are preserved only under ignored `.local/audit-secrets-20260906/`; this is recovery material, not a production secret store. Restrict access and securely retire copies after provider rotation. The report and scripts never print credential values.

Configure DB_PASSWORD, WEIXIN_SECRET, FEIEYUN_UKEY, PARKING_TOKEN, PARKING_AUTHORIZATION, ARK_API_KEY and ZSQ_PASSWORD through the deployment secret store. AUTH_JWT_CURRENT_SECRET and PAYMENT_CONFIG_MASTER_KEY retain their existing runtime requirements. `APPROVAL_TOKEN_ENVELOPE_KEY` must contain at least 32 bytes of high-entropy secret material and must be identical on every backend instance; keep it independent from JWT and payment keys. No new secret values are generated as substitutes for working provider credentials.

Move payment keys to a restricted runtime directory and change `t_payment_merchant_config` private-key references from `classpath:` to absolute paths using the existing merchant administration workflow. Public key/certificate references must also point to deployed files. Check payment readiness before enabling checkout. The new JAR deliberately contains no PEM/PFX/ZIP resources.

Rotate/revoke old credentials at their providers; coordinate Git history rewrite and old artifact cleanup separately with repository owners. These external operations have not been executed by the code change. Reverting code must not restore compromised credentials.

## API changes
Four config-account proxy routes now return 410. Use existing authenticated admin delivery APIs. JSON bodies are limited to 1 MiB by default, including chunked bodies. Set matching edge limits.

Collection events require a known shop and a unique active intent at arrival time. Multiple candidates are NEEDS_REVIEW, unknown shops cannot participate in reverse matching, and the order-amount fallback is removed. Operators must reconcile these events manually against provider records. The callback signature contract remains the S04 exception.

## Verification
`python scripts/check-release-security.py --jar target/diancan-0.0.1-SNAPSHOT.jar` checks tracked key material and production resources. Run `mvnw.cmd clean verify -Pprod,quality` for tests, coverage and artifact generation. SCA is a separate profile because vulnerability feeds require network/provider access; do not equate a missing SCA report with a clean scan.

Record provider rotation, deployment configuration, production database migration, restore, load and failover results before declaring production remediation complete. Local test evidence alone does not establish those outcomes.

## Explicit migration and multi-instance operation

Before starting the new application, set MIGRATION_JDBC_URL, MIGRATION_DB_USER and MIGRATION_DB_PASSWORD for an independently privileged migration account, then run:

```powershell
java "-Dloader.main=com.lanf.database.AuditSchemaMigration" -cp target/diancan-0.0.1-SNAPSHOT.jar org.springframework.boot.loader.PropertiesLauncher
```

The command executes V007 under a database advisory lock and records its checksum only after success. Back up first; MySQL DDL auto-commits, so rerun the idempotent script after correcting a failure. Do not run an old and new schema writer concurrently. The application now requires the migration and validates tables read-only before payment beans start. New workflow preferences survive restart and are read from the shared database. Existing in-memory selections must be reselected once after rollout; they cannot be backfilled from a database that never stored them.

Cashier WebSocket instances check durable delivery cursors every 5 seconds for their connected shops; duplicate wakes are expected and use existing cursor-based pull/ack. This is bounded recovery, not an exactly-once message channel. Keep scheduling enabled for recovery and validate a two-instance deployment before scaling. Other WebSocket channels require their own deployment verification.

Local verification: MySQL 8 at 127.0.0.1:3307, disposable c007_test_* schema: fresh install, legacy index upgrade, completed-debt cleanup, pending-debt preservation, rerun and startup readiness PASS. Production DB not accessed. Opt-in: C007_MYSQL_PASSWORD plus AuditSchemaMigrationMySqlTest. Checksum normalizes CRLF/LF.

Final local evidence and residual debt: [C007-VERIFICATION.md](C007-VERIFICATION.md). NVD initialization was interrupted without a completed vulnerability report; rerun the security-scan profile in CI with its feed access configured.

## Direct HTTPS configuration (2026-09-06)
The current application configuration selects port 443 and PKCS12 TLS. Set SERVER_SSL_KEY_STORE to a deployed external certificate resource (for example a file: URI), and SERVER_SSL_KEY_STORE_PASSWORD to its password. The configured alias must exist in that keystore. No certificate is bundled in the JAR. Match the reverse proxy upstream port and protocol to this configuration; packaging alone does not repair an existing 502. If Nginx terminates TLS, configure the application HTTP port/SSL setting explicitly in the deployment environment instead. The removed optional AI/Feieyun YAML sections remain removed in this build.

Latest configuration build: clean package -Pprod -DskipTests PASS (tests skipped); packaged YAML and credential gate PASS. SHA256: `3730de6a648a9ac625069db21cc1c14584d887767e9314aeadc9bbeb02403dc6`. This supersedes the artifact hash of the earlier full audit test build, not its historical test evidence.
