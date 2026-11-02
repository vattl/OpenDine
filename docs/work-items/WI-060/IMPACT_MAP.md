# Impact Map — WI-060

## Authoritative Owner
`ApprovalService` 负责二维码审批状态机与令牌交付；新增 `ApprovalTokenEnvelopeCipher` 负责唯一的持久化加密格式。

## Change Propagation Path
```text
manager AGREE
→ generate random token
→ SHA-256(token) + AES-GCM(approvalCode, token)
→ t_access_approval token_hash + token_value(envelope only)
→ any instance polls status
→ authenticated decrypt + hash verification
→ existing approvalToken response
→ CAS consume and envelope clear
```

## Consumer Coverage
| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| Flutter cashier | polls `approvalToken` | VERIFIED_UNAFFECTED | NO | response contract unchanged |
| Admin/mobile approver | confirms QR | VERIFIED_UNAFFECTED | NO | request/response unchanged |
| Backend instances | encrypt/decrypt envelope | AFFECTED | YES | shared key required |
| Database/Flyway | envelope storage and legacy cleanup | AFFECTED | YES | migration required |

## Layer Coverage
| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | no UI edit or visible contract change |
| Interaction | VERIFIED_UNAFFECTED | QR polling sequence remains identical |
| Frontend State | VERIFIED_UNAFFECTED | response field remains `approvalToken` |
| API Client | VERIFIED_UNAFFECTED | no request/response schema delta |
| Request Contract | VERIFIED_UNAFFECTED | no field change |
| Backend/Domain | AFFECTED | approval token delivery storage changes |
| Persistence | AFFECTED | migration clears plaintext and standardizes envelope column |
| Response Contract | AFFECTED | same shape, stricter fail-closed semantics |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | none |
| Config/Security | AFFECTED | `APPROVAL_TOKEN_ENVELOPE_KEY` required for QR approval |
| Runtime/NFR | AFFECTED | AES-GCM is local and constant-sized; no extra DB round trip |
| Tests | AFFECTED | crypto/service/migration/contract tests |

## Duplicate Logic / Patch Smells
Payment credential encryption is payment-owned and is not reused; approval receives a purpose-specific cipher and key to avoid secret-domain coupling.

## Contract Delta Summary
HTTP schema is unchanged. Runtime now returns 503 on missing encryption key and rejects corrupted/mismatched envelopes rather than returning a token.

## UI Semantic Impact
None; UI Design Track is not applicable.

## Risks
- Instances with different keys cannot decrypt each other's envelopes; deployment handoff requires one shared secret.
- Active historical plaintext approvals are invalidated; maximum user impact is recreating a QR request within its existing 120-second window.
- Duplicate Flyway versions must be corrected before adding the new migration.
