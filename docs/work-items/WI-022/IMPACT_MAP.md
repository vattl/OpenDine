# Impact Map — WI-022

## Authoritative Owner

`PaymentCapabilityMatcher` 是稳定渠道码到独立配置字段的权威映射；`PaymentCapabilityService.isCashierPaymentMethodEnabled` 是统一能力判定入口；`PayOfflineCollectController.tempQrcode` 是个人收款码出码入口。

## Layer Coverage

| Layer | Impact | Evidence |
|---|---|---|
| API | BEHAVIORAL | 路径和报文不变；修正个人码出码所读取的渠道开关 |
| Controller | DIRECT | `PayOfflineCollectController` 当前把 `wechat/alipay` 误传为线上渠道 |
| Capability matcher | DIRECT | 个人码曾错误读取线上 `cashier_wechat/alipay_enabled`，现读取独立 QR 字段 |
| Capability service | REUSED | `isCashierPaymentMethodEnabled` 统一解析稳定渠道码并包含总开关 |
| Persistence | REVIEWED | 独立列 `cashier_wechat_qr_enabled` / `cashier_alipay_qr_enabled` 已存在，无迁移 |
| Merchant payment | REVIEWED | Native/付款码服务不经过个人码 controller |
| Tests | DIRECT | controller 回归测试 + capability 既有测试 + 全量 Maven |
| UI | NONE | 服务端修复，无界面结构或交互改动 |

## Consumers

- 收银端继续提交 `channel=wechat|alipay`，无需适配。
- 管理端继续通过 `clients.cashier.channelStates.wechat_qr/alipay_qr.enabled` 配置独立开关。

## Unknowns

NONE
