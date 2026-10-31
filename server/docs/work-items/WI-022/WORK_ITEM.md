# WORK ITEM — WI-022

## Request

修复收银端支付渠道开关串线：关闭“微信支付（微信商户收款）”后，只要“微信收款码（个人收款码）”仍开启，结账时必须仍可生成个人微信收款码。

## Type

BUG

## State

ACCEPTED

## Requirement Contract

### Goal

让微信商户支付与微信个人收款码使用各自独立的渠道开关，任何一方关闭都不应误伤另一方。

### Current behavior

`POST /pay/offline-collect/temp-qrcode` 把请求中的 `channel=wechat` 交给 `isCashierConfiguredChannelEnabled`，该方法把 `wechat` 解释为线上 `cashier_wechat_enabled`，导致关闭微信商户支付后个人收款码也被错误拒绝。

### Target behavior

- 微信个人收款码只校验 `offline_wechat_qr` / `cashier_wechat_qr_enabled`。
- 支付宝个人收款码只校验 `offline_alipay_qr` / `cashier_alipay_qr_enabled`。
- 微信商户支付继续独立校验 `online_wechat` / `cashier_wechat_enabled`。
- 收银端总支付开关关闭时，两类收银渠道仍统一不可用。

### Must preserve

- 个人码 payload、订单归属、会话、金额和收款意图校验保持不变。
- API 路径、请求体字段、成功响应结构与权限不变。
- 微信 Native/付款码商户支付流程不读取个人收款码开关。

### Acceptance criteria

- [x] 线上微信关闭、微信个人码开启时，可成功生成微信个人收款码。
- [x] 线上微信开启、微信个人码关闭时，生成个人码仍明确提示未启用。
- [x] 支付宝个人码遵循相同独立开关语义。
- [x] 专项测试、全量测试及 JAR 打包通过。

## Business Invariants

- INV-PAY-CH-001：`online_wechat` 与 `offline_wechat_qr` 是两个独立支付渠道。
- INV-PAY-CH-002：个人收款码出码必须由对应个人码开关授权，不能借用线上商户渠道开关。
- INV-PAY-CH-003：门店/收银端总开关仍是所有收银支付渠道的上级闸门。

## Acceptance Decision

ACCEPTED

仓库修复、文档同步、自动化验证与 JAR 构建完成；尚未部署生产，不表示 RELEASED。

## Implementation Ready

- Status: `YES`
- Blockers: NONE
