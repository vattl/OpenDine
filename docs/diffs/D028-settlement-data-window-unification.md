# D028 — 结算日数据窗口统一

- Parent: C011
- Complexity: STRUCTURAL
- Status: ACTIVE

## 当前状态

订单、日报、看板、导出和 Analytics 的营业日聚合混用“开台日 `[open_time, next settle_time)`”、自然日和动态当前时间截断；`/cashier/order/today` 已采用结算日 12 小时窗口。相邻查询还混用闭区间与右开区间。

## 目标状态

1. 结算数据的 `date` 一律表示结算日 D。
2. 结算窗口一律为 `[D settle_time - 12h, D settle_time)`；`settle_time -> close_time -> 04:00` 回退。
3. 报表默认查询最近完成的结算日；收银/KDS 当前班次保持运行时语义。
4. 所有结算数据查询使用右开结束边界。

## Diff

| Operation | Target | Expected result | Negative acceptance |
|---|---|---|---|
| REPLACE | `ShopBusinessWindowResolver.resolveWindow` consumers | 改为结算日窗口与明确的“最近完成/当前班次”日期选择 | 报表接口不再调用 `windowFor` 或 `businessDayFor` |
| MODIFY | 订单统计、日报、报表、导出 | `date` 作为结算日，统一 `[start,end)` | 无 `<= settle_time` 聚合边界 |
| REPLACE | `OrderMapper` 营业额/看板 SQL | 显式结算窗口或基于结算日标签的聚合 | 无 `CURTIME()` 动态营业窗口 |
| MODIFY | Analytics | 默认窗口取最近完成结算日，标签以结算日归属 | 无 open_time 驱动的结算数据过滤 |
| UNCHANGED | KDS 实时配送 | 当前营业班次继续服务运行中工单 | 不将实时 KDS 强制改为已结算报表窗口 |
| MODIFY | API 文档与测试 | 参数和边界规则可验证、可使用 | 文档不再称 date 为开台日 |
