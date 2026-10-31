# UI Implementation Map — WI-074

UI ID: UI-INVOICE-APPLY-001
Approved Prototype: `invoice-apply-prototype.html`
Measured Spec: `MEASURED_UI_SPEC.md`
Parent Feature / Change: WI-074
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
| Header Banner | `src/main/resources/static/invoice-apply.html` | MODIFY | PRESERVE | 390px 视口，渐变背景 | 修正标语为发票抬头登记服务 |
| Order Summary Card | `src/main/resources/static/invoice-apply.html` | PRESERVE | PRESERVE | 圆角 12px，虚线分割 | 保持订单号与实付金额展示 |
| Privacy Notice | `src/main/resources/static/invoice-apply.html` | ADD | PRESERVE | 蓝色边框背景，盾牌图标 | 提示用户数据脱敏保护 |
| Form Inputs & Submit | `src/main/resources/static/invoice-apply.html` | MODIFY | PRESERVE | 输入框高度 44px，按钮 46px | 增加防抖并在提交时禁用 |
| Submitted Result Card | `src/main/resources/static/invoice-apply.html` | MODIFY | PRESERVE | 绿色成功图标，灰底明细框 | 掩码展示 PII，校验下载链接 |

---

# Token Mapping

| Visual Constraint | Target | Existing Token | Action |
|---|---:|---|---|
| Primary Color | #1aad19 | --primary | REUSE |
| Danger Color | #fa5151 | --danger | REUSE |
| Background Color | #f7f7f7 | --bg | REUSE |
| Card Radius | 12px | --radius | REUSE |
| Input Height | 44px | .form-input height | REUSE |

---

# Business Logic to Preserve

- 顾客扫码打开页面后拉取订单详情
- 支持企业/单位与个人/非企业抬头类型切换
- 邮箱与手机号至少填写一项以接收发票
- 提交成功后切换至已提交回显视图
