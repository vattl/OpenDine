# Test Report — WI-012

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## TDD Evidence

- RED：新增套餐明细漂移用例在旧实现下返回 124，未满足订单实际金额 116。
- GREEN：改用持久化订单金额后，该用例返回 116。

## Regression

- 专项：`TableStatusAmountCalculatorTest,AdminTableControllerTest,CashierCheckoutServiceTest,OrderAmountRecalculationServiceTest`，46 tests，0 failures，0 errors。
- 全量：`.\mvnw.cmd test`，1246 tests，0 failures，0 errors，5 skipped。
- 打包：`.\mvnw.cmd clean package -DskipTests`，BUILD SUCCESS。

## Artifact

- `target/diancan-0.0.1-SNAPSHOT.jar`
- Size: 73,921,906 bytes
- SHA-256: `A907CAA5CD6A399AFB693CF0C734CD068B7BBA438260FD7421ABAF117E5E18FB`
