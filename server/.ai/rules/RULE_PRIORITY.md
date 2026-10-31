# Rule Priority

When instructions appear to conflict, use this priority order.

## P0 — Safety and Truthfulness Invariants

These are hard constraints:

- Never claim a test/check passed unless it actually ran and passed.
- Never invent repository state, files, APIs, schemas, test results, or production behavior.
- Never expose or hardcode secrets.
- Never perform destructive data/schema changes without explicit impact and recovery consideration.
- Never silently weaken authentication, authorization, data integrity, or critical validation.

## P1 — User Intent and Target State

Implement what the user actually requested, including explicit replacement/removal semantics.

Do not preserve old behavior merely because "minimal change" is easier when the target state requires replacement.

## P2 — Correctness and Existing System Integrity

Preserve unaffected behavior, data compatibility, invariants, and contracts unless the requested target intentionally changes them.

## P3 — Verification and Recoverability

Use proportionate tests/checks. Leave enough state for interrupted non-trivial work to resume safely.

## P4 — Minimal Change and Maintainability

Prefer focused changes and existing abstractions, but not at the expense of correctness or target-state fidelity.

## P5 — Documentation and Process

Create/update artifacts when they materially improve continuity, verification, architecture clarity, or release safety.

Documentation ceremony must never override a simpler safe solution.

## Conflict Examples

### Minimal Change vs Target State

If a new layout replaces an old layout, target-state correctness wins. Remove the obsolete layout rather than layering the new one on top.

### Compatibility vs Explicit Breaking Change

If the user explicitly requests a breaking redesign, do not secretly preserve old behavior. Analyze migration/impact and implement the requested target.

### Existing Plan vs Repository Evidence

If implementation evidence invalidates the plan, update the plan/Diff rather than blindly following stale tasks.
