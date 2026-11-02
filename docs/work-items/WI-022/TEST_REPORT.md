# Test Report — WI-022

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Evidence

- RED：新增 controller 回归测试在旧实现下 3/3 失败，证明个人码入口读取线上渠道。
- RED：新增真实 capability 正反组合测试在旧 matcher 下失败，证明稳定个人码渠道码仍映射到线上字段。
- GREEN：`mvnw.cmd "-Dtest=PayOfflineCollectControllerTest,PaymentCapabilityServiceClientTest,CashierCheckoutServiceTest" test`：61 tests，0 failures，0 errors。
- FULL：`mvnw.cmd test`：1303 tests，0 failures，0 errors，5 skipped（既有跳过项）。
- PACKAGE：`mvnw.cmd clean package -DskipTests`：BUILD SUCCESS，生成 `target/diancan-0.0.1-SNAPSHOT.jar`。
