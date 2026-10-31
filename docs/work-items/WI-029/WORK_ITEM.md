# WORK ITEM — WI-029

## Request

修复营业日报未完整结合挂账的问题，使销售、实际收款和应收变动可明确区分并可用于财务对账。

## Type

REPAIR

## State

ACCEPTED

## Requirement Contract

### Goal

统一同步日报、详细日报、Z/X 报表打印文本和 CSV 导出的挂账口径。

### Current behavior

- 挂账销售进入净销售额，但 /admin/report/daily 不返回应收汇总和实际收款合计。
- 日结打印将包含挂账的 net_sales 标为“净营业实收”。
- Z 报表异常降级时可能将挂账订单金额当成支付渠道实收。
- CSV 只输出订单销售聚合，无法识别应收新增、回款、核销和撤销。
- 已日结快照不持久化撤销金额，历史 Z 报表固定返回 reversed_fen=0。

### Target behavior

- 详细日报增量返回 receivableSummary、totalCollectionsFen 和 totalCollections。
- 支付渠道始终只表示真实支付流水；降级统计排除挂账销售。
- 打印文本明确区分净销售额、实际收款、新增挂账、回款、坏账、撤销与期末余额。
- CSV 增加窗口应收变动列，保留既有列和顺序以兼容现有消费者。
- 已日结快照准确保存和返回挂账撤销金额。
- OpenAPI 与 API.md 同步。

### Must preserve

- 挂账销售仍在发生营业日计入净销售额。
- 回款只在真实发生日计入实际收款，不重复增加销售额。
- 支付渠道不伪造挂账支付流水。
- 门店隔离、营业窗口和既有响应字段保持兼容。

### Acceptance criteria

- [x] 详细日报返回完整应收与实收字段。
- [x] 打印文案不再把含挂账的销售额称作实收。
- [x] 异常降级不把挂账计入支付渠道。
- [x] CSV 可区分应收新增、回款、坏账和撤销。
- [x] 已结快照保留撤销金额。
- [x] 回归测试、API 文档及完整 JAR 构建通过。

## Business Invariants

- INV-FIN-001：净销售额与实际收款必须分列，二者不得混称。
- INV-FIN-002：挂账创建销售事实但不创建支付事实。
- INV-FIN-003：应收回款只在回款发生营业日进入实际收款。
- INV-FIN-004：历史日结快照必须不可变且足以重放当日财务摘要。
- INV-TENANT-001：所有应收报表数据必须按门店隔离。

## Impact Map Authority

- Impact map path: docs/work-items/WI-029/IMPACT_MAP.md
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: docs/work-items/WI-029/SCENARIO_MATRIX.md
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: NONE

## Acceptance Decision

ACCEPTED
