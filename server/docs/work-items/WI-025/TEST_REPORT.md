# Test Report — WI-025

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Evidence

- TDD RED：新增用例首先复现了全额冲正后不能重新结账、重复冲正超额、退款幂等冲突未拒绝、日结不阻断错账、内部未匹配仍显示已对平、重复退款账单覆盖等问题。
- TDD GREEN：资金生命周期、结算/退款入口、日结一致性和对账匹配修复后，聚焦回归 `.\mvnw.cmd "-Dtest=PaymentLedgerServiceTest,PaymentFacadeBalanceLedgerTest,WechatPaymentSuccessServiceTest,WechatRefundSettlementServiceTest,CashierCheckoutServiceTest,CashierForceCheckoutTest,CashierOrderControllerTest,OrderLedgerConsistencyServiceTest,DailyCloseServiceTest,ReconciliationServiceTest,CashierShiftControllerTest,OrderAmountRecalculationPaymentGuardTest,OrderDetailRefundServiceTest" test` 共 151 tests，0 failures，0 errors。
- 全量回归：`.\mvnw.cmd test`，1361 tests，0 failures，0 errors，5 skipped。
- OpenAPI：PyYAML 解析 `docs/openapi.yaml` 成功；`docs/openapi.yaml` 与 `docs/API.md` 已同步 WI-025 语义。
- 格式：`git diff --check` 无错误。
- JAR：`.\mvnw.cmd clean package -DskipTests` 成功，产物 `target/diancan-0.0.1-SNAPSHOT.jar`（74,085,275 bytes），SHA-256 `53106BDD8770EF0DDF535B6FAA19F48A5F038BC05B2DA122060DA24CD49B900D`。

## Scope Note

验证覆盖最终服务端代码。真实 MySQL 数据核对、微信/支付宝官方账单样本回放和生产部署不在本地自动化范围内。
