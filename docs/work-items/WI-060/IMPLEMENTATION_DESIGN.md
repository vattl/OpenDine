# Implementation Design — WI-060

## Root Fix / Owner
`ApprovalService` continues to own token lifecycle, while `ApprovalTokenEnvelopeCipher` owns a versioned AES-256-GCM envelope. No controller may persist or decrypt approval tokens directly.

## Why this location
All QR confirmation and polling paths converge in `ApprovalService`; a dedicated cipher keeps key handling, format validation and authenticated encryption out of business logic.

## End-to-End Change
### Backend
On AGREE, generate the token, hash it, encrypt it with random 96-bit IV and `approvalCode` as AAD, then atomically store hash and envelope. On poll, authenticate/decrypt and verify the hash before returning.
### Frontend
No code change. The successful status response retains `approvalToken`.
### UI / Interaction
No visual or interaction change; prototype gate is NOT_APPLICABLE.
### Data / Persistence
Rename the unintegrated WI-059 migration to unique V037. V038 ensures the legacy column exists with envelope-only semantics, expires active rows containing pre-envelope values, and clears them.
### Interfaces / Contracts
No schema delta. Document new 503 configuration/cipher failure and shared-key deployment requirement.
### Jobs / Events / Integrations
None.

## Preserve / Compatibility
Envelope prefix is versioned. Historical plaintext is deliberately not decrypted or returned. Existing users recreate a QR request; HTTP success shape remains compatible.

## API Consumer Migration / Handoff
Client: NONE. Operations: configure the same high-entropy `APPROVAL_TOKEN_ENVELOPE_KEY` on every instance before deployment; do not reuse JWT or payment secrets.

## Failure / Boundary Behavior
Missing key fails confirmation before state mutation. Unknown prefix, malformed Base64, GCM authentication failure, wrong approval code/key, or token-hash mismatch fails closed and logs only approval identity, never token/ciphertext.

## Runtime / Performance / Reliability
AES-GCM adds constant local CPU and no query. Random IVs make identical tokens produce different envelopes. Database remains cross-instance coordination authority.

## Security / Permissions
AES-256-GCM provides confidentiality and integrity. Approval number AAD prevents moving a valid envelope to another approval row. SHA-256 comparison verifies envelope/token consistency before disclosure.

## UI Design Track
NOT_APPLICABLE: no production UI or user-visible layout change.

## Vertical Slice Plan
1. Add RED cipher and ApprovalService tests.
2. Implement cipher and service integration.
3. Add unique migrations and legacy cleanup.
4. Synchronize API/config/operations docs and handoff.
5. Run focused/full verification, review and gates.

## Verification Strategy
Unit tests cover round-trip, randomized IV, AAD/key/tamper failures, ciphertext persistence, cross-instance retrieval, hash mismatch and missing key. Migration checks prove unique versions and cleanup SQL. Run affected tests plus mandatory clean package.

## Rollback / Recovery
Rollback requires expiring outstanding envelope approvals; never restore plaintext writes. Keep the key available for the 120-second maximum token lifetime during rolling recovery.
