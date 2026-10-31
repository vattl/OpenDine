# Security Audit — WI-015

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Findings and controls

- Authentication/authorization: all three endpoints remain behind `SysInterceptor` and explicit `cashier:operate` path mappings.
- Tenant isolation: orders and payment attempts are always selected with the resolved `shop_id`; the client cannot choose a merchant or shop through the body.
- Amount integrity: create accepts no amount field and derives cents from `OrderNetRevenue`; settlement validates the persisted expected cents.
- Forged success defense: callback keeps platform signature verification and AES-GCM decryption; settlement validates state, out-trade-no, trade type, amount, and—when supplied—mchid/appid.
- Replay/race defense: unique `active_key`, unique `out_trade_no`, per-order lock, transactional `SELECT ... FOR UPDATE`, successful-order guard, and existing immutable payment ledger.
- Unknown-result defense: create timeouts remain `UNKNOWN`; a new QR is blocked until authoritative query resolves the attempt.
- Secret handling: merchant credentials remain server-side in the existing DB-backed key store. Scoped secret-pattern scan returned no hard-coded secret in changed payment files.
- Logging: no request authorization, private key, APIv3 key, or full callback body is added to logs.

Dependency scan is not applicable because this change adds or updates no dependency.
