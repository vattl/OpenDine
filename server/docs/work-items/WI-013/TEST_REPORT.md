# Test Report — WI-013

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## TDD Evidence

- 权限阻断：普通操作员（无 `admin:manage`）请求 `force: true` 时，正确返回 403 被阻断，未更新订单或清理意向。
- 特权放行：具备 `admin:manage` 权限或超管身份时，成功绕过收款会话冲突完成结账，并原子将名下意向标记为 `COMPLETED`。
- 特权审计：强结成功后正确调用 `SecurityAuditService.recordPrivilegedAction` 写入审计日志。

## Regression

- 专项测试：`CashierForceCheckoutTest,CashierCheckoutServiceTest,AdminOrderControllerTest,TableStatusAmountCalculatorTest`，44 tests，0 failures，0 errors。
- 打包：`.\mvnw.cmd clean package -DskipTests`，BUILD SUCCESS。

## Artifact

- `target/diancan-0.0.1-SNAPSHOT.jar`
- Size: 73,926,022 bytes
- SHA-256: `9FCF02E027E19B7A57550023DA514D26E39216C4E76A51E192B2BEE04260DC45`
