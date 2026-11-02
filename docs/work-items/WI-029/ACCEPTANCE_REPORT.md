# Acceptance Report — WI-029

Decision: ACCEPTED

## Business outcome

营业日报、详细日报、Z/X 报表打印文本和 CSV 导出的挂账口径完全统一，净销售额（包含挂账销售）与实际收款合计（支付台账净额 + 应收回款 + 充值本金）明确区分，有效支持财务对账；日结快照完整保存挂账撤销金额。

## Criteria

- PASS：详细日报返回完整应收与实收字段（receivableSummary, totalCollectionsFen, totalCollections）。
- PASS：打印文案不再把含挂账的销售额称作实收，明确标为“净销售额”并独立输出“实际收款合计”与应收摘要。
- PASS：异常降级不把挂账计入支付渠道。
- PASS：CSV 可区分应收新增、回款、坏账和撤销，保持前 7 列兼容。
- PASS：已结快照保留撤销金额（V031 迁移与 receivable_reversed_fen 字段）。
- PASS：回归测试、API 文档及完整 JAR 构建通过。

## Completion level

ACCEPTED
