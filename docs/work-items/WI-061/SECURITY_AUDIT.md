# Security Audit — WI-061

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Threat Model / Controls

- Exact permission derivation has one owner and rejects all legacy broad aliases at runtime.
- AGREE and REJECT use the same authorization rule; `admin:super` bypasses permission only, not credential or throttling controls.
- Request and credential counters are persisted under transactional row locks with `REQUIRES_NEW`, so instances share state and rejected business transactions do not erase counters.
- Composite limiter keys are SHA-256 hashes. Raw account, PIN, password and approval token are neither persisted nor included in audit snapshots.
- Credential failures are failure-only counters and clear after valid credentials; status polling remains outside the limiter.
- 403/429 rejections are persisted through an independent audit transaction with explicit result codes.
- Migration does not grant approval permissions to action-only cashier/operator roles.

## Residual Risk
- A hostile user can intentionally throttle a known manager account for up to 15 minutes; bounded scope, audit evidence and separate operator request throttling limit impact.
- Binding v1 remains a measured compatibility risk until the frontend handoff is implemented and adoption reaches zero.
