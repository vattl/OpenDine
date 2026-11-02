# /review

Perform release-oriented engineering review.

Input: `$ARGUMENTS`

## Adaptive Review Rule

Full release-oriented review is required for STRUCTURAL/CRITICAL work before release when material risk exists. For low-risk local changes, review may be scoped to the changed behavior and regression surface. Prioritize concrete correctness findings over style commentary.

## Diff-Driven Review

Compare four things:

1. User request / intended behavior
2. Target State
3. Planned Structural Diff
4. Actual implemented Diff

Report:

- Missing Diff
- Unexpected Diff
- Incorrect Diff
- Legacy Diff Remaining
- Accidental change to UNCHANGED behavior

## Review Categories

- Requirement correctness
- Regression
- Architecture
- Database safety
- API compatibility
- Authentication / Authorization
- Security
- Performance
- Error handling
- Concurrency
- Testing
- Documentation impact

Severity:

- CRITICAL
- HIGH
- MEDIUM
- LOW

CRITICAL/HIGH block release and route back to IMPLEMENTATION.

This command is the engineering review pass. It does not by itself satisfy the mandatory acceptance cross-audit. Before `ACCEPTED`, a different fresh-context, read-only Agent must review the sealed `AUDIT_PACKET.md`, write `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`, and pass `validate_third_party_audit.py`.

## Interruption-Safe Review

If review stops mid-scope, record the reviewed scope and remaining scope. The next agent must not assume unreviewed files/categories passed.


---

# Commit Boundary Review

Review whether completed tasks have clean, traceable commit boundaries.

Flag:

- mixed unrelated changes
- completed tasks without commit evidence
- vague commit messages
- commits that cannot be independently reverted without significant collateral changes


# UI Review

When UI/layout work is in scope, compare production implementation against the approved prototype/blueprint and UI Diff. Review:
- hierarchy
- duplicate legacy UI
- design-token consistency
- responsive behavior
- preservation of business interactions
- accessibility regressions where relevant

Build/type success alone is insufficient evidence for visual correctness.

---

# UI Fidelity Review Extension

For UI work governed by an approved HTML prototype, review:

- approved HTML prototype exists
- measured UI spec exists when fidelity is material
- implementation map preserves business logic while replacing legacy presentation
- production was compared at the same target viewport where possible
- major scale/spacing/typography/proportion deltas are resolved
- no legacy layout remains active unexpectedly
- accepted deviations are explicit rather than accidental
- every prototype region and legacy region has an explicit production mapping/disposition
- the translation plan gate passed before production UI editing
- the final fidelity gate passed after same-viewport comparison
- every approved interaction/data need has a real production capability mapping
- API_EXTENSION/NEW_API rows have VERIFIED backend requests and consumer integration
- no visual-only, local-only, mock, placeholder or hardcoded-success interaction simulates completion
- the backend coordination report is CLEAR, or OPEN items are explicitly surfaced and acceptance remains blocked/partial

A materially different production scale despite a matching component structure is a real review finding.


---

# v2.6 Production Reliability Review

For runtime-sensitive work, review additionally:

- Can anything grow without bound?
- Can listeners/timers/subscriptions/resources be created more than once or fail to release?
- Can async work outlive its owner?
- Can requests/jobs overlap unexpectedly?
- Are writes idempotent where duplicate execution is realistic?
- Can retries amplify an outage?
- Is concurrency/backlog bounded?
- Do database/query paths remain safe at expected scale?
- Are failure/timeout/partial-success paths intentional?
- Can a slow dependency exhaust a shared resource?
- Is the failure diagnosable in production?

CRITICAL/HIGH runtime-reliability findings block release.

# v3.2 UI Screenshot Evidence

When reviewing any UI work with an approved HTML prototype, check the latest `/ui-verify` evidence.

Review must distinguish:

- requested target
- approved prototype screenshot
- production screenshot
- programmatic diff signals
- accepted rendering variance
- unresolved material visual deltas

A missing major section or retained legacy UI is a review issue even if aggregate fidelity scores are high.

For UI acceptance, independently check the output of `validate_ui_fidelity.py --phase accept`. Do not accept “close enough”, build success, or functional usability as a substitute for target-state and legacy-removal evidence.

---

# v3.4 Capability & Evidence Review

For shared/repeated repairs, review additionally:

- Was the authoritative owner fixed rather than only a symptom consumer?
- Were all known consumers searched and classified?
- Did semantic duplicates remain inconsistent?
- Did implementation introduce caller-specific patch smells?
- Is every material requirement traceable to evidence?
- Is any production path using fake/mock/hardcoded/placeholder behavior to simulate completion?
- Would the regression test fail if the fix were removed?

Unexplained consumer gaps or false-completion evidence are blocking findings.
