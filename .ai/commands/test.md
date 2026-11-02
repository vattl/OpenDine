# v4.0 Role

`/test` is a specialist SELF_VERIFY check. Test selection should derive from the Work Item Impact Map. Passing tests do not by themselves imply acceptance.


---

# /test

Execute validation for current active work or explicit scope.

Input: `$ARGUMENTS`

## Strict behavior-change cycle

Final PASS is not enough for behavior-changing work. Run each stage with:

`python .ai/scripts/execution_journal.py --work-item <dir> record-test --task <TID> --stage <RED|GREEN|REFACTOR|REGRESSION> --selector <selector> [--expected-signature <text>] -- <argv...>`

RED must precede production implementation and fail on the expected assertion. Syntax/import/collection/environment failures and first-run PASS are not RED. GREEN uses the same selector; REFACTOR and REGRESSION remain green. Allowed non-behavior classifications require a task-specific rationale in `TDD_CYCLE_REPORT.md`.

## Risk-Based Test Selection

Choose verification proportional to the actual blast radius. Do not run every possible suite for a trivial isolated edit unless project policy or dependencies require it. Conversely, do not use a narrow local check for critical transaction/security/migration changes. Record only tests actually executed.

## Determine Scope

If no explicit scope, use PROJECT_STATE active work.

## Consider

- Type Check
- Lint
- Build
- Unit Tests
- Integration Tests
- E2E Tests
- Migration Validation
- Manual Verification

Use risk-based selection; not every change requires every level.

## Result States

- PASS
- FAIL
- NOT_RUN
- BLOCKED
- NOT_APPLICABLE

Failure classification:

- NEW_FAILURE
- PRE_EXISTING_FAILURE
- FLAKY
- ENVIRONMENT_FAILURE
- UNKNOWN

## Transitions

- Required tests pass → REVIEW
- New implementation failure → IMPLEMENTATION
- Environment prevents meaningful validation → BLOCKED

Never report PASS unless actually executed.

## Interruption-Safe Testing

If a multi-stage validation run is interrupted, update the execution cursor/validation state with tests actually executed and tests still pending. Never convert unrun checks into PASS during recovery.



# UI Validation Scope

For UI changes, consider visual/manual rendered verification and responsive checks in addition to code-level tests. Use the lightest evidence appropriate to risk.

---

# UI Fidelity Extension

When the active work is a STRUCTURAL `/ui` task with an approved prototype:

- include visual fidelity verification as a required test dimension when rendering tools are available
- compare at the target viewport defined in the measured UI spec
- classify fidelity as PASS / PARTIAL / FAIL
- do not advance to REVIEW when required visual fidelity is FAIL

Visual build success alone is not sufficient evidence.


---

# v2.6 Runtime Validation

When Runtime Risk is material, extend validation with appropriate checks such as:

- boundary cases
- concurrency/idempotency cases
- query/data-scale checks
- resource cleanup checks
- performance baseline/budget
- soak/longevity testing

Do not run all of these for every change. Select by risk.

Record runtime checks as PASS / FAIL / NOT_RUN / NOT_APPLICABLE, and do not advance when a required runtime check fails.

# v3.2 UI Visual Validation

For UI work whose acceptance depends on an approved prototype/reference, functional tests do not replace visual verification.

Route the visual portion through `/ui-verify` when real rendering is available.
