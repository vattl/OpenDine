# Security Audit — WI-030

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS
DAST: NOT_APPLICABLE

## Findings addressed

- Client-controlled `merchantId` can no longer select the recipient merchant for a new payment.
- Bound merchant credentials are rejected when owned by another shop; only the order shop or a previously bound global template is valid.
- Payment callbacks fail closed when `mchid` or `appid` is missing or differs from the bound configuration.
- Unknown refund callbacks cannot create local refund state or infer an order from a fuzzy identifier.
- Refund amount, original transaction ID, merchant number, shop and merchant configuration version must match the registered request before accounting mutation.
- Callback key candidates are selected by the signed `Wechatpay-Serial` value through indexed equality predicates.
- DB state, not an unbounded JVM-local cache, decides the merchant for new money movement.

## Assets and trust boundaries

- Assets: merchant private credentials, APIv3 keys, payment/refund identities, immutable payment ledger and order settlement state.
- Trust boundaries: client to backend, backend to WeChat Pay, signed callback to callback controller, shop-scoped order to merchant configuration, application to MySQL.

## Abuse cases

- Client attempts to choose another receiving merchant through `merchantId`.
- Signed callback is valid for one merchant but is applied to another shop's order.
- Attacker or operator submits an unknown refund notification or changes amount/transaction/merchant fields.
- One application node keeps a stale enabled merchant after another node disables or rotates it.

## Authentication, authorization and isolation

Public WeChat callbacks remain protected by signature verification and encrypted-resource decryption. Business mutation additionally requires exact shop/order/merchant binding. Admin permission contracts are unchanged.

## Secret and logging review

- Diff scan found no PEM private keys, Bearer tokens, APIv3 keys or merchant secrets.
- Existing callback logging keeps body/payload summaries and hashes rather than raw decrypted financial payloads.
- No credential value was added to an API response, exception message or new log statement.

## Residual operational risks

- V033 deliberately fails if historical `t_order.order_no` duplicates exist; production must run the documented duplicate preflight and remediate before deployment.
- Historical pending refunds that cannot be backfilled with a complete merchant binding remain fail-closed and require manual reconciliation.
- The application-wide configuration master key remains a deployment secret/trust boundary; per-row ciphertext and shop/config binding provide tenant separation inside the application, but this change does not introduce an external per-merchant KMS.

## Findings

| ID | Severity | Finding | Evidence | Owner | Resolution / Risk Acceptance | Reverification |
|---|---|---|---|---|---|---|
| SEC-030-01 | Critical | Client merchant fallback could influence funds routing | Routing unit tests | Payment | Fixed: server default/rules only | PASS |
| SEC-030-02 | High | Refund callback was not bound to exact registered request identity | Refund ledger/controller tests | Payment | Fixed: exact request/shop/transaction/mchid/config validation | PASS |
| SEC-030-03 | High | Bound credential lookup did not reject another shop | Key store/payment success tests | Payment | Fixed: expected-shop enforcement | PASS |
