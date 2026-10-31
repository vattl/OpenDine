# Scenario Matrix — WI-023

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 创建门店账户 | 有效门店、额度和账期 | ACTIVE、余额0、仅本店可见 | INV-AR-004/005 | `createAccount_initializesActiveZeroBalanceAccount` | PASS |
| S02 | 商户共享账户 | scope=MERCHANT | 同商户门店可用；管理需总部权限 | INV-AR-004 | merchant-scope charge + management denial tests | PASS |
| S03 | 挂账成功 | 同店未结单、额度充足 | 原子生成应收/流水并完成订单 | INV-AR-001/002/003 | server-amount/service + payment-ledger tests | PASS |
| S04 | 挂账幂等重试 | 相同 requestId/order | 返回同一应收，不重复占额 | INV-AR-001/006 | fast replay + post-lock concurrent-winner tests | PASS |
| S05 | 并发额度竞争 | 两单总额超过剩余额度 | 最多一笔成功，不超额度 | INV-AR-005 | order/account `FOR UPDATE` review + DB unique keys | PASS |
| S06 | 非法挂账 | 跨店、暂停账户、已结订单 | 零写入并明确拒绝 | INV-AR-004/005 | suspended/credit/scope service tests | PASS |
| S07 | 部分回款 | amount < outstanding | claim=PARTIAL，余额同步减少 | INV-AR-001/005/006 | `collect_partiallyReduces...` | PASS |
| S08 | 全额回款 | amount = outstanding | claim=SETTLED，账户余额释放 | INV-AR-001/005 | `collect_fullAmountSettles...` | PASS |
| S09 | 超收/重复回款 | amount>余额或相同requestId | 拒绝超收；重试幂等 | INV-AR-005/006 | over-collection + replay tests | PASS |
| S10 | 撤销挂账 | OPEN且从未回款 | 追加REVERSAL、订单回未结、额度释放 | INV-AR-006/007 | `reverse_unpaidClaim...` | PASS |
| S11 | 有回款后撤销 | PARTIAL | 拒绝直接撤销 | INV-AR-007 | `reverse_rejectsClaimAfterAnyPartialCollection` | PASS |
| S12 | 坏账核销 | 剩余欠款、授权人与原因 | 追加WRITE_OFF、关闭余额、不计实收 | INV-AR-006/007/008 | write-off + permission review/tests | PASS |
| S13 | 账龄逾期 | 到期日前后 | 正确返回未到期/1-30/31-60/61-90/90+ | INV-AR-008 | clock-boundary + overdue read tests | PASS |
| S14 | 日结销售/实收 | 当日挂账、次日回款 | 销售计挂账日；实收计回款日 | INV-AR-003/008 | `precheck_countsCreditSale...` | PASS |
| S15 | 现有支付回归 | 微信/现金/余额订单 | 支付台账、日结、退款行为不变 | existing PAY invariants | 1325-test full Maven suite | PASS |

## Acceptance rule

全部场景必须 PASS；任何 NOT_RUN / FAIL / BLOCKED 阻止 ACCEPT。
