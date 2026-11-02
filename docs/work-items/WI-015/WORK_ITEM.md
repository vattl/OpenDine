# WORK ITEM — WI-015

## Request

现有后端已经具备小程序微信支付回调，完成收银系统微信支付第一期：客人扫描收银端动态二维码，资金直接进入已配置微信商户号。

## Type

FEATURE

## State

ACCEPTED

## Requirement Contract

### Goal

在现有微信 APIv3、小程序支付回调、退款、支付台账与对账能力之上，提供可供收银端接入的 Native 动态码闭环，并保证回调丢失时可通过主动查单唯一收敛。

### Current behavior

- `WechatJsapiChannel` 已支持小程序 JSAPI 下单、境内退款与退款查单。
- `/order/pay/notify` 已完成微信回调签名验证、AES-GCM 解密和订单支付成功处理。
- 收银端目前只能走人工确认收款码或直接结账，没有微信 Native 动态码创建、查单和关单 API。
- `PaymentOrderNoUtil.buildOutTradeNo` 每次生成不同商户单号，未持久化 Native `code_url`，无法安全复用同一次二维码支付尝试。

### Target behavior

1. 新增持久化 Native 支付尝试，记录门店、业务订单、微信商户单号、金额、二维码、状态、过期时间与微信交易号。
2. `POST /cashier/payment/wechat/native/orders`：从当前登录门店加载未结订单，由服务端计算应付金额并创建或复用有效 Native 二维码。
3. `GET /cashier/payment/wechat/native/orders/{orderNo}`：查询微信权威交易状态；若返回 `SUCCESS`，即使回调丢失也调用与回调相同的幂等入账逻辑。
4. `POST /cashier/payment/wechat/native/orders/{orderNo}/close`：仅关闭未支付尝试；支付已成功时不得误关单并应先收敛本地订单。
5. `/order/pay/notify` 与主动查单共用支付成功应用服务，验证订单、门店商户、商户单号和金额后再把订单置为成功并执行台账/打印/KDS/桌台等既有副作用。
6. 复用现有 `/admin/order/refund`、退款回调/补偿任务、支付台账和 `/admin/reconciliation/**`，不创建第二套退款或对账状态机。

### Must preserve

- 客户端不能提交或覆盖权威支付金额、商户号、AppID 或支付成功状态。
- 只有验签通过的微信回调或签名请求得到的微信查单 `SUCCESS` 可以确认支付。
- 同一成功交易重复回调、重复查单和并发回调/查单只能入账和触发业务副作用一次。
- 订单与 JWT 门店必须一致；不能跨门店创建、查询或关闭二维码。
- 商户私钥、APIv3 密钥、平台公钥和付款正文不得进入响应或明文日志。
- 已有小程序 JSAPI 支付、退款和 KDS 云端权威语义保持不变。

### Acceptance criteria

- [ ] Native 动态码创建接口返回 `codeUrl`、服务端金额、商户单号和过期时间。
- [ ] 有效未支付尝试可幂等复用，过期/关闭尝试可创建新的商户单号。
- [ ] 主动查单可识别 `NOTPAY/USERPAYING/SUCCESS/CLOSED/REFUND/PAYERROR` 等状态，`SUCCESS` 能补偿回调丢失。
- [ ] 关单只作用于未支付尝试；已支付订单不会被关闭或重新收款。
- [ ] 回调与查单成功路径共享幂等入账服务，并校验商户、AppID、商户单号和金额。
- [ ] 已确认支付继续写入 `t_payment_ledger` 并兼容现有微信账单导入对账。
- [ ] 新接口受 `cashier:operate` 权限与当前门店范围保护。
- [ ] `docs/openapi.yaml` 与 `docs/API.md` 同步更新，并提供收银端 API consumer handoff。
- [ ] 专项测试、相关回归和完整 JAR 打包通过。

### Open product questions

- 本 Work Item 仅实现“客人扫收银端”的 Native 支付。收银员扫描客人付款码属于第二期，不在本次范围。
- 收银端生产 UI 在其他仓库；本 Work Item 以明确 API handoff 结束，不修改生产 UI。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [ ] T01 持久化 Native 支付尝试与幂等约束。
- [ ] T02 创建动态码并安全复用有效尝试。
- [ ] T03 查单/关单与回调丢失补偿。
- [ ] T04 抽取并复用幂等支付成功应用服务。
- [ ] T05 权限、契约文档、消费者 handoff 与全量验证。

## Verification Evidence

PENDING

## Review

PENDING

## Acceptance Decision

PENDING

## Consumer Handoffs

`API_CONSUMER_HANDOFF.md`（收银端实现待后续消费）。

## Integration / Release

本 Work Item 目标为仓库内 ACCEPTED/INTEGRATED；不包含部署与生产商户实扣款。

## Related IDs

Workstream: current clean integration worktree; no overlapping payment workstream detected.

## Business Invariants

- Applicable invariant IDs: INV-PAY-001, INV-PAY-002, INV-PAY-003, INV-KDS-001.
- New invariant candidates: NONE.

## Impact Map Authority

- Impact map path: `docs/work-items/WI-015/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-015/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

ACCEPTED
