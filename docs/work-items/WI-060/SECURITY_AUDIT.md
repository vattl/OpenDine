# Security Audit — WI-060

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Threat Model / Controls

- Database/backup disclosure: only SHA-256 token hash and AES-256-GCM envelope are stored; no directly usable token is persisted.
- Envelope transplant: `approvalCode` is authenticated AAD; moving ciphertext to another row fails authentication.
- Ciphertext/key mismatch or tamper: decryption fails closed with 503 and never returns token.
- Envelope/hash inconsistency: constant-time hash comparison fails closed before response disclosure.
- Missing/weak configuration: keys shorter than 32 bytes are treated as unavailable; confirmation fails before state mutation.
- Expired token disclosure: both PENDING and APPROVED rows become EXPIRED; envelope is cleared before any token response.
- Historical plaintext: V038 expires active legacy rows and clears every non-`aet:v1:` value.
- Logging: approval identity may be logged; raw tokens, envelopes and key material are never logged.

## Residual Risks

- MEDIUM operational: inconsistent keys across instances cause safe 503 failures. The deployment handoff mandates one shared secret and a two-minute drain before rotation.
- LOW schema naming: legacy column remains named `token_value` for rolling compatibility, but its DDL comment and all writers enforce envelope-only semantics. A later maintenance migration may rename it after all historical versions are retired.
