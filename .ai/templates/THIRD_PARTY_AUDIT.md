# Third-Party Agent Cross-Audit — WI-XXX

Audit Decision: APPROVED / BLOCKED
Independence Status: VERIFIED / FAILED
Fresh Context: YES / NO
Read-Only Audit: YES / NO
Implementer Agent: AGENT-ID
Auditor Agent: AUDITOR-ID
Auditor Provider / Model: PROVIDER / MODEL
Audit Mode: INDEPENDENT_AGENT / CROSS_MODEL / EXTERNAL_PROVIDER
Audit Session ID: SESSION-ID
Reviewed Work Item: WI-XXX
Reviewed Snapshot: immutable snapshot identifier
Audit Packet: AUDIT_PACKET.md
Audit Packet SHA256: 64-character-sha256
Audit Receipt: AUDIT_RECEIPT.md
Audit Receipt SHA256: 64-character-sha256
Provider Readiness: NOT_APPLICABLE / AGENT_PROVIDER_READINESS.md
Provider Readiness SHA256: NOT_APPLICABLE / 64-character-sha256
Critical Open: 0
High Open: 0
Required Findings Resolved: YES / NO
Acceptance Coverage: COMPLETE / INCOMPLETE
Acceptance Criteria Reviewed: 0
Evidence Integrity: VERIFIED / FAILED

## Review Coverage

| Axis | Scope | Evidence | Verdict |
|---|---|---|---|
| REQUIREMENT | Original request and scope | EV-01, EV-02 | PASS / FAIL |
| CORRECTNESS | Behavior and edge cases | Evidence IDs/paths reviewed | PASS / FAIL |
| ARCHITECTURE | Ownership, contracts and affected surfaces | Evidence IDs/paths reviewed | PASS / FAIL |
| SECURITY | Threats and security gate | Evidence IDs/paths reviewed | PASS / FAIL |
| TEST_EVIDENCE | Test quality and reproducibility | Evidence IDs/paths reviewed | PASS / FAIL |
| FALSE_COMPLETION | Mocks, placeholders and unsupported claims | Evidence IDs/paths reviewed | PASS / FAIL |
| ACCEPTANCE | Criterion coverage and user outcome | Evidence IDs/paths reviewed | PASS / FAIL |

## Acceptance Criterion Audit

Every Review Coverage `Evidence` and Acceptance Criterion Audit `Evidence Reviewed` cell is a comma-separated list containing only exact Evidence IDs or paths from the sealed packet inventory. Criterion IDs must exactly match the packet's canonical acceptance contract.

| Criterion ID | Evidence Reviewed | Auditor Verdict | Notes |
|---|---|---|---|
| AC-01 | Evidence IDs/paths | PASS / FAIL | Independent conclusion |

## Findings

Use exactly one `AUDIT-NONE` / `NONE` / `CLOSED` row only when no findings exist. `NONE` severity is forbidden for any real finding. Every real finding must use its actual severity, be closed, and contain reverification evidence before approval.

| Finding ID | Severity | Finding | Required Action | Status | Reverification |
|---|---|---|---|---|---|
| AUDIT-NONE | NONE | No findings | None | CLOSED | Complete independent review |

## Auditor Declaration

I reviewed the sealed packet from fresh context without editing implementation files. The decision above is based on the referenced evidence, not the implementer's completion claim.

For `Audit Mode: EXTERNAL_PROVIDER`, the readiness reference/hash are mandatory and must prove `Provider State: READY` plus `Live Probe: PASS`. They do not replace independent evidence review.

