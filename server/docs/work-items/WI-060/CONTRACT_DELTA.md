# Contract Delta — WI-060

## HTTP schema
No request or response field is added, removed or renamed.

## Semantic delta
- Approved QR tokens are recovered from an authenticated encrypted envelope rather than plaintext storage.
- Missing key or invalid envelope fails closed; API documents a 503 configuration/runtime failure.

## Compatibility
Existing cashier and manager clients remain compatible. Outstanding pre-migration plaintext QR approvals expire and must be recreated.
