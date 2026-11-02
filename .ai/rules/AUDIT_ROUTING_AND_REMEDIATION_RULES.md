# Audit Routing and Remediation Rules

Every Work Item must select its audit coverage from the requirement type, risk and affected surfaces before implementation. `AUDIT_PLAN.md` is mandatory and `validate_audit_plan.py --phase plan` must pass before production edits.

## Routing matrix

- Universal: `CORE`, `THIRD_PARTY`
- `FEATURE`, `CHANGE`, `REFACTOR`: `ARCHITECTURE`
- `BUG`, `REPAIR`: `ROOT_CAUSE`, `REGRESSION`
- `MAINTENANCE`, `DOCS`: `CONSISTENCY`
- UI impact: `UI_UX`
- API/contract impact: `CONTRACT`
- Security/auth/privacy impact or HIGH/CRITICAL risk: `SECURITY`
- Data/schema/migration impact: `DATA_MIGRATION`
- Reliability/performance/operations impact: `RELIABILITY_PERFORMANCE`

Additional tracks may be selected, but mandatory tracks may not be omitted. Third-party acceptance audit remains universal and does not replace specialist review.

`WORK_ITEM.md` is the authority for Work Type. `AUDIT_PLAN.md` must match it exactly; a self-declared lower-cost type is not valid routing evidence. Risk and impact inputs remain bound to `IMPACT_MAP.md`.

## Finding-to-fix loop

An audit finding is implementation input, not a documentation inconvenience:

`AUDIT BLOCKED → archive failed audit → IMPLEMENT code/config fix → RETEST → update evidence → RESEAL packet → dispatch different fresh-context auditor → AUDIT PASS`

- Preserve every failed canonical receipt/report under `audit-history/<session-id>/` before a new audit overwrites canonical artifacts.
- The implementation owner fixes findings; the auditor must not repair its own findings.
- `AUDIT_REMEDIATION.md` must map every archived finding to repository-relative code/configuration paths and structured PASS retest evidence. Every fix path must have a real content delta from the declared pre-remediation Git commit. Every finding must map to concrete regression-test selectors that exist in sealed test source and have a finding-specific PASS row in the sealed test report. Global prose, an unchanged/unrelated file, or a generic PASS report is not closure.
- Editing only status prose, lowering severity, deleting history, or reusing the same stale packet is false closure.
- Acceptance requires `validate_audit_plan.py --phase accept`, the normal third-party validator, zero open findings and a fresh approved audit.

## Local Git completion

Acceptance and integration are separate. After acceptance evidence is final:

1. inspect status and classify pre-existing/current/unknown changes;
2. stage only current Work Item files and review the staged diff;
3. create a descriptive local commit;
4. set Work Item integration truth to `INTEGRATED`, commit that evidence as part of the task transaction when needed;
5. run `gate.py work --phase integrate` from a clean worktree.

The declared `Change Paths` must exactly equal the files actually changed by the recorded feature commit. A path merely present in that commit's tree, or an unrelated commit with an unchanged claimed path, is false integration.

A normal completed task must reach `INTEGRATED`. A non-Git directory must be safely bootstrapped or the task remains `READY_TO_COMMIT`; unrelated dirty work must be isolated or explicitly blocked, never swept into the commit. Local commit does not authorize push.

