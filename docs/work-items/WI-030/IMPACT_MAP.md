# Impact Map — WI-030

## Authoritative Owner

- 商户选择：`WechatMerchantRoutingService`。
- 商户配置与历史凭据：`PaymentMerchantConfigService` / `WechatMerchantKeyStore`。
- 支付成功入账：`WechatPaymentNotifyHandler` / `WechatPaymentSuccessService`。
- 退款申请与入账：`WechatJsapiChannel` / `PaymentRefundLedger` / `WechatRefundSettlementService`。
- 订单身份：`t_order.order_no` 与支付尝试表的 `out_trade_no`。

## Change Propagation Path

```text
订单门店/金额/就餐方式
→ 服务端商户路由
→ 当前数据库商户配置
→ 支付尝试固化配置 ID/版本
→ 微信签名请求
→ 签名回调 + 精确密钥候选
→ 支付/退款绑定校验
→ 权威流水 + 订单状态
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 微信小程序 | JSAPI 请求消费者 | VERIFIED_UNAFFECTED | No | 请求/成功响应字段不变；`merchantId` 不作为权威输入 |
| 收银端 | Native/MICROPAY 消费者 | VERIFIED_UNAFFECTED | No | 路径与响应结构不变 |
| 管理端 | 商户配置消费者 | VERIFIED_UNAFFECTED | No | CRUD 合同不变；配置生效一致性增强 |
| 微信支付平台 | 支付/退款回调提供方 | AFFECTED | No | 服务端增强验证，协议字段来自微信标准回调 |
| 财务对账 | 流水和退款消费者 | AFFECTED | No | 未登记/不一致退款进入异常而非自动入账 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 本仓库不含生产 UI，接口形状不变 |
| Interaction | VERIFIED_UNAFFECTED | 支付交互入口不变 |
| Frontend State | VERIFIED_UNAFFECTED | 无新增必填响应字段 |
| API Client | VERIFIED_UNAFFECTED | 微信请求协议不变 |
| Request Contract | AFFECTED | `merchantId` 保留但不再决定新支付路由；退款回调验证收紧 |
| Backend/Domain | AFFECTED | 路由、配置解析、支付成功、退款结算 |
| Persistence | AFFECTED | 新迁移：订单唯一约束、回调索引、退款商户绑定字段 |
| Response Contract | VERIFIED_UNAFFECTED | 成功响应结构不变，异常回调继续返回 FAIL |
| Jobs/Events/Integrations | AFFECTED | 退款补偿继续按固化商户查询；微信回调精确路由 |
| Config/Security | AFFECTED | 跨店绑定、商户身份、缓存一致性 |
| Runtime/NFR | AFFECTED | 回调由全表扫描改为索引查询；支付配置读取以 DB 为权威 |
| Tests | AFFECTED | 新增跨店、商户不匹配、退款未知单、缓存漂移、唯一性覆盖 |

## Duplicate Logic / Patch Smells

- 支付回调与退款回调分别实现资源解密，需保留共同的“解密成功商户身份”。
- `OrderController` 中退款回调仍承担过多领域判断，本次把权威校验下沉到退款服务/台账。
- 部分历史兼容路径仍只按 `order_no` 查询；本次通过全局唯一约束保证其确定性，新增代码优先使用 `shop_id + order_no`。

## Contract Delta Summary

兼容性收紧：客户端传入的 `merchantId` 不再决定新支付资金路由；微信退款回调只有对应本系统已登记退款申请时才自动入账。接口路径、字段类型和成功响应均不变。

## UI Semantic Impact

NONE。

## Risks

- 生产库若已有重复 `order_no`，唯一索引迁移会失败并阻止启动，必须先清理重复数据；这是防止静默错账的预期 fail-closed 行为。
- 退款历史待处理记录缺少新绑定字段时需由迁移从订单/商户配置回填；无法回填的记录不得自动入账。
- 每次新支付精确读取商户配置会增加少量数据库查询，使用已有复合唯一键控制成本。
