# Prototype Interaction Capability Contract — WI-075

UI ID: UI-FINANCE-INVOICE-001
Approved Prototype: `finance-invoice-prototype.html`
Parent Work Item: WI-075

Capability Mapping Status: COMPLETE
All Prototype Interactions Mapped: YES
Unmapped Prototype Interactions: 0
Production Fake/Mock/Placeholder Interactions: 0
Unresolved Required Backend Capabilities: 0

## Interaction-to-Capability Matrix

| Interaction ID | Prototype Interaction | Classification | Production Integration | Contract / Capability Evidence | Capability Request | E2E Evidence | Status |
|---|---|---|---|---|---|---|---|
| INT-001 | 财务工作台拉取开票申请分页列表 | AVAILABLE | src/main/resources/static/invoice/admin.html | ../../../../src/main/java/com/lanf/controller/admin/AdminOrderController.java | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-002 | 一键复制税号/抬头到剪贴板 | DERIVABLE | src/main/resources/static/invoice/admin.html | finance-invoice-prototype.html | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-003 | 财务弹窗确认开票并录入发票号 | AVAILABLE | src/main/resources/static/invoice/admin.html | ../../../../src/main/java/com/lanf/controller/admin/AdminOrderController.java | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-004 | 财务弹窗驳回开票申请并填写原因 | AVAILABLE | src/main/resources/static/invoice/admin.html | ../../../../src/main/java/com/lanf/controller/admin/AdminOrderController.java | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-005 | 顾客 H5 申请页面查看驳回原因并修改重提 | AVAILABLE | src/main/resources/static/invoice-apply.html | ../../../../src/main/java/com/lanf/controller/PublicInvoiceController.java | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-006 | 状态过滤 Tab 切换与关键字过滤 | DERIVABLE | src/main/resources/static/invoice/admin.html | finance-invoice-prototype.html | N/A | e2e_contract_evidence.json | VERIFIED |
