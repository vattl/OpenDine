# UI Lock Manifest — WI-074

## UI ID
UI-INVOICE-APPLY-001

## Status
UI_LOCKED

## Reference Viewport
390×844

## Golden Reference
`docs/work-items/WI-074/ui/invoice-apply-prototype.html`

## Contracts
- Content: “老肥家餐饮 · 电子发票服务” 及真实门店内发票登记说明
- Elements: 订单卡片、安全提示、发票表单（抬头、税号、邮箱、手机）、提交按钮、回显卡片
- Structure/Layout: 垂直卡片流式布局，顶部渐变色条，自适应移动端
- Tokens/Style: 遵循 Design System 移动端规范（主色 #1aad19，圆角 12px/8px）
- Component Map: 严格映射至生产静态资源 `invoice-apply.html`
- Responsive: 390px 基准视口，兼容 360px ~ 480px 移动屏幕
- Fixture: 模拟订单数据与脱敏回显文本

## Accepted Deviations
无视觉偏离；生产代码中采用动态数据渲染与服务端脱敏输出。

## Blocking Compatibility Gaps
无。

## Implementation Notes
生产交付时同步更新 `src/main/resources/static/invoice-apply.html` 与 `src/main/resources/static/invoice/apply.html`。
