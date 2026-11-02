# Impact Map — WI-075

## Audit Routing Inputs

Risk Level: MEDIUM
UI Impact: STRUCTURAL
Contract Impact: BOTH
Security Impact: YES
Data / Migration Impact: NO
Reliability / Performance Impact: YES

## Authoritative Owner

- `OrderInvoiceServiceImpl`: 开票申请分页查询、状态机管理（支持 REJECTED、SUCCESS 流转）、权限及数据安全主管服务。
- `AdminOrderController`: 管理端开票申请列表查询（`GET /admin/order/invoice/list`）、开票确认（`POST /admin/order/invoice/issue`）及驳回（`POST /admin/order/invoice/reject`）接口控制器。
- `PublicInvoiceController`: 顾客端发票申请查询与修改重提接口控制器。
- `src/main/resources/static/invoice/admin.html`: 财务开票管理工作台前端静态页面。
- `src/main/resources/static/invoice-apply.html`: 顾客端发票申请 H5 页面。

## Change Propagation Path

```text
Admin / Finance Request
→ AdminOrderController (权限校验 order:view / order:operate，参数校验)
→ OrderInvoiceServiceImpl (分页过滤 / 状态流转 / 驳回理由记录 / 确认开具)
→ t_order_invoice (读取明细 / 更新 invoice_status, fapiao_number, error_msg, operator_id)
→ admin.html (工作台数据渲染 / 一键复制 / 弹窗表单交互)
→ invoice-apply.html (顾客端提示时效 / 驳回原因展示 / 允许修改重新提交)
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 财务人员 / 管理端 | 集中查看待开票申请、复制税号、确认开具、驳回异常单 | AFFECTED | YES | `AdminOrderController`, `admin.html` |
| 顾客端 H5 | 提交发票抬头、查看人工处理进度提示、查看驳回原因并修改 | AFFECTED | YES | `PublicInvoiceController`, `invoice-apply.html` |
| 数据库持久化 | 记录发票开具结果及驳回原因 | AFFECTED | NO (已具备所需字段) | `t_order_invoice` |
| 接口文档 | 同步新增与修改的财务管理接口 | AFFECTED | YES | `docs/openapi.yaml`, `docs/API.md` |

## Layer Coverage

| Layer | State | Owner / Impact |
|---|---|---|
| Controller / API | MODIFIED | `AdminOrderController`, `PublicInvoiceController` |
| Domain / Service | MODIFIED | `IOrderInvoiceService`, `OrderInvoiceServiceImpl`, `OrderInvoice` |
| Persistence / DB | PRESERVED | `t_order_invoice`（已有字段完全覆盖） |
| Frontend / UI | MODIFIED | 新增 `invoice/admin.html`，增强 `invoice-apply.html` |
| Documentation | MODIFIED | 同步更新 `docs/openapi.yaml`, `docs/API.md` |
