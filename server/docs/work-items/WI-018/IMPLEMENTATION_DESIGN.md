# Implementation Design — WI-018

## Root Fix / Owner

由 `WechatNativeApiClient` 统一完成请求签名和响应验签。请求继续使用 `WechatMerchantKeyStore.resolveForPay(...)` 返回的同一份 `mchId/serialNo/privateKey`；响应在解析 JSON 或接受 204 关单结果前，使用同一配置加载的微信平台公钥验证签名。

## Source Basis

- 微信支付官方 `wechatpay-apache-httpclient`：业务请求必须使用标准初始化流程验证应答签名；客户端同时需要商户号、商户证书序列号、商户私钥和微信平台验签材料。https://github.com/wechatpay-apiv3/wechatpay-apache-httpclient
- 当前项目固定 SDK 0.4.9，不支持新版 `withWechatPay(publicKeyId, publicKey)`；因此复用项目已有 `WechatPayV3Crypto.verifyNotifySignature` 实现相同三行应答签名消息验证，避免本 Work Item 引入依赖升级。

## Verification Rules

1. `Wechatpay-Serial` 必须与配置的微信平台公钥 ID 一致。
2. 时间戳、随机串、签名头必须存在，响应时间与服务器相差不得超过五分钟。
3. 使用平台公钥验证 `timestamp + "\\n" + nonce + "\\n" + body + "\\n"`。
4. 平台公钥不可加载、商户证书审计明确不匹配或已过期时，调用前失败。
5. 验签完成后才解析 `code_url` 或交易状态；关单空响应体同样验签。

## Failure Behavior

验证失败抛出 Native API 异常，由既有服务保持 `UNKNOWN` 或返回查单/关单失败，禁止把不可信响应视为成功。

## Verification Strategy

以生成的 RSA 密钥对构造真实签名响应，先证明旧实现接受伪造签名，再实现校验并覆盖成功、错误签名、缺失平台公钥和过期响应。执行完整 Maven 测试、OpenAPI 解析和 JAR 打包。
