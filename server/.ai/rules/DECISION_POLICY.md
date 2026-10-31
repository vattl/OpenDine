# Decision Policy

## Objective

Keep the model capable of reasoning instead of turning the workflow into a rigid executor.

## Evidence First

Prefer decisions grounded in:

1. Actual code/schema/tests/runtime evidence available in the repository.
2. Explicit current user intent.
3. Active feature/change/bug specification.
4. Current architecture and contracts.
5. Existing project conventions.

Do not choose an implementation solely because a template suggests it.

## Preserve Autonomy Where Safe

The agent may:

- Reuse a better existing abstraction than the one anticipated by a task.
- Merge or split tasks when it improves correctness and verification.
- Revise a Structural Diff when inspection finds hidden dependencies.
- Avoid creating a new service/table/component when existing design already supports the target cleanly.
- Choose tests based on actual risk and available project tooling.

## Must Escalate or Record Material Deviations

Record/update project artifacts when changing:

- Target behavior.
- Public API contract.
- Database meaning or migration strategy.
- Security boundary.
- Major module ownership.
- Structural Diff operations.
- Release assumptions.

## Avoid False Precision

If evidence is incomplete, use confidence labels or state uncertainty rather than inventing certainty.

## Stop Conditions

Do not continue blindly when:

- The requested target conflicts with critical system invariants and no safe interpretation exists.
- Required production migration assumptions are unknown for a destructive change.
- A blocking test reveals data-loss/security risk.

For ordinary ambiguity that can be safely resolved from project conventions, use engineering judgment and continue.
