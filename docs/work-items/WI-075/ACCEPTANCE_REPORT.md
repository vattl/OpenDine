# Acceptance Report — WI-075

Decision: ACCEPTED

## 1. 验收综述
- **状态**: ACCEPTED
- **简述**: 针对个人/普通商户无法直连税控 API 开具在线发票的业务场景，成功交付了财务后台人工开票工作台（`invoice/admin.html`）与全链路业务支撑。实现开票申请分页查询与指标统计（`GET /admin/order/invoice/list`）、申请驳回与原因记录（`POST /admin/order/invoice/reject`）、线下税控机选填链接开具（`POST /admin/order/invoice/issue`）、以及顾客端 H5 申请页的工作日人工开票提示与驳回重提闭环。全套自动化测试 24 项 100% 通过，UI 子门禁（保真度、能力契约、自适应）全部 PASS，OpenAPI 与 API.md 同步完成，Maven 打包成功。

## 2. 验收清单核对 (Acceptance Criteria)

| 准则 ID | 状态 | 验证说明 |
|---|---|---|
| AC-01: 财务开票申请分页列表接口 | PASS | `GET /admin/order/invoice/list` 正常支持状态过滤、关键词检索、多租户门店隔离及待办计数统计，`AdminOrderAuditAndInvoiceApiTest#listInvoices_success` 验证通过 |
| AC-02: 确认开具与驳回处理 | PASS | `POST /admin/order/invoice/issue` 兼容离线税控开具；`POST /admin/order/invoice/reject` 成功流转为 `REJECTED` 并记录原因，禁止逆向驳回已开具发票，`OrderInvoiceServiceTest` 与 Controller 测试均通过 |
| AC-03: 财务人工开票工作台界面 | PASS | 交付静态工作台 `src/main/resources/static/invoice/admin.html`，提供指标卡、申请列表、一键复制税号/抬头、确认开具弹窗与驳回弹窗，UI 保真度及自适应门禁均 PASS |
| AC-04: 顾客端 H5 申请页联动 | PASS | `invoice-apply.html` 增加工作日人工处理时效提示；在被驳回时回显驳回说明并支持重新解锁表单提交，重置为 `TITLE_SUBMITTED` |
| AC-05: 核心业务不变量保持 | PASS | 未支付订单禁止开票，已开票总额不超实付金额，普通商户不调用第三方服务商税控接口，权限严格受控 |
| AC-06: 规范文档与构建验证 | PASS | 同步更新 `docs/openapi.yaml` 与 `docs/API.md`，全套 24 项测试通过，Maven 打包生成可运行 JAR 产物 |
