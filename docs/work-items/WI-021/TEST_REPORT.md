# Test Report — WI-021

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Evidence

- TDD 红灯：实体未声明 null update 策略时测试明确失败。
- Native 专项：10 tests，0 failures，0 errors，0 skipped。
- 全量集合分段验证：除 `DataSourceBudgetConfigurationTest` 外 1295 tests（0 failures、0 errors、5 skips）；该连接池测试隔离运行 4 tests（0 failures、0 errors）。合计 1299 tests 全覆盖通过。
- OpenAPI YAML：解析通过，version `1.2.296`。
- runnable JAR：`mvnw.cmd clean package -DskipTests` BUILD SUCCESS。

## Existing suite timing note

单命令全量运行曾两次在既有 `DataSourceBudgetConfigurationTest` 的 80ms 首次建连窗口发生 `GetConnectionTimeoutException`；该测试隔离运行 4/4 通过，本次支付专项 10/10 通过，其余 1295 项整组通过。未修改无关连接池生产代码或测试以掩盖时序抖动。

## Covered behavior

- 新关单持久化清除 active_key。
- 关单后创建新 outTradeNo/codeUrl。
- 历史 CLOSED 残留活动键自动修复。
- CREATING/UNKNOWN 并发与不确定结果保护保持不变。
