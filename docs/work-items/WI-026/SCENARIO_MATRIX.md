# Scenario Matrix — WI-026

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 订单有实收投影但完全无成功流水 | 成功非挂账订单，流水为空 | 阻断并返回缺失流水、总额短少和渠道缺失 | INV-FIN-004/006/007 | `OrderLedgerConsistencyServiceTest` | PASS |
| S02 | 流水渠道与订单投影不一致 | 订单微信投影，流水为现金 | 同时解释缺失渠道与意外渠道，并返回渠道差额 | INV-FIN-004/007 | `OrderLedgerConsistencyServiceTest` | PASS |
| S03 | 同渠道流水金额超额 | 订单现金 75 元、流水净额 100 元 | 返回总额/渠道超额及 +2500 差额 | INV-FIN-004/007 | `OrderLedgerConsistencyServiceTest` | PASS |
| S04 | 日结存在异常订单 | 一致性服务返回多原因 Issue | 不签发令牌，blocker 返回原因汇总及明细 | INV-FIN-006/007 | `DailyCloseServiceTest` | PASS |

## Acceptance rule

全部场景 PASS；Material NOT_VERIFIED count: 0。
