# Acceptance Report — WI-035

Decision: ACCEPTED

## Acceptance Evidence

- 加菜后桌台待结账金额通过同店、同桌全部未结订单汇总计算，并台场景下不会遗漏其他订单。
- 汇总统一复用 `OrderNetRevenue.netRevenueYuan` 口径，涵盖服务费、折扣与退款。
- 自动化单元测试 `OrderControllerCompanionAddDishesTest` 覆盖单单加菜与并台多单加菜场景，6/6 全部通过。
- JAR 包打包成功：`target/diancan-0.0.1-SNAPSHOT.jar`。
