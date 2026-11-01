# Security Audit — WI-080

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS
DAST: NOT_APPLICABLE

## Assets and Trust Boundaries

Protected assets are database credentials, JWT/approval/payment encryption keys, initial administrator credentials, payment key files, business data and the authoritative cloud schema. Boundaries are operator environment to Compose, Compose network to MySQL/Redis, public Nginx to backend/public files, and the one-shot bootstrap to an explicitly selected empty database.

## Abuse Cases

- Missing or reused secrets: Compose fails closed for the three required application keys; documentation requires independent generated values.
- Accidental initialization of a live database: the CLI verifies MySQL 8, acquires a lock and refuses any database containing a table before writes.
- Default administrator takeover: there is no fixed account/password; the operator chooses a validated password and only its BCrypt hash is stored.
- Private-key disclosure: payment keys use a separate private volume/path that Nginx does not mount; legacy public paths are denied.
- Bootstrap replay: the tools profile is explicit, is not a normal server dependency, and a second run on the initialized database is rejected.
- Diagnostic secret leakage: bootstrap failure output reports stage, exception class and bounded SQL state/vendor code, not raw SQL, passwords or URLs.

## Authentication / Authorization / Isolation

The initial account receives the existing `super_admin` role, complete permission atoms and the first shop. Real login, HQ/super-admin permission lookup and wrong-password rejection passed. MySQL and Redis publish no host ports and join only the internal `data` network; Nginx joins only `edge`, while the server bridges the two. Only Nginx binds to loopback by default. KDS cloud authority remains unchanged.

## Data, Privacy and Secrets

`.env` and local deployment data are ignored; the committed example contains empty secrets only. A Git-range scan found no private-key block, common OpenAI-style API key or AWS access-key pattern. Payment encryption-key retention and the consequence of loss/rotation are documented. The test environment used generated ignored credentials and an isolated data directory.

## Supply Chain

No dependency was added to `pom.xml` or client manifests, so a new-dependency scan is not applicable. The final Java 8 build and focused tests passed. All five upstream container images are content-digest pinned from verified official registry responses. Docker Engine was unavailable; the guide does not claim a container runtime test.

## Findings

| ID | Severity | Finding | Evidence | Owner | Resolution / Risk Acceptance | Reverification |
|---|---|---|---|---|---|---|
| SEC-NONE | NONE | No open critical/high security finding | RUNTIME_VERIFICATION.md; production diff | WI-080 | Closed by design and verification | Fresh spec/quality review and final independent audit required |
