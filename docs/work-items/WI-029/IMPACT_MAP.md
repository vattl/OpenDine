# Impact Map — WI-029

## Authoritative Owner

- 销售归属：成功订单与 `OrderNetRevenue`。
- 实际支付：`t_payment_ledger`。
- 应收变动：`t_receivable_ledger` 与 `ReceivableService`。
- 日结快照：`DailyCloseServiceImpl` / `t_daily_close_snapshot`。

## Layer Coverage

API controller、日结服务、应收汇总、快照持久化、CSV 导出、测试和接口文档均在范围内。

## Affected Surfaces

| Surface | Evidence | Planned change |
|---|---|---|
| 详细营业日报 | 已读取 Z 报表但丢弃 `receivable_summary`/`total_collections_fen` | 增量透传 camelCase 财务字段 |
| 渠道降级 | 按成功订单净额聚合，包含挂账 | 排除挂账，渠道只表示真实收款 |
| 日结打印 | `net_sales` 标为“净营业实收” | 改为净销售额并新增应收/实际收款区块 |
| 日结快照 | 缺少 `receivable_reversed_fen` | 追加迁移及实体/快照读写 |
| CSV 导出 | 仅订单销售 7 列 | 追加应收窗口变动列 |
| 测试 | 仅验证底层日结，未覆盖日报挂账消费端 | 增加日报、打印、快照和导出回归 |
| API 契约 | 未声明新增日报与导出字段 | 同步 OpenAPI/API.md |

## Consumers

- 运营后台日报消费者。
- 日结打印/归档消费者。
- 报表 CSV 下载消费者。

## Excluded

- 前端 UI 改造（不在本仓库）。
- 应收账户、回款业务规则本身。
- 生产部署。

Material UNKNOWN count: 0

