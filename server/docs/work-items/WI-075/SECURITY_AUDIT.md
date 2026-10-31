# Security Audit — WI-075

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

### T1: Store Multi-Tenancy Boundary Isolation (P0)
- **Threat**: Cross-shop invoice data leakage where an operator from Store A queries or rejects invoice applications belonging to Store B.
- **Remediation**:
  - `AdminOrderController#listInvoices` retrieves `shopId` via `AdminShopRequest.getResolvedShopId(httpServletRequest)`.
  - In `OrderInvoiceServiceImpl#pageInvoiceForAdmin`, when `shopId != null`, `lambdaQuery.eq(OrderInvoice::getShop_id, shopId)` is strictly appended, ensuring store-level data partition.
  - Reject operations log operator ID and verify entity existence.

### T2: State Machine Integrity & Anti-Tampering (P0)
- **Threat**: Financial staff or malicious requests attempting to reject already finalized/issued invoices, causing ledger inconsistency.
- **Remediation**:
  - `OrderInvoiceServiceImpl#rejectInvoice` strictly checks `STATUS_ISSUED.equals(invoice.getInvoice_status())` and rejects the operation with an explicit error.
  - Resubmission by customers through `submitInvoiceTitleFromCustomer` validates that if previously `REJECTED`, the status resets cleanly to `TITLE_SUBMITTED`, clears `error_msg`, and updates `token_used_at`.

### T3: Input Validation & Injection Prevention (P1)
- **Threat**: Malicious rejection reasons or XSS payloads entered in the rejection dialog reflected onto customer H5.
- **Remediation**:
  - Strict non-empty validation on `invoiceId` and `reason` in `AdminOrderController#rejectInvoice`.
  - Customer H5 (`invoice-apply.html`) safely encodes error reason text inside standard text containers without executing raw HTML scripts.

### T4: Merchant Boundary & Secret Protection (P0)
- **Threat**: Exposure of tax keys or inadvertent reliance on partner-only WeChat APIs.
- **Remediation**:
  - Zero hardcoded API keys or tax credentials.
  - Conforms 100% to Ordinary Merchant architecture: offline manual tax machine workflow does not transmit plaintext tax secrets over public networks.
