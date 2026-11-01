# Review Remediation — WI-080 / T01

Cycle: 1
Trigger: first fresh specification and code-quality reviews both returned FAIL with one High evidence-integrity finding.

## Required remediation

1. Retain exact-final-head Java 8 output proving all six focused tests and the full package command pass.
2. Retain sanitized before/after administrator, shop and migration counts around the expected nonempty-bootstrap refusal.
3. Update lifecycle evidence to reference the durable artifacts rather than ignored local logs.
4. Segment the public Nginx path from MySQL/Redis on separate Compose networks and test the boundary.
5. Replace broad service/base image tags with verified exact-version or digest-pinned official image references where supported, and document upgrade responsibility.
6. Reseal the Git-range snapshot and dispatch two different fresh reviewers; the archived first-cycle reviews cannot approve the remediated snapshot.

## Archived reviews

- `task-reviews/attempts/01-T01-SPEC_COMPLIANCE-FAIL.md`
- `task-reviews/attempts/01-T01-CODE_QUALITY-FAIL.md`

Status: COMPLETE

Cycle-two result: fresh specification and code-quality reviewers both returned PASS with zero open Critical/High findings. The quality reviewer retained one non-blocking Medium follow-up: separate and delete bootstrap-only credentials after first login/password rotation so ordinary Compose maintenance no longer depends on them.
