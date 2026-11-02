# Implementation Design — WI-022

## Root Fix / Owner

在 `PayOfflineCollectController` 的个人码出码边界，将外部协议值 `wechat|alipay` 显式映射为内部稳定渠道码 `offline_wechat_qr|offline_alipay_qr`，再调用统一的 `PaymentCapabilityService.isCashierPaymentMethodEnabled`。

同时修复权威 `PaymentCapabilityMatcher`：`offline_wechat_qr` 映射到 `cashierWechatQrEnabled`，`offline_alipay_qr` 映射到 `cashierAlipayQrEnabled`，并继续叠加 `cashierPayEnabled` 总开关。该根修复同步覆盖个人码出码与结账能力校验。

不修改线上微信开关含义，不把个人码逻辑塞入商户支付服务，也不恢复已废弃的 `offline_collect_*` 双写来源。

## Contract Delta

请求/响应 schema、路径和鉴权不变；仅修正文档与实际意图不一致的开关语义。消费者无需改代码。

## Compatibility

- `channel=wechat|alipay` 对外请求兼容不变。
- 个人码依旧受 `clients.cashier.enabled` 总开关约束。
- 无数据库迁移。

## Verification Strategy

1. 先增加 controller 失败测试，证明个人微信码出码必须查询 `offline_wechat_qr` 而不是线上 `wechat`。
2. 增加关闭个人码时拒绝的边界测试，并覆盖支付宝映射。
3. 做最小生产修复并运行专项测试。
4. 同步 `docs/openapi.yaml` 与 `docs/API.md` 的行为说明。
5. 运行全量测试与 `mvnw.cmd clean package -DskipTests`。
