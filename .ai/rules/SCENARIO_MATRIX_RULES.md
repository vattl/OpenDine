# Scenario Matrix Rules

For STANDARD, STRUCTURAL and CRITICAL work, verification must cover business scenarios, not only code paths.

## Required scenario families

Select relevant families:
- normal/happy path
- boundary values and time boundaries
- empty/zero/no-data state
- historical or pre-existing data
- invalid/error/timeout path
- permission/role differences
- repeated/idempotent execution
- concurrent/race-sensitive behavior
- compatibility with old consumers/data
- UI loading/empty/error/disabled states when UI is affected

## Rules

1. Build the Scenario Matrix before IMPLEMENTATION_READY for non-trivial work.
2. Every scenario records input/context, expected business outcome, affected invariant(s), verification method and result.
3. The matrix should be driven by the Work Item and Impact Map, not generic test boilerplate.
4. A passing unit test does not close a scenario unless it actually proves that scenario.
5. Material scenarios marked UNKNOWN or NOT_VERIFIED block ACCEPT.
