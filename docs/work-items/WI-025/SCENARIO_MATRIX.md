# Scenario Matrix — WI-025

| ID | Scenario | Expected outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 余额支付流水写入失败 | 钱包、订单全部回滚 | INV-FIN-001 | `PaymentFacadeBalanceLedgerTest` | PASS |
| S02 | 后台成功结账 | 委托统一收银结算并持有行锁 | INV-FIN-001 | `CashierForceCheckoutTest` / controller tests | PASS |
| S03 | 微信退款流水失败 | refund_amount 与退款请求状态均回滚 | INV-FIN-001/002 | `WechatRefundSettlementServiceTest` | PASS |
| S04 | 现金人工退款 | 先写关联现金 REFUND，再更新订单 | INV-FIN-001/002 | `CashierCheckoutServiceTest` | PASS |
| S05 | 余额本金+赠送退款 | 分渠道 REFUND 与钱包/订单原子一致 | INV-FIN-001/002 | `CashierCheckoutServiceTest` | PASS |
| S06 | 结账后全额反结账再结账 | 旧 PAYMENT 被冲正，新 PAYMENT 可创建 | INV-FIN-003 | `PaymentLedgerServiceTest` | PASS |
| S07 | 重复或冲突退款请求 | 精确重放幂等，冲突拒绝 | INV-FIN-002 | `PaymentLedgerServiceTest` | PASS |
| S08 | 班次/日结预览读取 | 不产生任何新流水 | INV-FIN-005 | Shift/daily full regression | PASS |
| S09 | 成功订单缺失或错配流水 | 日结阻断且不签发令牌 | INV-FIN-004/006 | `OrderLedgerConsistencyServiceTest` / `DailyCloseServiceTest` | PASS |
| S10 | 挂账、跨午夜、内部未匹配 | 按支付营业日核对，挂账分离，状态为差异 | INV-FIN-004/006 | `ReconciliationServiceTest` | PASS |

全部场景 PASS；Material NOT_VERIFIED count: 0。
