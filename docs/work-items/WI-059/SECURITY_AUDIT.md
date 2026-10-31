# Security Audit — WI-059

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Threat Model / Controls

- Cross-resource/action/amount/operator/shop replay: v2 exact comparisons before CAS.
- Cross-terminal replay: terminal context bound in v2 and propagated by current consumers.
- Failed comparison consuming a valid token: tests verify mapper update is never invoked.
- Historical client outage: explicit v1 compatibility state, response marker and security log.
- Schema rollout: additive non-null default 1 preserves existing rows.

## Residual Risks

- MEDIUM: `X-Terminal-Id` is contextual identity, not cryptographic device attestation. Registered terminal credentials are a later hardening option.
- MEDIUM: callers may still request v1 during the measured compatibility window. WI-061 must enforce v2 after consumer adoption and must not silently extend the window.
- Out of scope: plaintext QR token storage is WI-060 and remains a separate P0 item.
