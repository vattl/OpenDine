# Impact Map — WI-020

## Authoritative Owners

- 商户生命周期与版本：`PaymentMerchantConfigService`。
- 门店继承策略：新增 merchant policy service/cache。
- 商户路由：新增 `WechatMerchantRoutingService`。
- 凭据解析：`WechatMerchantKeyStore`。
- 交易绑定：订单、Native/MICROPAY attempt 与各微信支付服务。

## Layer Coverage

| Layer | Classification | Evidence / obligation |
|---|---|---|
| UI | NOT_APPLICABLE | 本仓库无生产 UI；只提供 API handoff。 |
| API/consumer | AFFECTED | DELETE 改退役；新增恢复和门店继承策略；响应新增生命周期/版本字段。 |
| Backend/payment | AFFECTED | CRUD、路由、解析、回调、查单、退款链路。 |
| Persistence | AFFECTED | V024：生命周期、历史快照、策略和交易绑定字段。 |
| Security | CRITICAL | 密钥 fail-closed、示例脱敏、跨店与历史版本约束。 |
| External integration | AFFECTED | 微信 JSAPI/NATIVE/MICROPAY/退款继续使用既有协议。 |
| Observability | AFFECTED | 商户选择/版本日志只记录非敏感标识。 |
| Tests/build | AFFECTED | 单元、迁移、支付专项、全量与 JAR。 |

Material UNKNOWN count: 0
