# Impact Map — WI-017

## Authoritative Owner

- 并发活动键：`t_wechat_native_payment_attempt.active_key` 唯一约束。
- 创建编排：`WechatNativePaymentService.create`。
- 外部下单：`WechatNativeApiClient`，仅胜出请求可调用。

## Change Propagation Path

```text
concurrent POST requests
-> unique active_key winner
-> loser observes CREATING
-> bounded local DB polling
-> reuse winner ACTIVE codeUrl OR retain 40931 safety response
```

## Layer Coverage

| Layer | Classification | Evidence / obligation |
|---|---|---|
| UI | NOT_APPLICABLE | 本仓库无生产 UI；消费者提示通过 handoff 说明。 |
| API/consumer | AFFECTED | 并发创建的响应语义改善，字段不变。 |
| Backend/domain | AFFECTED | Native 创建冲突分支。 |
| Persistence | UNCHANGED | 继续使用既有唯一活动键；无迁移。 |
| WeChat integration | AFFECTED | 必须证明冲突请求不调用第二次下单。 |
| Security | UNCHANGED | 不新增输入、凭据或敏感输出。 |
| Tests/build | AFFECTED | 专项单测、全量回归、完整 Maven package。 |

Material UNKNOWN count: 0
