# WORK ITEM — WI-030

## Request

依据多门店多商户订单支付审计，完成商户路由权威化、跨实例配置一致性、支付/退款回调商户绑定、订单号唯一性及回调性能优化。

## Type

REPAIR

## State

ACCEPTED

## Requirement Contract

### Goal

多门店、多商户场景下，每笔支付和退款都只能归属订单门店在创建交易时选定的商户配置；配置停用或轮换在多实例中及时生效；回调不能通过模糊订单号或未登记退款单跨店入账。

### Current behavior

- 无路由规则时会回退订单中由客户端可传入的 `merchantId`。
- 商户运行时解析依赖无 TTL 的 JVM 本地缓存。
- 退款回调未以已登记退款申请为唯一入口，也未严格校验回调商户与申请金额。
- `t_order.order_no` 仅有普通索引；部分回调/退款按订单号全局查询。
- 回调按平台公钥序列号匹配时扫描所有当前与历史商户配置。

### Target behavior

- 新支付的商户由服务端门店路由策略决定，无匹配规则时固定使用 `default`。
- 每次创建支付都读取数据库当前商户状态；跨节点不会永久使用已停用或旧版本配置。
- 固化商户凭据解析必须校验订单门店；支付成功回调强制校验 `mchid/appid`。
- 退款成功回调必须命中既有退款申请并校验门店、订单、金额、交易号、商户号和固化配置。
- 订单号由数据库保证全局唯一；回调凭据按平台公钥序列号索引查询。

### Must preserve

- JSAPI、Native、MICROPAY 现有 API 路径与成功响应结构不变。
- 旧订单 `merchantId=1/2` 仍可用于历史交易兼容；已创建交易继续按固化配置版本查单、关单、撤销和退款。
- 全局商户模板只有门店策略明确允许时才能用于新支付。
- 回调仍保持幂等，资金流水优先于订单成功状态写入。
- 不改动当前工作区中与套餐、优惠券和退菜有关的用户未提交修改。

### Acceptance criteria

- [x] 客户端 `merchantId` 不能改变新支付的收款商户。
- [x] 多实例下商户停用/轮换不会因本地缓存而永久漂移。
- [x] 支付回调拒绝缺失或不匹配的 `mchid/appid`，并校验固化配置门店。
- [x] 退款回调拒绝未知退款单、金额不符、交易号不符、商户号不符和跨店绑定。
- [x] 数据库保证 `order_no` 唯一，并为回调商户序列号建立选择性索引。
- [x] 支付专项测试、迁移检查、OpenAPI/API 文档同步及 runnable JAR 均通过；全量测试仅剩 Impact Map 外的 KDS 基线失败，详见 `TEST_REPORT.md`。

### Open product questions

无。退款若由微信商户平台人工发起而非本系统登记，按异常对账处理，不直接自动回写订单。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 服务端权威商户路由与实时配置解析。
- [x] T02 支付回调门店/商户强校验。
- [x] T03 退款申请绑定与严格回调入账。
- [x] T04 数据库唯一约束和回调索引。
- [x] T05 合同文档、全量验证、安全复核和打包。

## Verification Evidence

见 `TEST_REPORT.md`、`SECURITY_AUDIT.md`、`REVIEW_REPORT.md`、`ACCEPTANCE_REPORT.md` 和 `COMPLETION_EVIDENCE.md`。

## Review

PASS FOR PAYMENT SCOPE

## Acceptance Decision

ACCEPTED；whole-worktree INTEGRATED 尚未确认，RELEASED=NO。

## Consumer Handoffs

现有请求字段保持兼容；`merchantId` 降级为非权威兼容字段，消费者无需同步发布。

## Integration / Release

本 Work Item 仅覆盖仓库实现与可部署 JAR，不包含生产部署。

## Related IDs

Workstream: WI-030
Capability: payment-multi-store-multi-merchant
Commits: PENDING

## Business Invariants

- INV-PAY-030-01：新交易商户只能由订单门店的服务端策略决定。
- INV-PAY-030-02：交易绑定的商户配置 ID/版本必须属于订单门店或经授权继承的全局模板。
- INV-PAY-030-03：支付回调必须同时匹配支付尝试、门店、金额、商户号和 AppID。
- INV-PAY-030-04：退款回调必须匹配已登记退款申请及其金额、交易号和商户。
- INV-PAY-030-05：订单号不得在数据库中重复。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-030/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-030/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`（非 INTEGRATED、非 RELEASED）
