# Test Report — WI-035

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## RED Evidence

原实现使用 `table.setAmount(paidAmount)` 直接覆盖桌台金额，在并台多笔未结订单场景下，第二单加菜会直接丢失第一单金额。

## GREEN / Regression Evidence

- `mvnw.cmd '-Dtest=OrderControllerCompanionAddDishesTest' test`
  - Tests run: 6
  - Failures: 0
  - Errors: 0
  - 验证 `addDishes_whenMergedTableHasMultipleUnsettledOrders_shouldAggregateAllUnsettledOrdersNetRevenueForTable` 准确汇总未结订单金额为 160.0。
- `mvnw.cmd '-Dtest=OrderControllerAddDishesComboTest' test`
  - Tests run: 5
  - Failures: 0
  - Errors: 0
  - 验证单单加菜及套餐加菜场景。
- `mvnw.cmd clean package -DskipTests`
  - BUILD SUCCESS
  - 产物：`target/diancan-0.0.1-SNAPSHOT.jar`

## Scope Decision

范围专项测试全部通过，且全仓打包成功。
