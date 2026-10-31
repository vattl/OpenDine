# Implementation Design — WI-024

## Root Fix / Owner

新增 `WechatJsapiPaymentService` 作为 JSAPI 支付尝试和金额变更互斥的业务权威。控制器不自行推断微信状态；低层客户端只负责签名、下单、查单和关单。

## State model

- `CREATING`：请求已占用活动键，微信结果尚未落库。
- `ACTIVE/NOTPAY`：可复用的未支付交易。
- `UNKNOWN`：网络或响应校验不确定；继续占用活动键，必须查单收敛。
- `SUCCESS`：微信已支付，释放活动键但保留历史。
- `CLOSED/PAYERROR`：不可支付终态，释放活动键。
- `CONFLICT`：回调与本地业务不变量冲突，持久化证据并阻止静默入账。

## Create prepay

1. 校验用户归属、订单状态、并台状态和支付能力。
2. `SELECT ... FOR UPDATE` 锁订单。
3. 在锁内重新计算并持久化优惠/应付金额。
4. 若有活动尝试：同金额同用户且有效则复用；UNKNOWN/CREATING 先查单；金额或身份变化时查询后关闭 NOTPAY。
5. 创建带唯一活动键的 CREATING 尝试，绑定商户配置版本。
6. 调微信 JSAPI 下单；明确拒绝释放活动键，不确定结果保持 UNKNOWN。

## Amount mutation guard

所有已识别的应付金额变更入口在首个业务写入前锁订单并调用 guard：

- 无活动尝试：允许。
- NOTPAY：关单成功后允许。
- CLOSED/PAYERROR：本地收敛后允许。
- SUCCESS：拒绝变更，要求刷新并走支付后退款。
- UNKNOWN/查询失败：拒绝变更，避免旧金额继续可付。

## Callback

- 优先按 `out_trade_no` 找 JSAPI/Native 尝试。
- JSAPI 尝试必须校验 exact amount、shop、merchant binding、openid 和交易类型。
- 已支付订单仅在 transaction_id 与同一尝试一致时视为回调幂等；不同交易返回冲突并保留尝试证据。
- 无 JSAPI 尝试仅作为部署前兼容：金额必须精确等于当前 `OrderNetRevenue`，不再接受“小于原价即自动变优惠”。

## Compatibility

- `/order/getPrepayId` 路径和 `prepay_id/payParams` 保持。
- 可新增 `paymentAttemptId/outTradeNo/amountFen/expiresAt/reused` 字段。
- 新冲突错误为兼容性收紧；消费者应刷新订单，不能复用旧 payParams。

## Official source basis

- JSAPI/小程序下单与 `out_trade_no` 唯一、金额分单位：<https://pay.wechatpay.cn/doc/v3/merchant/4012791856>
- JSAPI 生命周期、过期和防重复支付：<https://pay.wechatpay.cn/doc/v3/merchant/4012791870>
- 无需继续支付时关闭订单：<https://pay.wechatpay.cn/doc/v3/merchant/4012791860>

## Vertical slices

1. RED tests for attempt uniqueness, old amount invalidation and exact callback matching.
2. Migration/entity/mapper plus create/reuse/query/close lifecycle.
3. Mutation guard integration.
4. Callback convergence and legacy compatibility.
5. Documentation, security/review, full regression and package.

## Verification Strategy

1. RED tests prove legacy JSAPI callback cannot reinterpret a smaller payment as an implicit discount and a different transaction cannot be treated as an idempotent callback.
2. Attempt-service tests cover same-attempt reuse, amount-change close-and-recreate, uncertain-state fail-closed behavior and historical merchant binding.
3. Mutation tests cover refund, quantity, price, discount and add-dish entry points against NOTPAY, UNKNOWN and SUCCESS attempts.
4. Callback tests cover exact amount, shop, merchant, payer and transaction identity plus native-payment regression.
5. Run focused tests, full Maven tests, API contract validation, migration/schema review, secret scan and `mvnw.cmd clean package -DskipTests`.
