# Security Audit — WI-024

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Threat Model

- 客户端金额篡改：预支付金额始终取服务端订单净应付，客户端 `totalAmount` 被忽略。
- 陈旧二维码/预支付参数重复收款：金额变更前锁定订单并查询、关闭旧 JSAPI 交易；查单或关单不确定时 fail closed。
- 支付与退菜并发：订单行锁串行化回调、预支付创建和金额变更；微信已支付或关单失败时本地金额变更回滚。
- 回调伪造与串单：沿用 API v3 验签，并精确校验商户、AppID、门店、交易类型、金额、openid 和 out_trade_no。
- 重复支付覆盖：已支付订单仅允许相同 transaction_id 幂等；第二个交易明确拒绝，不覆盖首笔交易号。
- 收银覆盖真实支付：微信回调使用 `transaction_id` 派生请求号并先写权威流水；手工结账会核对订单已有成功流水的请求号、渠道、金额和第三方交易号，不一致即拒绝。
- 商户密钥漂移：尝试记录商户配置 ID/版本，后续签名、查单和关单使用创建时的历史绑定。
- 未知外部状态：超时或非权威状态保持活动占位，禁止创建第二笔可支付交易。
- 敏感信息：变更未记录私钥、APIv3 密钥、证书内容或完整支付参数；日志限定订单、门店、商户单号和请求标识。

## Residual Risk

生产发布前仍需在真实 MySQL 上演练并执行 V026，且需要微信沙箱/真实商户端到端验证。外部小程序和收银消费者必须完成 handoff，丢弃缓存的 `payParams` 并处理支付冲突。
