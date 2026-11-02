# WORK ITEM — WI-018

## Request

完善收银微信 Native 下单业务逻辑，确保沿用既有门店商户 APIv3 凭据，并且仅接受微信签名验证通过的下单、查单和关单响应。

## Type

SECURITY_REPAIR

## State

ACCEPTED

## Requirement Contract

### Goal

Native 调用必须使用与 JSAPI 相同的门店商户号、商户私钥和证书序列号；微信同步响应必须经平台公钥验签及时间戳校验后才能进入业务处理。

### Must preserve

- 商户选择仍按 `shopId + order.merchantId`，默认 `default/1`。
- 金额、订单归属、幂等创建和不确定结果保护保持不变。
- 验签失败、平台公钥缺失或凭据明确不匹配时，不接受 `code_url`、交易状态或关单成功。
- 不记录私钥、签名原文或完整敏感响应。

### Acceptance criteria

- [x] Native 请求继续使用既有 DB 商户配置中的私钥和证书序列号签名。
- [x] 下单、查单、关单均验证 `Wechatpay-Serial/Timestamp/Nonce/Signature`。
- [x] 拒绝错误平台公钥 ID、无效签名、缺失签名头及超过五分钟的响应。
- [x] 平台公钥加载失败时不发送微信请求。
- [x] 专项测试、全量回归、API 文档和 runnable JAR 完成。

## Acceptance Decision

ACCEPTED（仓库内；尚未部署生产或执行真实商户交易）

## Business Invariants

- INV-PAY-001：未经微信权威认证的响应不得改变支付状态。
- INV-PAY-002：商户私钥、证书序列号、商户号和门店配置必须来自同一解析结果。
- INV-PAY-003：验签失败属于不可信/不确定结果，不得重新收款。

## Implementation Ready

- Status: `YES`
- Blockers: NONE
