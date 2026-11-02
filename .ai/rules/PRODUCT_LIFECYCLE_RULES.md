# Product Lifecycle Rules

Use this track for a new product, a material new product line, or work whose value/problem is not yet established.

## Authoritative product states

`IDEA → RESEARCHED → PROJECT_APPROVED → PRD_APPROVED`

Engineering then continues through the unified lifecycle:

`TECH_DESIGN_APPROVED → UX_DESIGN_APPROVED/NOT_APPLICABLE → IMPLEMENTATION_READY → DEVELOPMENT_ACTIVE → INTEGRATION_READY → REVIEW_APPROVED → SECURITY_APPROVED → TEST_APPROVED → ACCEPTED → RELEASE_READY → DEPLOYED → PRODUCTION_VERIFIED → RELEASED → MONITORED → CLOSED`

States must not be collapsed into `DONE`.

## Required evidence

- IDEA: `PROJECT_CHARTER.md` with problem, users, intended value, constraints and owner.
- RESEARCHED: `RESEARCH_BRIEF.md` with source/evidence inventory, user/market/competitor findings, assumptions and confidence.
- PROJECT_APPROVED: `PRODUCT_ANALYSIS.md` with opportunity, options, value/cost/risk, success metrics and `Go/No-Go Decision: GO`.
- PRD_APPROVED: product PRD plus `PRD_APPROVAL.md` with requirements-to-evidence traceability and `Approval Status: APPROVED`.

Research claims must identify their source. Unsupported assumptions must remain labelled assumptions. An agent may recommend GO/NO-GO but may not invent human approval.

Existing-product maintenance may set `Product Inception Gate: NOT_APPLICABLE` with a reason in `DELIVERY_GATE.md`.
