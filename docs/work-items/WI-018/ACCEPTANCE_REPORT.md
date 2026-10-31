# Acceptance Report — WI-018

Decision: ACCEPTED

## Acceptance Evidence

- 请求签名继续使用门店已有商户号、私钥和商户 API 证书序列号。
- 创建二维码、主动查单和关单的微信同步响应均在业务处理前完成签名验证。
- 错误平台公钥 ID、签名伪造、签名头缺失、过期响应及平台公钥缺失均有回归覆盖。
- 不可信响应沿用现有不确定状态语义，不改变支付成功或关单状态。
- API 文档、OpenAPI、专项测试、全量回归和 runnable JAR 打包全部完成。

## Scope

仓库内修复已接受；未部署到 `www.laofei.com.cn`，未执行真实微信商户交易验证。
