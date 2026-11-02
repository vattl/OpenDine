# WORK ITEM — WI-036

## Request
基于门店多商户场景，规划并代码落地“商户可编辑路由规则模块”。老板可在后台多条件配置订单分流规则（如打包自提走小额商户、金额50~100元走小额商户、包含三文鱼产品走专用商户等），支持试算与平滑降级。

## Type
FEATURE / REPAIR

## State
ACCEPTED

## Requirement Contract
### Goal
餐饮门店后台可灵活多条件定义微信/支付宝商户分流规则；前台点餐与收银结账依据菜品明细、就餐方式、实付金额与时段自动分流；商户异常时自动保底降级，确保支付永不中断。

### Implementation Summary
- 数据库表: `t_payment_routing_rule` (Flyway `V035__payment_routing_rules.sql`)
- 规则实体与映射: `PaymentRoutingRuleEntity`, `PaymentRoutingRuleMapper`
- 规则匹配引擎: `PaymentRoutingRuleMatcher` (就餐方式, 金额闭区间, 菜品包含/仅含模式, 时段, AND/OR 组合)
- 服务层: `PaymentRoutingRuleService` (CRUD, 优先级重排, 模拟试算 `simulate`)
- 路由器重构: `WechatMerchantRoutingService.route(PaymentRoutingContext)` (优先新规则链, 平滑回退 legacy 规则, `isMerchantPayReady` 降级自愈)
- 控制器: `AdminPaymentRoutingRuleController` (权限 `payment:config:read/write`)
- 订单与明细装配: `PaymentSettlementService`, `WechatNativePaymentService`, `WechatMicropayService` 注入订单菜品上下文