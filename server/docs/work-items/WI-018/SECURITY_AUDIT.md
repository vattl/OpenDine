# Security Audit — WI-018

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Review

- Native 与 JSAPI 共用 `WechatMerchantKeyStore.resolveForPay(shopId, merchantId, null)`，商户号、私钥和商户 API 证书序列号来自同一解析结果。
- 创建、查单和关单均在读取微信业务响应前验证平台公钥 ID、时间窗口及 RSA-SHA256 响应签名。
- 平台公钥缺失、商户证书审计明确异常、签名头缺失、响应过期或验签失败全部 fail closed；不接受二维码、交易状态或关单成功。
- 验签异常由现有服务层映射为不确定结果，不会误判支付失败并触发重复收款。
- 未新增密钥、依赖或敏感日志；测试使用运行时临时 RSA 密钥对。
