# WORK ITEM — WI-024

## Request

依据小程序微信支付超收审计，修复并完善订单金额变更、JSAPI 预支付、支付回调和异常交易补偿之间的结算严谨性与准确性。

## Type

REPAIR

## State

IMPLEMENTATION_READY

## Requirement Contract

### Goal

同一业务订单任一时刻最多存在一笔可支付的微信 JSAPI 交易；退菜、改价、优惠、改数量和加菜等金额变更必须先安全终止旧交易。支付成功只能按持久化支付尝试的精确金额、商户、门店、用户和交易号入账，任何重复或冲突交易都不得静默吞掉。

### Current behavior

- JSAPI 下单只返回 `prepay_id/payParams`，不持久化 `out_trade_no`、金额、商户版本或状态。
- 订单金额改变后旧 `prepay_id` 仍可被客户端使用。
- 支付下单和金额变更未统一锁定订单，旧对象可能覆盖新金额。
- JSAPI 回调没有精确的期望金额记录；重复交易在订单已支付后可能被当作幂等成功。
- 现有测试未覆盖“预支付后退菜/改价”和同单多笔微信交易。

### Target behavior

- 建立 JSAPI 支付尝试账本，记录订单、门店、`out_trade_no`、服务端金额、openid、商户配置版本、有效期和状态。
- 数据库唯一活动键保证同一门店同一订单最多一笔 CREATING/ACTIVE/UNKNOWN 尝试。
- 同金额重复请求复用有效 `prepay_id`；金额变化必须查单并关闭旧 NOTPAY 交易，状态不确定时禁止继续改价或创建新支付。
- 所有影响应付金额的服务端操作统一经过金额变更保护；支付已成功时金额变更失败并提示改走支付后退款。
- 回调按支付尝试精确核对金额、门店、商户、openid 和 `out_trade_no`；不同微信交易不得借“订单已支付”静默成功。
- `t_payment_ledger` 是权威资金事实；成功回调与收银手工结账都必须先写/校验流水再更新订单，且不同成功资金事实不得互相覆盖。
- 兼容部署前短时在途 JSAPI 单，但只允许回调金额等于当前服务端净应付。

### Must preserve

- 微信签名、回调解密和商户历史凭据绑定不降级。
- 金额始终由服务端计算，客户端不能提供权威金额或商户。
- Native、付款码、余额、现金、挂账和现有退款链路不改变。
- 退菜/改价失败必须整体回滚库存、明细、桌台金额和订单金额。
- 不把异常超收误记为菜品退款，不污染订单销售额和 `refund_amount`。

### Acceptance criteria

- [x] JSAPI 尝试表、唯一活动键和商户版本绑定完成。
- [x] `/order/getPrepayId` 在订单行锁内按服务端金额创建或复用支付尝试。
- [x] 退菜、数量、改单价、优惠和加菜前能关闭旧未支付交易；未知或已支付状态 fail closed。
- [x] 支付回调必须精确匹配尝试；旧单金额不一致、重复交易、跨门店/用户/商户不入账。
- [x] 部署前在途单只在金额精确一致时兼容入账。
- [x] API 文档、迁移、专项测试、全量测试和 JAR 构建通过。
- [x] 权威支付流水先于订单结清落库；流水失败回滚订单，手工结账不能覆盖回调资金事实。

### Open product questions

NONE。采用资金安全默认：状态不确定时阻断金额变更和新支付；微信已支付时保留原订单金额并要求走支付后退款。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 RED：复现旧预支付退菜、并发金额覆盖、重复支付和回调错配。
- [x] T02 数据迁移与 JSAPI 支付尝试生命周期。
- [x] T03 金额变更保护接入退菜、改数量、改价、优惠和加菜。
- [x] T04 回调精确匹配、兼容迁移和异常可观测性。
- [x] T05 API 文档、专项/全量回归、JAR 与验收证据。

## Verification Evidence

`TEST_REPORT.md`：专项 85 项与全量 1348 项测试通过，OpenAPI 解析、格式检查及 JAR 构建通过。

## Review

`REVIEW_REPORT.md`：PASS；无 HIGH/CRITICAL 开放问题。

## Acceptance Decision

`ACCEPTANCE_REPORT.md`：ACCEPTED（仅服务端能力，尚未部署）。

## Consumer Handoffs

`API_CONSUMER_HANDOFF.md`。现有成功响应保持兼容；消费者需处理新增安全冲突码并刷新订单金额。

## Integration / Release

Branch only；未部署、不代表 RELEASED。

## Related IDs

Workstream: jsapi-settlement-integrity
Capability: payment-settlement
Commits:

## Business Invariants

- INV-PAY-001：同店同业务订单任一时刻最多一笔可支付 JSAPI 尝试。
- INV-PAY-002：微信下单金额必须等于创建尝试时服务端净应付金额，回调必须精确相等。
- INV-PAY-003：任何订单金额变更提交前，旧微信尝试必须进入不可支付终态；未知状态阻断变更。
- INV-PAY-004：微信 SUCCESS 与金额变更竞争时只能有一个业务结果获胜；支付获胜后只能走退款。
- INV-PAY-005：不同 `out_trade_no/transaction_id` 的第二笔支付不是幂等回调，必须作为冲突交易处理。
- INV-PAY-006：支付尝试必须绑定原门店、openid 和商户凭据版本，后续查单/关单/回调不得漂移。
- INV-PAY-007：异常超收冲正与菜品退款是不同财务语义，不得混写 `refund_amount`。
- INV-PAY-008：`t_payment_ledger` 是权威资金事实；任何订单结清必须在同一事务中先成功写入/精确校验对应流水，不同成功流水禁止覆盖。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-024/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-024/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

ACCEPTED
