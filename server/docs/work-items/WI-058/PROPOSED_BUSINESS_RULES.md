# Proposed Project Business Rules — PB-2

This candidate is validated before promotion. After WI-058 acceptance it replaces the durable views in `.ai/project/business-rules.json` and `docs/project/BUSINESS_RULES.md`. `ENFORCED` means current repository evidence already verifies the rule; `TARGET` is an approved governance constraint whose enforcing Work Item is still pending and must not be represented as implemented.

### INV-PAY-001

Status: `ENFORCED`

Only a verified WeChat callback or authoritative query may confirm an external WeChat payment.

### INV-PAY-002

Status: `ENFORCED`

Payable amount and merchant/shop scope are server-owned and must not be trusted from a client.

### INV-PAY-003

Status: `ENFORCED`

Payment and refund success application is idempotent and must produce immutable accounting evidence.

### INV-KDS-001

Status: `ENFORCED`

Cloud is the sole KDS business authority; cashier is proxy/cache only.

### INV-ORDER-001

Status: `ENFORCED`

Adding dishes must preserve the original order creation time.

### INV-ORDER-002

Status: `TARGET` (WI-064)

Every successful business mutation of an order must monotonically increase its revision.

### INV-PRICE-001

Status: `TARGET` (WI-066)

Final payable amount is produced by server-owned pricing rules and never by a client-provided total.

### INV-TABLE-001

Status: `ENFORCED`

A table outstanding amount equals the sum of authoritative net payable amounts of all unsettled orders for the same shop and table.

### INV-COMBO-001

Status: `ENFORCED`

A combo header carries the price; component lines are persisted for traceability and must not be priced again.

### INV-APPROVAL-001

Status: `TARGET` (WI-059～WI-061)

An approval token is bound to exactly one action, resource, amount, operator and shop and can be consumed only once.
