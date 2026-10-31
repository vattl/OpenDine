# Impact Map — WI-019

## Authoritative Owner

- 微信 HTTP/验签异常分类：`WechatNativeApiClient`。
- 本地支付尝试状态与 API 返回：`WechatNativePaymentService`。

## Layer Coverage

| Layer | Classification | Evidence / obligation |
|---|---|---|
| UI | NOT_APPLICABLE | 无 UI 修改。 |
| API/consumer | AFFECTED | 新增明确拒绝业务码 `40231` 及可选诊断字段。 |
| Backend/payment | AFFECTED | 区分微信 4xx、5xx、网络与验签异常。 |
| Persistence | BEHAVIORAL | 4xx 尝试写为 `CLOSED/PAYERROR` 并清空 `active_key`；无迁移。 |
| External integration | AFFECTED | 微信 APIv3 失败语义。 |
| Observability | AFFECTED | 增加安全化失败分类日志。 |
| Tests/build | AFFECTED | 客户端、服务、全量测试和 JAR。 |

Material UNKNOWN count: 0
