# Test Report — WI-074

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0
Total Checks: 29
Passed Checks: 29

## Execution Summary

| Test Suite | Tests Run | Failures | Errors | Result |
|---|---|---|---|---|
| `OrderInvoiceServiceTest` | 14 | 0 | 0 | PASS |
| `PublicInvoiceControllerTest` | 4 | 0 | 0 | PASS |
| `AdminOrderAuditAndInvoiceApiTest` | 5 | 0 | 0 | PASS |
| `WechatJsapiChannelTest` | 6 | 0 | 0 | PASS |

## Scenario Matrix Coverage (SC-01 to SC-09)

| Scenario ID | Test Method / Evidence | Result |
|---|---|---|
| SC-01 (Missing Token 401) | `PublicInvoiceControllerTest#getInvoiceInfo_missingToken_returns400BadRequest`, `OrderInvoiceServiceTest#getInvoiceInfoForPublic_missingToken_rejected401` | PASS |
| SC-02 (Missing Record 404 & No Auto-init) | `OrderInvoiceServiceTest#getInvoiceInfoForPublic_missingRecord_rejected404` | PASS |
| SC-03 (Invalid/Expired Token 403) | `OrderInvoiceServiceTest#getInvoiceInfoForPublic_invalidToken_rejected403`, `OrderInvoiceServiceTest#getInvoiceInfoForPublic_expiredToken_rejected403` | PASS |
| SC-04 (Normal Title Submission) | `OrderInvoiceServiceTest#submitInvoiceTitleFromCustomer_validCompany_updatesStatusAndUsedAt` | PASS |
| SC-05 (Unpaid Order 400) | `OrderInvoiceServiceTest#createInvoiceQrcode_unpaidOrder_rejected`, `AdminOrderAuditAndInvoiceApiTest#createInvoiceQrcode_unpaidOrder_rejected` | PASS |
| SC-06 (Cumulative Amount / Refund Ceiling) | `OrderInvoiceServiceTest#createInvoiceQrcode_cumulativeLimitExceeded_rejected`, `OrderInvoiceServiceTest#createInvoiceQrcode_excessiveAmount_rejected` | PASS |
| SC-07 (PII Masking) | `OrderInvoiceServiceTest#getInvoiceInfoForPublic_validToken_returnsMaskedPii`, `OrderInvoiceServiceTest#utilityMethods_maskingAndSanitize` | PASS |
| SC-08 (WeChat JSAPI support_fapiao: true) | `WechatJsapiChannelTest#createPrepayIncludesSupportFapiao` | PASS |
| SC-09 (H5 Compliance & Debounce) | `ui/SCREENSHOT_VISUAL_DIFF_REPORT.md`, `ui/DEVICE_UX_VERIFICATION_REPORT.md` | PASS |

## Build and Compilation Verification

- Full Maven clean compile and packaging command (`.\mvnw.cmd clean package -DskipTests`) executed successfully with BUILD SUCCESS.
- Runnable JAR artifact generated at `target/diancan-0.0.1-SNAPSHOT.jar`.
