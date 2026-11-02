# Adaptive UI Contract — WI-074

UI ID: UI-INVOICE-APPLY-001
Approved Prototype: `invoice-apply-prototype.html`
Parent Work Item: WI-074

Adaptive Contract Status: COMPLETE
Required Device Profiles: 1
Covered Required Profiles: 1
Unmapped Critical Operations: 0
Unresolved Component Variants: 0
Arbitrary Component Size Values: 0

## Device Experience Profiles

| Profile ID | Terminal / Platform | Viewport | Orientation | Input Modality | Usage Context | Support | Density / Navigation | Prototype Evidence | Status |
|---|---|---|---|---|---|---|---|---|---|
| PHONE | Mobile Web / WeChat H5 | 390x844 | Portrait | Touch | 顾客就餐后扫描结账小票开票二维码进行发票抬头登记与申请 | REQUIRED | compact single-column card flow | invoice-apply-prototype.html | READY |

## Component Family Contract

| Component ID | Family / Role | Variant | Profiles | Visual Size Token | Hit Target | Icon Token | Typography Token | Spacing Token | Adaptation | States | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|
| BTN-PRIMARY | Button / Primary action | touch-prominent | ALL_REQUIRED | control-lg | 46px min height | icon-none | font-16-bold | space-16 | full-width container action | default/active/disabled/loading | READY |
| INPUT-TEXT | Input / Text entry | standard-input | ALL_REQUIRED | control-md | 44px min height | icon-none | font-15-regular | space-12 | fluid-width with border | default/focus/error | READY |
| CARD-CONTAINER | Surface / Card grouping | elevated-card | ALL_REQUIRED | surface-card | fluid width max 480px | icon-none | font-14-medium | space-16 | center aligned card layout | default | READY |
| TAG-BADGE | Badge / Status indicator | pill-badge | ALL_REQUIRED | badge-sm | 24px height | icon-none | font-12-medium | space-8 | rounded inline block | default | READY |

## Business Operation Coverage

| Operation ID | Business Operation | Priority | Required Profiles | Entry / Navigation | Primary Action | Completion Feedback | Error / Recovery | Adaptive Pattern | Capability Link | Status |
|---|---|---|---|---|---|---|---|---|---|---|
| OP-INVOICE-001 | 扫描小票二维码查看订单可开票状态 | CRITICAL | ALL_REQUIRED | 微信扫一扫 URL 打开页面 | 自动拉取已鉴权订单与发票详情 | 卡片展示订单号与可开票金额 | 友好错误横幅并提供重新连接按钮 | mobile single-column card | INT-001 | READY |
| OP-INVOICE-002 | 填写并提交发票企业或个人抬头 | CRITICAL | ALL_REQUIRED | 表单卡片输入并点按提交按钮 | 校验输入并提交至后台发票登记服务 | 视图平滑切换至已提交成功卡片并掩码回显 | 校验不通过高亮报错，防抖锁定防重 | mobile touch-friendly form | INT-003 | READY |
