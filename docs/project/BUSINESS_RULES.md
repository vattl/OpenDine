# Project Business Rules / Invariants — PB-2

`.ai/project/business-rules.json` is the machine-readable authority. This file is its human-readable review view. `scripts/governance/validate_business_rules.py` must pass whenever either file changes.

`ENFORCED` means current repository evidence verifies the rule. `TARGET` means the rule is an approved governance constraint but its enforcing Work Item is still pending; it must not be reported as implemented.

### INV-PAY-001

- Status: `ENFORCED`
- Capability/owner: external WeChat payment confirmation / `PaymentSuccessHandler`
- Invariant: Only a verified WeChat callback or authoritative query may confirm an external WeChat payment.
- Verification: payment callback/query signature tests and settlement integration tests.

### INV-PAY-002

- Status: `ENFORCED`
- Capability/owner: payment amount and merchant routing / `PaymentSettlementService`
- Invariant: Payable amount and merchant/shop scope are server-owned and must not be trusted from a client.
- Verification: server-side payable amount and multi-shop merchant binding tests.

### INV-PAY-003

- Status: `ENFORCED`
- Capability/owner: payment/refund accounting application / `PaymentSuccessHandler` and refund ledger services
- Invariant: Payment and refund success application is idempotent and must produce immutable accounting evidence.
- Verification: duplicate callback/refund tests and ledger consistency checks.

### INV-KDS-001

- Status: `ENFORCED`
- Capability/owner: KDS business authority / `com.lanf.kds`
- Invariant: Cloud is the sole KDS business authority; cashier is proxy/cache only.
- Verification: KDS authority-mode, command-contract and legacy-write fail-closed tests.

### INV-ORDER-001

- Status: `ENFORCED`
- Capability/owner: order lifecycle / `OrderController` and order application services
- Invariant: Adding dishes must preserve the original order creation time.
- Verification: add-dish regression tests assert `order_time` is unchanged.

### INV-ORDER-002

- Status: `TARGET` — WI-064
- Capability/owner: order mutation concurrency / order command layer
- Invariant: Every successful business mutation of an order must monotonically increase its revision.
- Verification: concurrent command and stale `expectedVersion` tests.

### INV-PRICE-001

- Status: `TARGET` — WI-066
- Capability/owner: order pricing / future `OrderPricingService` and current pricing owners
- Invariant: Final payable amount is produced by server-owned pricing rules and never by a client-provided total.
- Verification: price tampering, quote and settlement parity tests.

### INV-TABLE-001

- Status: `ENFORCED`
- Capability/owner: table outstanding amount / `TableStatusAmountCalculator`
- Invariant: A table outstanding amount equals the sum of authoritative net payable amounts of all unsettled orders for the same shop and table.
- Verification: table/order amount parity tests covering add dish, merge, discount and refund.

### INV-COMBO-001

- Status: `ENFORCED`
- Capability/owner: combo ordering and pricing / `ComboMealServiceImpl` and order detail persistence
- Invariant: A combo header carries the price; component lines are persisted for traceability and must not be priced again.
- Verification: combo expansion, parent linkage and no-double-charge tests.

### INV-APPROVAL-001

- Status: `TARGET` — WI-059～WI-061
- Capability/owner: sensitive-operation approval / `ApprovalService`
- Invariant: An approval token is bound to exactly one action, resource, amount, operator and shop and can be consumed only once.
- Verification: binding mismatch, expiry and concurrent single-consumption tests.
