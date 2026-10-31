# Prototype Interaction Capability Contract — WI-074

UI ID: UI-INVOICE-APPLY-001
Approved Prototype: `invoice-apply-prototype.html`
Parent Work Item: WI-074

Capability Mapping Status: COMPLETE
All Prototype Interactions Mapped: YES
Unmapped Prototype Interactions: 0
Production Fake/Mock/Placeholder Interactions: 0
Unresolved Required Backend Capabilities: 0

## Interaction-to-Capability Matrix

| Interaction ID | Prototype Interaction | Classification | Production Integration | Contract / Capability Evidence | Capability Request | E2E Evidence | Status |
|---|---|---|---|---|---|---|---|
| INT-001 | 页面加载携带 token 查询发票与订单信息 | AVAILABLE | src/main/resources/static/invoice-apply.html | ../../../../src/main/java/com/lanf/controller/PublicInvoiceController.java | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-002 | 抬头类型切换（企业/个人单选） | DERIVABLE | src/main/resources/static/invoice-apply.html | ../../../../src/main/resources/static/invoice-apply.html | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-003 | 提交发票抬头、税号及接收方式 | AVAILABLE | src/main/resources/static/invoice-apply.html | ../../../../src/main/java/com/lanf/controller/PublicInvoiceController.java | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-004 | 提交按钮防抖禁用与等待反馈 | DERIVABLE | src/main/resources/static/invoice-apply.html | ../../../../src/main/resources/static/invoice-apply.html | N/A | e2e_contract_evidence.json | VERIFIED |
| INT-005 | 发票文件下载链接安全协议校验 | DERIVABLE | src/main/resources/static/invoice-apply.html | ../../../../src/main/resources/static/invoice-apply.html | N/A | e2e_contract_evidence.json | VERIFIED |
