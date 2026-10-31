# UI Implementation Map — WI-075

UI ID: UI-FINANCE-INVOICE-001
Approved Prototype: `finance-invoice-prototype.html`
Measured Spec: `MEASURED_UI_SPEC.md`
Parent Feature / Change: WI-075
Interaction Capability Contract: `PROTOTYPE_INTERACTION_CONTRACT.md`
Backend Coordination Report: `BACKEND_COORDINATION_REPORT.md`

Mapping Status: COMPLETE
All Prototype Regions Mapped: YES
Unmapped Prototype Regions: 0
Legacy Structure Reused Without Approval: NO

---

# Prototype-to-Production Mapping

| Prototype Region | Production File / Component | Operation | Business Logic | Visual Constraints | Notes |
|---|---|---|---|---|---|
| Top Navigation Bar | `src/main/resources/static/invoice/admin.html` | ADD | NEW | 深蓝底色 #001529，高 56px | 包含系统标识与当前操作员信息 |
| Offline Mode Notice | `src/main/resources/static/invoice/admin.html` | ADD | NEW | 蓝底通知横幅 #e6f7ff | 提示线下人工税控开票业务规范 |
| Metrics Stat Grid | `src/main/resources/static/invoice/admin.html` | ADD | NEW | 4 列栅格，彩色边条指示 | 待办待开票、今日已开、填写中、已驳回 |
| Filter Toolbar & Search | `src/main/resources/static/invoice/admin.html` | ADD | NEW | Tab 切换与关键字过滤 | 过滤待开票、已开具等状态 |
| Invoice Data Table | `src/main/resources/static/invoice/admin.html` | ADD | NEW | 响应式表格，支持税号一键复制 | 渲染申请流水、金额、抬头、税号等 |
| Issue Modal Dialog | `src/main/resources/static/invoice/admin.html` | ADD | NEW | 居中弹窗 520px，发票号必填 | 调用 `POST /admin/order/invoice/issue` |
| Reject Modal Dialog | `src/main/resources/static/invoice/admin.html` | ADD | NEW | 居中弹窗 520px，原因说明必填 | 调用 `POST /admin/order/invoice/reject` |
| Customer H5 Status View | `src/main/resources/static/invoice-apply.html` | MODIFY | PRESERVE | 移动端 390px 卡片 | 增加工作日集中开具提示、驳回状态回显 |

---

# Token Mapping

| Visual Constraint | Target | Existing Token | Action |
|---|---:|---|---|
| Primary Brand Color | #1890ff | --primary | REUSE |
| Success Color | #52c41a | --success | REUSE |
| Warning Color | #faad14 | --warning | REUSE |
| Danger Color | #f5222d | --danger | REUSE |
| Card Background | #ffffff | --bg-card | REUSE |
| Page Background | #f0f2f5 | --bg-page | REUSE |
| Border Radius | 8px | --radius | REUSE |

---

# Business Logic to Preserve

- 保证未授权或非管理员无法访问财务开票工作台页面与数据
- 保护顾客税号与联系方式，仅在财务管理端对已认证用户开放一键复制
- 保持已提交订单的防重复开票校验与状态机流转控制
- 顾客端在被驳回时允许重新修改抬头并再次提交
