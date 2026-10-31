# Business Invariants — WI-067

## Applicable Invariants

| ID | Invariant | Source | Affected? | Verification |
|---|---|---|---|---|
| INV-PAY-003 | 支付/退款应用幂等且保留不可变会计证据 | project | yes | 日结资金一致性与历史快照回归 |
| INV-CLOSE-001 | 预检到关账间目标窗口财务事实变化必须使凭据失效 | WI-006 | yes | 目标窗口水位变化测试 |
| INV-CLOSE-SEQ-001 | 同一门店必须按营业日严格连续关账；存在更早未结日时不得展示或关账更晚日期 | candidate | yes | 多日、零销售、跳日及并发测试 |
| INV-CLOSE-SEQ-002 | 日结预检、摘要和截止水位只受目标营业窗口事实影响，不得被其他营业日活动污染 | candidate | yes | 后续钱箱/交易不干扰历史补结测试 |

## New Invariant Candidates

- `INV-CLOSE-SEQ-001`：门店日结严格按营业日连续推进，任何调用者均不可跳过更早未结日。
- `INV-CLOSE-SEQ-002`：目标营业日关账只消费并锁定该营业窗口的事实，窗口外经营不能改变其可结性或截止语义。
