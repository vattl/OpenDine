# Implementation Design — WI-012

## Root Fix / Owner

删除桌台查询对订单金额的二次解释。`TableStatusAmountCalculator` 使用订单持久化字段计算实际净应付，同时保留明细统计用于审计，不再按当前配置重算服务费。

## Minimal Change

- 订单 `sett_amount` 作为商品/费用基数。
- 订单 `service_fee` 使用已落库值。
- `discount_amount`、`refund_amount`、`pay_amount_gift` 继续扣减。
- `AdminTableController` 不再用计算结果覆盖响应 Order 的持久化金额。

## Verification Strategy

先新增“订单 116、明细 124，桌台必须 116”的失败测试；实现后运行 calculator/controller 专项测试、完整 Maven 测试与 clean package。
