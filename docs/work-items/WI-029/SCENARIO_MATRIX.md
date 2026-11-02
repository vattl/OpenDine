# Scenario Matrix — WI-029

| ID | Scenario | Expected Business Outcome | Verification | Result |
|---|---|---|---|---|
| S01 | 当日新增挂账 100 元，无回款 | 净销售额含 100；实际收款不含 100；应收新增为 100 | AdminReportControllerDailyReportTest | PASS |
| S02 | 当日历史应收回款 40 元 | 销售额不重复增加；实际收款与应收回款增加 40 | AdminReportControllerDailyReportTest / DailyCloseServiceTest | PASS |
| S03 | 当日坏账/撤销 | 日报与历史 Z 报表保留各自金额 | DailyCloseServiceTest | PASS |
| S04 | Z 报表生成失败 | 挂账不进入支付渠道，仍返回应收摘要 | AdminReportControllerDailyReportTest | PASS |
| S05 | 打印日结清单 | 显示净销售额、实际收款及完整应收摘要，无“净营业实收”误称 | DailyCloseServiceTest | PASS |
| S06 | 导出日报 CSV | 保留旧列并追加四个应收变动列，按门店和营业窗口汇总 | ReportOrderAggregateTest / ReportLogServiceTest | PASS |

Material NOT_VERIFIED count: 0


