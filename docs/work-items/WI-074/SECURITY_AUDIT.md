# Security Audit — WI-074

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Medium Open: 0
Low Open: 0
Secret Scan: PASS
Dependency Scan: PASS
SAST: PASS

## 1. Threat Modeling & Vulnerability Remediation Analysis

### T1: Order Traversal & Anonymous Data Exposure (P0)
- **Previous Risk**: Attackers could supply arbitrary `orderNo` to `GET /public/invoice/info` to view sensitive customer info, or trigger automatic blank invoice creation in the database.
- **Remediation**:
  - Implemented cryptographic token authentication (`token` parameter mandatory).
  - High-entropy UUID token generated upon cashier QR code creation; only the SHA-256 digest is stored in `token_hash`.
  - Constant-time hash verification via `MessageDigest.isEqual`.
  - 24-hour expiration enforced via `token_expire_at`.
  - Missing records return 404; auto-initialization code completely removed.

### T2: Sensitive Personal Information Leaks in Logs & UI (P0)
- **Previous Risk**: Full tax numbers, mobile phone numbers, and email addresses were logged in plaintext and displayed unmasked on the H5 page.
- **Remediation**:
  - Server logs sanitized: `maskTaxNo` masks middle 8 digits (`9111********0000`), `maskPhone` masks middle 4 digits (`138****5678`), and `maskEmail` masks prefix (`f***e@domain.com`).
  - Response DTO from `GET /public/invoice/info` transmits only masked PII to the client.

### T3: State Machine Bypass & Over-Invoicing Fraud (P1)
- **Previous Risk**: Invoices could be requested or issued for unpaid orders, or cumulative invoice amounts could exceed actual paid amounts after refunds.
- **Remediation**:
  - Explicit payment check: order must be paid (`transac_status == SUCCESS/settled && pay_time != null`).
  - Net revenue calculation (`OrderNetRevenue.netRevenueYuan`) accounts for discounts, service fees, gift cards, and refunds.
  - Active invoice sum (`TITLE_SUBMITTED`, `ISSUING`, `SUCCESS`) verified against remaining balance before QR generation.
  - State machine prohibits transition directly from `PENDING_SCAN` to `SUCCESS`.

### T4: Client Protocol Injection & False Compliance Claim (H5)
- **Previous Risk**: Untrusted download URLs could inject `javascript:` URIs; H5 page falsely claimed State Taxation Administration authority.
- **Remediation**:
  - Download URL sanitized with whitelist (`http://`, `https://`, `/`).
  - Removed misleading national authority claims; clearly branded as store service.
  - Button debounce implemented to prevent race condition replay attacks.

## 2. Invariant & Security Verification

All security invariants verified through automated unit and mock controller tests in `OrderInvoiceServiceTest` and `PublicInvoiceControllerTest`.
