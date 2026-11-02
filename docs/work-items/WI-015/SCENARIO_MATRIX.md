# Scenario Matrix — WI-015

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | Create Native QR | Authenticated cashier, same-shop unsettled order, enabled merchant | Returns server amount, unique outTradeNo, codeUrl and expiry | INV-PAY-002 | service test + API contract | PASS |
| S02 | Idempotent create retry | Same order has valid active NOTPAY attempt | Reuses same attempt/QR; no second charge intent | INV-PAY-003 | `createUsesServerAmountAndReusesLiveCodeUrl` | PASS |
| S03 | Expired/closed retry | Latest attempt terminal or expired and order unpaid | Closes old WeChat order before creating a new outTradeNo | INV-PAY-003 | service branch review + unique active-key constraint | PASS |
| S04 | Cross-shop access | Cashier shop differs from order/attempt shop | Rejects without calling WeChat | INV-PAY-002 | shop-scoped `findOrder/findLatest/findActive` review + permission regression | PASS |
| S05 | Client amount injection | Request includes extra/malicious amount field | Field ignored; server amount used | INV-PAY-002 | controller DTO surface + `OrderNetRevenue.netRevenueFen` test path | PASS |
| S06 | Callback success | Valid signed/decrypted matching transaction | Order settles once; ledger and side effects execute | INV-PAY-001, INV-PAY-003 | shared success service tests + 1263-test regression | PASS |
| S07 | Callback lost, query success | WeChat query returns matching SUCCESS | Same local settlement occurs once | INV-PAY-001, INV-PAY-003 | `querySuccessInvokesSharedSettlementCompensation` | PASS |
| S08 | Query/callback race | Both paths observe same SUCCESS concurrently | Exactly one state transition/ledger/side-effect set | INV-PAY-003 | transactional `FOR UPDATE`, local lock, immutable ledger regression | PASS |
| S09 | Mismatched signed result | Wrong mchid/appid/outTradeNo/amount/tradeType | Rejects settlement and records no success | INV-PAY-001, INV-PAY-002 | `rejectsAmountMismatchBeforeChangingOrder` + validation branch review | PASS |
| S10 | Close unpaid | WeChat close succeeds | Attempt becomes CLOSED; order remains unsettled | INV-PAY-001 | close-path review and compilation/full regression | PASS |
| S11 | Close paid | Local order already SUCCESS | Refuses close | INV-PAY-001 | close-state guard review | PASS |
| S12 | Transport timeout | Create/query response unknown | Never marks success; preserves resolvable attempt | INV-PAY-001, INV-PAY-003 | `createDoesNotReplaceAnUnknownAttemptThatCouldStillBePayable` | PASS |
| S13 | Existing mini-program flow | Existing JSAPI callback payload | Existing payment behavior remains compatible | INV-PAY-001, INV-PAY-003 | full Maven suite: 1264 tests, 0 failures/errors | PASS |
| S14 | Refund/reconciliation reuse | Native order already confirmed | Existing refund and ledger/statement reconciliation paths recognize WeChat transaction | INV-PAY-003 | existing refund/reconciliation suite within full regression | PASS |

## Acceptance rule

All material scenarios must be PASS. No payment scenario may be waived with an unverified production assumption.
