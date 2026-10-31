# Governance Rules

## Purpose

Keep long-lived AI-developed projects safe, understandable, and evolvable without forcing every task through the same ceremony.

## Hard constraints

These are mandatory when applicable:

1. Do not claim validation that was not executed.
2. Do not mix unrelated task changes in one commit.
3. Do not perform destructive schema or data changes without migration and rollback analysis.
4. Do not expose secrets in source, logs, fixtures, screenshots, docs, or commits.
5. Do not let structural replacements leave obsolete active implementations behind.
6. Do not let long-running resources grow or remain active without an ownership and cleanup model.
7. Do not let multiple agents share the same mutable worktree for independent workstreams.

## Adaptive constraints

Use the lightest workflow that safely fits the risk.

- TRIVIAL: direct change + focused verification.
- STANDARD: context + implementation + relevant tests.
- STRUCTURAL: current/target/diff + verification.
- CRITICAL: full impact, NFR, migration/security/release controls.

## Engineering judgment

Rules are guardrails, not substitutes for reasoning.

An agent may deviate from a non-hard workflow step when:
- repository evidence makes the step unnecessary or harmful,
- the reason is recorded briefly,
- correctness and recoverability remain intact.
