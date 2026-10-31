# /incident

Handle a production incident with service restoration prioritized over elegant redesign.

Input: $ARGUMENTS

## Lifecycle

DETECT
→ ASSESS IMPACT
→ MITIGATE
→ STABILIZE
→ PRESERVE EVIDENCE
→ ROOT CAUSE
→ PERMANENT FIX
→ POSTMORTEM
→ PREVENT RECURRENCE

## Rules

- Prefer reversible mitigation first.
- Do not perform broad refactors during active mitigation.
- Record timeline, impact, mitigation, and remaining risk.
- After stabilization, create normal bug/change tasks for permanent fixes.
- Add missing tests/monitoring that would have detected or prevented recurrence.
