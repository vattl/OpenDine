# Layer Impact Matrix — WI-030

| Layer | Status | Planned Evidence |
|---|---|---|
| Client/UI | VERIFIED_UNAFFECTED | API 形状不变，无 UI 代码 |
| API contract | AFFECTED | OpenAPI/API 行为说明 |
| Payment routing | AFFECTED | 路由专项测试 |
| Merchant credentials | AFFECTED | DB 权威读取与门店绑定测试 |
| Payment callback | AFFECTED | 商户/AppID/门店测试 |
| Refund callback | AFFECTED | 登记、金额、交易号、商户测试 |
| Persistence | AFFECTED | V033 migration review |
| Runtime/reliability | AFFECTED | 多实例陈旧缓存场景与索引检查 |
| Security | AFFECTED | SECURITY_AUDIT.md |
| Packaging | AFFECTED | runnable JAR build |

Material UNKNOWN count: 0
