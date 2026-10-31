# Implementation Design — WI-029

## Root Fix / Owner

复用日结服务已经形成的应收摘要作为详细日报权威来源；无 Z/X 报表时直接按同一营业窗口调用 `ReceivableService`。销售和收款字段显式分离，不再通过支付渠道差额隐式推断挂账。

## Contract Design

现有字段不删除、不改类型，仅增量增加：

- `report.receivableSummary.{chargedFen,collectedFen,writeoffFen,reversedFen,outstandingFen,cutoffLedgerId}`
- `report.totalCollectionsFen`
- `report.totalCollections`
- CSV 尾部增加 `receivable_charged_amount`、`receivable_collected_amount`、`receivable_writeoff_amount`、`receivable_reversed_amount`

## Persistence

追加新的 Flyway 迁移，为 `t_daily_close_snapshot` 增加非空默认 0 的 `receivable_reversed_fen`；不修改已发布 V028。

## Failure Behavior

- Z/X 报表生成失败时，日报仍可从应收服务形成摘要。
- 支付渠道备用聚合明确排除 `payment_method=挂账`。
- 应收服务不可用时安全返回零摘要，但不得把挂账伪装为实收。

## Verification Strategy

先增加失败测试，覆盖详细日报透传、降级渠道、打印口径、快照撤销和 CSV 表头/数据，再实现最小修复；随后运行相关测试、全量测试与强制 clean package。

