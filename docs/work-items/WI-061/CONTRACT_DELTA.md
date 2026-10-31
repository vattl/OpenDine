# Contract Delta — WI-061

## HTTP schema
No success request/response field is removed or renamed. Protected endpoints may newly return HTTP 429 with code `ACCESS_APPROVAL_RATE_LIMITED` and data fields `retryAfterSeconds` and `rateLimitScope`.

## Semantic delta
- Approval permission is the exact requested action plus `:approve`; broad aliases no longer authorize decisions.
- QR AGREE and REJECT have symmetric permission enforcement.
- Excessive requests or credential failures are rejected across instances for a bounded period.

## Compatibility
Existing normal success flows remain wire-compatible. Clients that immediately retry errors should adopt the 429 countdown contract. Role assignments are additively migrated before runtime enforcement.
