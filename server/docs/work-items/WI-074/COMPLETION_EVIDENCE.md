# Completion Evidence — WI-074

Work Item: WI-074
Title: 基于 WI-073 审计结论完成收银端与顾客端电子发票全链路修复与优化
Parent Work: WI-074
Status: COMPLETED

## 1. Code Changes Inventory

1. **Database Migration**:
   - `src/main/resources/db/migration/V050__invoice_token_auth_and_audit.sql`: Added `token_hash`, `token_expire_at`, `token_used_at` with index `idx_token_hash`.
2. **Entity Layer**:
   - `src/main/java/com/lanf/entity/OrderInvoice.java`: Added persistent fields `token_hash`, `token_expire_at`, `token_used_at`.
3. **Service Layer**:
   - `src/main/java/com/lanf/service/impl/OrderInvoiceServiceImpl.java`:
     - Added payment status verification on QR creation (`order.getPay_time() != null && transac_status == success/settled`).
     - Added cumulative active invoice amount check against net revenue (`OrderNetRevenue.netRevenueYuan`).
     - Implemented SHA-256 token hashing and 24-hour expiration.
     - Excised external partner API call (`/v3/new-tax-control-fapiao/...`) to adhere to ordinary merchant boundary.
     - Implemented token verification (`MessageDigest.isEqual`) on `/info` and `/submit-title`.
     - Removed anonymous auto-initialization code completely (returns 404 on missing record).
     - Added PII masking (`maskTaxNo`, `maskPhone`, `maskEmail`) on log output and response DTO.
     - Added state machine constraint in `issueInvoice`: disallows jumping from `PENDING_SCAN` to `SUCCESS`.
4. **Controller Layer**:
   - `src/main/java/com/lanf/controller/PublicInvoiceController.java`: Required `token` parameter on `/info` and `/submit`.
   - `src/main/java/com/lanf/controller/admin/AdminOrderController.java`: Enforced paid order check before generating invoice QR code.
5. **Payment Channel Layer**:
   - `src/main/java/com/lanf/payment/channel/wechat/WechatJsapiChannel.java`: Injected `support_fapiao: true` in JSAPI transactions prepay request.
6. **Presentation Layer (H5 Static Web)**:
   - `src/main/resources/static/invoice-apply.html` & `src/main/resources/static/invoice/apply.html`:
     - Corrected header to "老肥家餐饮 · 电子发票服务".
     - Added privacy security banner.
     - Added submit button debounce protection.
     - Added download URL protocol whitelist verification.
7. **API Documentation**:
   - Synchronized `docs/openapi.yaml` and `docs/API.md` with required `token` and error codes.
8. **Automated Test Suites**:
   - `OrderInvoiceServiceTest.java`: 14 comprehensive test cases covering security, token hash, state machine, cumulative amount, and PII masking.
   - `PublicInvoiceControllerTest.java`: 4 test cases verifying candidate routes and token requirements.
   - `AdminOrderAuditAndInvoiceApiTest.java`: 5 test cases verifying cashier QR generation, payment check, and audit timeline.
   - `WechatJsapiChannelTest.java`: 5 test cases including `support_fapiao: true` parameter verification.

## 2. Build Artifact Verification

- Full Maven compilation and repackage: `.\mvnw.cmd clean package -DskipTests` -> BUILD SUCCESS.
- Artifact: `target/diancan-0.0.1-SNAPSHOT.jar`.
