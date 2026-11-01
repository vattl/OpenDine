# Implementation Design — WI-080
## Root Fix / Owner
Add explicit fresh-install Java CLI using project JDBC, BCrypt and migration runners. Refuse nonempty target DB before mutation; lock bootstrap; supplied DB is authoritative. Import schema baseline without CREATE DATABASE/USE redirect, apply reviewed ordered migrations with existing checksums for V007–V012; reconcile later baseline incompatibilities explicitly, never catch-and-ignore SQL errors. Seed existing RBAC/API mappings and supplied administrator plus closed first shop. No Spring bean or API.
Compose uses one-shot initializer before backend, buildable JAR image, required environment mapping, private MySQL/Redis networking, persistent uploads and separate private payment key storage.
Rewrite merchant README and full deployment guide with exact client build instructions and optional-service limits.
## Failure / Compatibility
Fresh database only. Existing installs follow backup and version-specific reviewed migration procedure, never bootstrap or delete volume. Partial initialization must fail loudly with recovery instructions for disposable fresh data only. No default admin password or production secret.
## Verification Strategy
Observed RED for missing deployment prerequisites/bootstrap protections; GREEN after implementation; refactor and regression via execution journal. Build package with supported Java environment. Real isolated MySQL datadir, empty database migration, BCrypt admin, authenticated login and repeated-init rejection. Compose static validation if Docker unavailable, explicitly report no Docker runtime validation. Check document links and env names against source. Fresh independent task spec/quality reviewers and final auditor.
## Scope / Constraints
No client or API change. SQL migrations remain immutable. Do not disable readiness validators to get a green startup. No arbitrary execution of historical example SQL without schema checks. All runtime experiments use local generated test credentials, never printed.


## Fresh Baseline Normalization
The schema-only snapshot already contained V021 member recharge columns/indexes, V033 refund binding columns/indexes and order/merchant indexes, and V037 approval binding_version, without their complete companion schemas. Remove these fragments ONLY from deploy/sql/init.sql so the original immutable migrations execute in full and restore them; never suppress duplicate-column/index errors. This baseline is exclusively for an empty database, never an upgrade.
