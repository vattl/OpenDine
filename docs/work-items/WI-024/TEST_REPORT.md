# Test Report — WI-024

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Evidence

- TDD RED：`WechatPaymentSuccessServiceTest` 最初按预期暴露两个缺陷——旧逻辑接受低于订单金额的付款，并把不同 transaction_id 当作幂等。
- TDD GREEN：支付成功服务改为订单净应付精确匹配、交易号精确幂等后，专项测试通过。
- 最终专项覆盖 JSAPI 生命周期、支付成功、权威流水写入顺序、手工结账冲突、金额重算和退菜副作用顺序；`.\\mvnw.cmd "-Dtest=CashierCheckoutServiceTest,CashierForceCheckoutTest,WechatPaymentSuccessServiceTest,PaymentSettlementLedgerHelperTest,PaymentLedgerServiceTest,WechatJsapiPaymentServiceTest,OrderDetailRefundServiceTest" test` 共 85 tests，0 failures，0 errors。
- 全量回归：`.\\mvnw.cmd test`，1348 tests，0 failures，0 errors，5 skipped。
- OpenAPI：PyYAML 解析成功；`docs/openapi.yaml` 与 `docs/API.md` 已同步。
- 格式：`git diff --check` 无错误。
- JAR：`.\\mvnw.cmd clean package -DskipTests` 构建成功，产物 `target/diancan-0.0.1-SNAPSHOT.jar`（74,075,179 bytes），SHA-256 `9F39CA0FD15F5590B4F3C3DA7F89DC93088CE412A402EA90C062CEA80DD8071F`。

## Scope Note

全量回归和 JAR 打包均覆盖最终生产代码；生产数据库迁移和真实微信支付端到端测试不在本地自动化范围内。
