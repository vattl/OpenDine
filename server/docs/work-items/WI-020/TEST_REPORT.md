# Test Report — WI-020

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Automated checks

- Targeted merchant/payment regression: 24 tests, 0 failures, 0 errors, 0 skipped.
- Full Maven regression: 1296 tests, 0 failures, 0 errors, 5 skipped.
- Full runnable package: `mvnw.cmd clean package -DskipTests`, BUILD SUCCESS.
- Artifact: `target/diancan-0.0.1-SNAPSHOT.jar`.
- OpenAPI parse: version `1.2.295`, 478 paths.
- Diff whitespace check: PASS.

## Coverage conclusion

覆盖凭据 fail-closed、退役/恢复、凭据版本快照、严格门店隔离、显式全局回退、任意 merchantKey、金额与就餐方式路由，以及 Native/MICROPAY 创建和后续操作的配置版本绑定。全量回归覆盖既有 JSAPI、通知和退款链路。

## Skips

全量测试中的 5 项既有 skip 未因本次变更增加；无必需检查被跳过。
