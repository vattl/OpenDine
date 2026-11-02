# Review Report — WI-063

Review Decision: PASS

## Review Scope
复核了权限正确性、跨动作绕过、token 消费时机、订单/门店/金额绑定、角色迁移、API 兼容、错误恢复、测试证据和文档同步。

## Resolved Findings
- 畸形兼容凭证最初可能再次返回 REQUIRE_APPROVAL；已改为稳定 DENY/401，并增加回归测试。
- 改价最初可能在确认订单明细有效前消费 token；已把资源校验移到授权前，并保留支付金额变更准备在授权后执行。
- 现金退款省略金额时，授权上下文改为从权威订单数据计算“剩余可退额与现金剩余额的较小值”。
- 优惠授权绑定服务端计算后的实际优惠金额，避免仅信任前端输入。

## Open Issues
无 WI-063 范围内 HIGH/CRITICAL 未决项。全仓既有测试失败已隔离并记录在 `TEST_REPORT.md`，未混入本安全改造。
