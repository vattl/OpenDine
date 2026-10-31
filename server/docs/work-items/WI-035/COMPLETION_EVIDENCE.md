# Completion Evidence — WI-035

## Current Status

ACCEPTED。

## Verification Evidence

- 单元测试：`OrderControllerCompanionAddDishesTest` 6/6 通过，覆盖单单加菜及并台多单加菜场景。
- 汇总口径统一：加菜更新桌台待结账金额时，自动查询同店同桌全部 `transac_status=unsettled` 订单，通过 `OrderNetRevenue.netRevenueYuan` 统一累加计算并持久化至 `t_table.amount`。
- 构建产物：`mvn clean package -DskipTests` 生成 `target/diancan-0.0.1-SNAPSHOT.jar`，构建成功。
- 门禁状态：`python .ai/scripts/gate.py work --work-item docs/work-items/WI-035 --phase accept` 执行通过。
