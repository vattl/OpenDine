# WI-080 / T01 Review Specification Snapshot

Goal: make OpenDine onboarding accurate and executable for a fresh installation.

## Acceptance criteria

- AC1 README states merchant problems, actual modules and third-party limitations without unsupported guarantees.
- AC2 Guide covers prerequisites, build, env purpose/injection, new DB, admin, clients, verification, upgrades and backups.
- AC3 Fresh bootstrap initializes current schema/RBAC and operator-selected BCrypt admin; nonempty DB rejected.
- AC4 Compose supplies required secrets, keeps DB/Redis private and payment keys outside public uploads.
- AC5 Automated checks and isolated MySQL startup/login evidence establish supported startup path; unavailable platforms stated truthfully.

## Preserved invariants and scope

- No production data or credentials are accessed.
- Existing/nonempty databases are never silently initialized.
- KDS cloud remains the sole business authority.
- Existing HTTP contracts and client UI remain unchanged.
- No default administrator password or usable example secret.
- Docker runtime, Flutter/WeChat devices, real payment and hardware are not claimed as verified when unavailable.

## Required implementation evidence

- Java 8 package and focused tests pass.
- A pristine isolated MySQL 8 database bootstraps without manual SQL assistance.
- BCrypt administrator, closed first shop, migration checksums and schema readiness are verified.
- Real backend login, permission lookup and wrong-password rejection pass.
- A second bootstrap against the nonempty database fails closed without changing seeded counts.
- Deployment contract tests, Compose positive/negative configuration checks and local documentation links pass.
