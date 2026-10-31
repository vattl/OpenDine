# Impact Map — WI-016

## Authoritative Owner

- 微信 V2 传输与签名：`com.lanf.payment.channel.wechat`。
- 付款码尝试生命周期：新增付款码支付服务与持久化表。
- 成功入账：既有 `WechatPaymentSuccessService`。
- 权威金额：`OrderNetRevenue`，请求不接受金额。

## Change Propagation Path

```text
cashier auth + orderNo + ephemeral authCode
-> shop/order/channel guard
-> durable attempt without authCode
-> signed V2 MICROPAY
-> verified response / V2 query / certificate reverse
-> shared idempotent payment success
-> order + ledger + fulfillment
```

## Layer Coverage

| Layer | Classification | Evidence / obligation |
|---|---|---|
| UI | NOT_APPLICABLE | 本仓库无生产 UI；通过 handoff 交付扫码、轮询和提示契约。 |
| API/consumer | AFFECTED | 三个 cashier 端点及商户配置扩展。 |
| Backend/domain | AFFECTED | MICROPAY 生命周期与共享成功入账。 |
| Persistence | AFFECTED | 凭据字段和付款尝试表迁移。 |
| External integration | AFFECTED | V2 micropay/orderquery/reverse。 |
| Security | AFFECTED | 付款码、APIv2 密钥、P12、XML/签名边界。 |
| Existing JSAPI/Native | AFFECTED | 共享成功服务扩展 MICROPAY，需回归。 |
| KDS/printing/ledger | AFFECTED | 仅通过既有成功处理链路触发。 |
| Tests/build | AFFECTED | 单元、回归、完整 Maven package。 |

Material UNKNOWN count: 0
