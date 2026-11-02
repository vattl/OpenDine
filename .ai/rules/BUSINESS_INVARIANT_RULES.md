# Business Invariant Rules

Business invariants are durable domain truths that must remain valid across features, fixes, refactors and migrations.

## Purpose

Use invariants to prevent a locally correct change from violating system-level business behavior.

Examples:
- cancelled orders must never enter active KDS scheduling
- historical reports using explicit dates must not inherit current-shift rules
- already-settled transactions must not be settled twice
- client display state must not be treated as authoritative payment confirmation

## Rules

1. During UNDERSTAND, identify known invariants relevant to the requested capability.
2. During DISCOVER, read `docs/project/BUSINESS_RULES.md` and confirm which invariants apply.
3. New durable domain rules discovered during work must be proposed as invariants, not silently embedded as local conditions.
4. IMPLEMENT may not knowingly violate an applicable invariant.
5. SELF_VERIFY must include invariant checks for every applicable invariant.
6. REVIEW must inspect whether the implementation created a hidden exception to an invariant.
7. ACCEPT blocks when an applicable invariant is UNKNOWN, violated, or unverified.
8. Add/update project-level invariants only after the behavior is accepted as intentional production truth.

## Scope

Invariants are not UI preferences, temporary acceptance criteria, test fixtures, or one-off implementation details. Keep them stable, minimal and domain-oriented.
