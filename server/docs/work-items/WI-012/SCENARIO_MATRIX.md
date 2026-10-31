# Scenario Matrix — WI-012

| Scenario | Expected Result | Status | Evidence |
|---|---|---|---|
| 套餐 108 + 菇串 8 | 桌台金额 116，不采用漂移后的 124 明细和 | PASS | `calculateUsesPersistedOrderAmountWhenComboDetailsDrift` |
| 优惠/退款/礼品支付 | 按订单实际净应付扣减 | PASS | `TableStatusAmountCalculatorTest` + `OrderNetRevenue` 统一口径 |
| 合并桌多订单 | 各订单实际净应付求和 | PASS | `status_shouldAggregateAllUnsettledOrdersForTable` |
| 历史订单与复用桌 | 不覆盖当前桌台金额 | PASS | `status_shouldReturnOnlyHistoricalOrderWhenTableHasBeenReused` |
