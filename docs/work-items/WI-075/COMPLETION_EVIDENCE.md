# Completion Evidence — WI-075

Work Item: WI-075
Title: 财务后台人工开票工作台与申请流转支撑
Parent Work: WI-075
Status: COMPLETED

## 1. Code Changes Inventory

1. **Entity Layer**:
   - `src/main/java/com/lanf/entity/OrderInvoice.java`:
     - Added `STATUS_REJECTED = "REJECTED"` constant.
2. **Service Layer**:
   - `src/main/java/com/lanf/service/IOrderInvoiceService.java`:
     - Added `pageInvoiceForAdmin(Integer shopId, Integer page, Integer limit, String status, String keyword, String startDate, String endDate)`.
     - Added `rejectInvoice(Integer invoiceId, String reason, Integer operatorId)`.
   - `src/main/java/com/lanf/service/impl/OrderInvoiceServiceImpl.java`:
     - Implemented `pageInvoiceForAdmin` supporting multi-tenant shop isolation, pagination, status tab filtering, keyword search, date range, and real-time status metric counts.
     - Implemented `rejectInvoice` verifying entity existence, blocking rejection of already-issued invoices, recording `error_msg`, updating status to `REJECTED`, and logging operator ID.
     - Relaxed `issueInvoice` requiring non-blank `fapiaoFileUrl`, permitting offline manual tax machine invoices without external URLs.
     - Updated `getInvoiceInfoForPublic` to expose `rejectReason` when status is `REJECTED`.
     - Updated `submitInvoiceTitleFromCustomer` to allow resubmission when status is `REJECTED`, clearing `error_msg` and resetting to `TITLE_SUBMITTED`.
3. **Controller Layer**:
   - `src/main/java/com/lanf/controller/admin/AdminOrderController.java`:
     - Added `GET /admin/order/invoice/list` endpoint with shop isolation via `AdminShopRequest.getResolvedShopId`.
     - Added `POST /admin/order/invoice/reject` endpoint with parameter validation and audit logging.
4. **Frontend UI**:
   - `src/main/resources/static/invoice/admin.html`: Created complete responsive finance workbench page featuring metric cards, filter tabs, keyword search, table with one-click copy of tax numbers, issue modal, reject modal, and CSV export.
   - `src/main/resources/static/invoice-apply.html` & `src/main/resources/static/invoice/apply.html`:
     - Added working hours offline manual issue notice banner.
     - Added support for `REJECTED` status display with rejection reason alert.
     - Added "重新修改发票抬头并提交" button and form unlock flow.
5. **Documentation**:
   - Synchronously documented `/admin/order/invoice/list` and `/admin/order/invoice/reject` in `docs/openapi.yaml` and `docs/API.md`.
