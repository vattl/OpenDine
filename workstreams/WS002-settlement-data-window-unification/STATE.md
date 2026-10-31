# WS002 — settlement-data-window-unification

- Status: READY_TO_MERGE
- Work Type: CHANGE
- Parent: C011
- Branch: change/C011-settlement-data-window-unification
- Base: be84c4b
- Active Diff: `server/docs/diffs/D028-settlement-data-window-unification.md`
- Active Task: COMPLETE
- Runtime risk: MEDIUM — financial/reporting aggregation boundaries.
- Conflict surface: order aggregation, reporting APIs, analytics SQL, OpenAPI/API documentation.
- Validation: targeted Maven tests passed (29 tests); production-profile package created `server/target/diancan-0.0.1-SNAPSHOT.jar` at 2026-09-10 19:34. Commit: 11f6073. Next: semantic merge review.
