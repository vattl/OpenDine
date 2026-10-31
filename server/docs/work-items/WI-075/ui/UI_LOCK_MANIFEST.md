# UI Lock Manifest — WI-075

## UI ID
UI-FINANCE-INVOICE-001

## Status
UI_LOCKED

## Reference Viewport
1280×800 (Desktop Workbench) & 390×844 (Customer Mobile Application)

## Golden Reference
`docs/work-items/WI-075/ui/finance-invoice-prototype.html`

## Contracts
- Content: “老肥家餐饮 · 财务人工开票工作台”及顾客端 H5 申请与驳回回显
- Elements: 顶部导航条、业务模式告示横幅、4 项核心指标统计卡、Tab 状态过滤器、搜索栏、数据表格（带一键复制税号）、开具弹窗、驳回弹窗
- Structure/Layout: 宽屏工作台栅格流式布局与移动端卡片流式布局
- Tokens/Style: 标准财务中后台主色（#1890ff、#52c41a、#faad14、#f5222d），统一圆角与边框规范
- Component Map: 映射至生产静态资源 `src/main/resources/static/invoice/admin.html` 与 `src/main/resources/static/invoice-apply.html`
- Responsive: 1280×800 基准桌面端，支持移动端断点响应式折叠
- Fixture: 模拟开票申请列表数据、状态变更与弹窗表单

## Accepted Deviations
无视觉偏离；生产页面接入真实后台 API 接口。

## Blocking Compatibility Gaps
无。

## Implementation Notes
生产交付时提供 `src/main/resources/static/invoice/admin.html` 并联动更新 `invoice-apply.html`。
