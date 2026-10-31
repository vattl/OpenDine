# Security Audit — WI-027

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Threat model and checks

- Asset: merchant credentials, receivable limits, order/payment truth and financial ledger.
- Trust boundaries: authenticated cashier request, `X-Shop-Id` resolution, WeChat API responses/callbacks, and database migrations.
- Authorization: route requires `receivable:view`; controller also checks the resolved administrator's shop access.
- Tenant isolation: eligible accounts are queried with the server-resolved shop ID; the endpoint does not accept a client-provided account scope.
- Tampering/repudiation: authoritative payment ledger remains recorded before mutable order projection in the same transaction.
- Secrets: no certificate, private key or API secret is added to route responses or documentation.
- Injection: MyBatis/query-wrapper parameter binding is retained; no request value is concatenated into executable SQL.
- Availability: eligible-account query is bounded to active candidates; no new external call is made by this read endpoint.

## Verdict

No critical, high, or required security finding remains open.
