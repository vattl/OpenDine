# Adaptive UI Contract — WI-075

UI ID: UI-FINANCE-INVOICE-001
Approved Prototype: `finance-invoice-prototype.html`
Parent Work Item: WI-075

Adaptive Contract Status: COMPLETE
Required Device Profiles: 2
Covered Required Profiles: 2
Unmapped Critical Operations: 0
Unresolved Component Variants: 0
Arbitrary Component Size Values: 0

## Device Experience Profiles

| Profile ID | Terminal / Platform | Viewport | Orientation | Input Modality | Usage Context | Support | Density / Navigation | Prototype Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| DESKTOP | PC Web / Cashier Management Console | 1280x800 | Landscape | Mouse/Keyboard | 财务人员白天在收银台PC或财务室电脑集中查看申请、复制税号并在税控机开具发票 | REQUIRED | comfortable table and modal workflow | finance-invoice-prototype.html | READY |
| PHONE | Mobile Web / WeChat H5 | 390x844 | Portrait | Touch | 顾客就餐后扫码填写发票抬头、查看人工开票进度、或查看驳回原因并修改重提 | REQUIRED | compact single-column card flow | finance-invoice-prototype.html | READY |

## Component Family Contract

| Component ID | Family / Role | Variant | Profiles | Visual Size Token | Hit Target | Icon Token | Typography Token | Spacing Token | Adaptation | States | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| BTN-PRIMARY | Button / Primary action | workbench-action | ALL_REQUIRED | control-md | 36px min height | icon-none | font-14-medium | space-12 | responsive button width | default/hover/active/disabled | READY |
| INPUT-SEARCH | Input / Search entry | standard-search | ALL_REQUIRED | control-sm | 32px min height | icon-search | font-13-regular | space-10 | fluid width in toolbar | default/focus | READY |
| TABLE-DATA | Table / Data display | responsive-grid | ALL_REQUIRED | surface-card | 48px row height | icon-none | font-13-regular | space-14 | desktop table, mobile card scroll | default/hover | READY |
| MODAL-CARD | Dialog / Form modal | centered-dialog | ALL_REQUIRED | surface-modal | 520px max width | icon-close | font-15-semibold | space-16 | centered popover with mask | default/open | READY |

## Business Operation Coverage

| Operation ID | Business Operation | Priority | Required Profiles | Entry / Navigation | Primary Action | Completion Feedback | Error / Recovery | Adaptive Pattern | Capability Link | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| OP-FINANCE-001 | 查看待人工开票申请明细与一键复制税号 | CRITICAL | ALL_REQUIRED | 财务工作台列表过滤待开票 Tab | 浏览明细并点击复制税号按钮 | 弹出复制成功轻提示，税号进入剪贴板 | 无税号或数据异常轻提示告知 | desktop table layout | INT-001 | READY |
| OP-FINANCE-002 | 录入税控发票号码并确认开具完成 | CRITICAL | ALL_REQUIRED | 点击操作列【开具发票】唤起弹窗 | 录入发票号码并点击确认 | 状态变更为已开具，指标卡自动累加 | 校验发票号非空，失败友好提示 | centered modal form | INT-003 | READY |
| OP-FINANCE-003 | 驳回不符合开票规范的申请 | HIGH | ALL_REQUIRED | 点击操作列【驳回】唤起弹窗 | 选择驳回原因并提交 | 状态变更为已驳回，同步至顾客端 | 校验驳回说明非空 | centered modal form | INT-004 | READY |
| OP-CUSTOMER-001 | 顾客查看驳回说明并重新修改提交 | HIGH | ALL_REQUIRED | 顾客端 H5 重新进入开票链接 | 查看驳回提示并点击修改按钮重新提交 | 重新进入待开票流程 | 表单必填校验与防抖控制 | mobile single-column card | INT-005 | READY |
