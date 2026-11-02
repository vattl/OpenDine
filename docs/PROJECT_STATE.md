# Active Work Update (2026-09-08)
C009 stability remediation is IN_PROGRESS; tasks/active/C009-stability-remediation.md and docs/EXECUTION_CURSOR.md are the active pointers. Earlier state below is historical C007 evidence, not current worktree status or C009 verification.

# Project State

Last Updated / Verified: 2026-09-06
Current Version: 0.0.1-SNAPSHOT
Environment: local development; production version/deployment not inspected this run.
Current Phase: LOCAL_IMPLEMENTATION_COMPLETE / EXTERNAL_VERIFICATION_PENDING
Active Change / Diff: C007 / D007-audit-remediation
Branch: codex/audit-remediation
Last code commit: eca32c4

Seven local slices complete. Full evidence and residual issues: docs/C007-VERIFICATION.md.
Final build: clean verify -Pprod,quality PASS; 749 tests, 0 failures/errors, 1 skipped. MySQL migration and concurrent matching verified in disposable local schema. Production JAR credential gate PASS. NVD scan did not finish; no full dependency security conclusion.

Backend: Spring Boot 2.3.2.RELEASE / Java 8 build target / MyBatis-Plus; MySQL 8.
Schema: V007 additive explicit migration required before deployment; production not migrated here.
API/OpenAPI and operations documentation synchronized. No push or deployment performed.

Next work: external credential rotation, history/artifact cleanup, completed SCA report, production migration and operational validation. Larger controller decomposition, remaining Double migration and overall test coverage remain measured debt. S01/S04/S10 are user-approved exclusions, not fixes.

## Do Not Repeat
- Do not recreate `t_cashier_collection_intent` or drop existing session unique indexes.
- Do not overwrite `enable_prep_workflow` defaults without checking station hierarchy.
- Do not alter `GET /admin/settings/store` response structure without preserving `basic` nested attributes.
- Do not include `API_JAVA/`, admin_panel/miniprogram deletions, or KDS changes in the D002 commit.

## Current Risks
- Mixed uncommitted working tree: user committed server-side D002 as 9e5add6 while this session was active; only test/doc remainder is uncommitted.
- `API_JAVA/` untracked directory is user-owned and must not be committed.

## Release State
Release Gate: EXTERNAL_VERIFICATION_PENDING
Local artifact: BUILT_AND_VERIFIED
Production migration / credential rotation: NOT_EXECUTED
Next action: follow C007 residual matrix; do not resume the historical D002 commit step.

## Migration Note
2026-08-31: AI Development OS upgraded from v1 to v2 (Diff Driven Development).
- Added `docs/diffs/` and `docs/history/diffs/`.
- Added `.ai/rules/DIFF_RULES.md`, `.ai/rules/CHANGE_RULES.md`, `.ai/templates/STRUCTURAL_DIFF.md`.
- Added AGENTS.md step 4 (DIFF_RULES) and step 8 (Mandatory API Documentation Sync, preserved from v1 customization).
- v1 customized files backed up to `.ai-backup-v1/`.
