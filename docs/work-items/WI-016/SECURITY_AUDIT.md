# Security Audit — WI-016

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Findings

- 付款码仅进入控制器、服务和单次微信请求参数，不存在于实体、迁移、响应或显式日志中。
- HTTP 请求使用 `byte[]` 载荷，Spring DEBUG 日志仅显示对象标识，不输出付款码 XML。
- APIv2 密钥由既有 `PaymentCredentialCipher` 加密；P12 不进入仓库，只保存服务器路径并验证扩展名/存在性。
- XML 解析禁止 DTD、外部实体、外部 DTD/schema；通信成功响应必须 HMAC-SHA256 验签。
- 签名通过后仍校验 appid、mch_id、out_trade_no、金额和交易类型；成功入账按 shop_id 再次隔离。
- 未新增依赖；权限映射和完整性测试覆盖三个端点。
