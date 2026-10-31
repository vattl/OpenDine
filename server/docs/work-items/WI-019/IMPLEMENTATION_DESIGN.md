# Implementation Design — WI-019

## Root Fix / Owner

`WechatNativeApiClient` 将所有异常包装为同一种 `ApiException`，`WechatNativePaymentService.create` 又无差别写入 `UNKNOWN` 并返回 `50331`。因此微信已明确返回的 4xx 拒绝被错误描述为“结果暂不确定”，且真实错误码不可观测。

根修复由 Native API 客户端负责产生结构化失败类别，Native 支付服务只依据该类别执行支付状态转换。

## Source Basis

微信支付官方 Java SDK将失败分为 HTTP/I/O 异常、响应验签失败、非 2xx 服务错误和报文异常；官方建议对非 2xx 获取 `errorCode/errorMessage` 并记录监控，5xx 重试。来源：https://github.com/wechatpay-apiv3/wechatpay-java

## Design

1. `WechatNativeApiClient.ApiException` 增加失败类别与安全诊断字段。
2. 捕获 `HttpStatusCodeException`：4xx 归类 `REJECTED`；5xx 归类 `UNCERTAIN`。仅解析 JSON 中的短 `code/message` 和 `Request-ID`。
3. 网络、超时、签名/时间戳/报文异常统一归类 `UNCERTAIN`。
4. 服务遇到 `REJECTED` 时将尝试写成 `CLOSED/PAYERROR`、释放 `active_key`，返回 `40231`；其余失败保持 `UNKNOWN/50331`。
5. 日志只记录 shop/order/outTradeNo、类别、HTTP 状态、微信错误码和 Request-ID，不记录签名或响应体。

## Verification Strategy

先新增服务回归测试证明当前 4xx 仍错误返回 `50331/UNKNOWN`，再实现分类；补客户端 4xx/5xx 分类测试，执行支付专项、全量测试、OpenAPI 解析和 JAR 打包。
