# Test Rules

Never report PASS unless actually executed. Record the risk-derived minimum matrix and actual results in `TEST_REPORT.md`.

Minimum required checks are selected from the Impact Map and Scenario Matrix. Every affected critical path requires at least one behavioral check at the closest useful level. Contract, migration, security, UI and deployment surfaces require their applicable specialist checks.

Available levels include:

- Type Check
- Lint
- Build
- Unit
- Integration
- E2E
- Migration
- Manual Verification

Bug fixes should add regression tests when practical.

For behavior changes, final PASS does not prove TDD discipline. Require hash-chained evidence of an expected assertion RED before GREEN, followed by REFACTOR and risk-appropriate REGRESSION PASS. Syntax/import/collection/environment failure is not RED.

Critical flows deserve stronger validation.

Failure classes:

NEW_FAILURE / PRE_EXISTING_FAILURE / FLAKY / ENVIRONMENT_FAILURE / UNKNOWN

Required failing tests block REVIEW.

`Test Decision: PASS` requires `Required Checks Complete: YES`, `Failed Required Checks: 0`, traceability for all material scenarios, and explicit classification of skipped/flaky/pre-existing failures. Build success alone is not a test decision.
