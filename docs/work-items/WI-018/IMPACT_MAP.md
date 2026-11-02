# Impact Map — WI-018

## Authoritative Owner

- 商户凭据解析：`WechatMerchantKeyStore`。
- Native APIv3 请求与同步响应：`WechatNativeApiClient`。
- 不确定结果状态：`WechatNativePaymentService`。

## Layer Coverage

| Layer | Classification | Evidence / obligation |
|---|---|---|
| UI | NOT_APPLICABLE | 无 UI 修改。 |
| API/consumer | AFFECTED | 字段不变；不可信微信响应继续映射为安全失败。 |
| Backend/payment | AFFECTED | Native 下单、查单、关单响应验签。 |
| Merchant config | AFFECTED | 强制平台公钥已成功加载；沿用同一 DB 记录。 |
| Persistence | UNCHANGED | 无迁移。 |
| External integration | AFFECTED | 微信 APIv3 请求/响应信任边界。 |
| Tests/build | AFFECTED | 客户端单测、支付回归、完整打包。 |

Material UNKNOWN count: 0
