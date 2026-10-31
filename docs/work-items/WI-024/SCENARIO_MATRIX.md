# Scenario Matrix — WI-024

| ID | Context | Expected outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 首次按252元请求预支付 | 创建一笔 ACTIVE 尝试并返回252元参数 | INV-PAY-001/002 | `WechatJsapiPaymentServiceTest` first-create case | PASS |
| S02 | 相同订单/金额重复请求 | 复用同一 prepay，不新建交易 | INV-PAY-001 | `WechatJsapiPaymentServiceTest` reuse case | PASS |
| S03 | 252预支付后退15元菜，包括顾客已拉起密码框 | 任何库存/KDS/菜品写入前先查单并关闭旧交易，再提交237元订单 | INV-PAY-003 | JSAPI changed-amount case + refund side-effect ordering test | PASS |
| S04 | 退菜与支付成功并发竞争 | 支付先赢锁则退菜零副作用失败；退菜先赢锁则旧支付关闭后才能改金额 | INV-PAY-004 | paid-after-lock case + refund no-side-effect case | PASS |
| S05 | 查单/关单超时 | 金额变更失败，尝试保持 UNKNOWN/活动 | INV-PAY-003 | JSAPI unknown-state and mutation rollback cases | PASS |
| S06 | 关单后重新支付237元 | 新 out_trade_no、金额237、旧单不可付 | INV-PAY-001/002 | JSAPI changed-amount replacement case | PASS |
| S07 | 回调金额与尝试不同 | 不入账，尝试标记冲突 | INV-PAY-002 | JSAPI callback-conflict case + payment-success mismatch case | PASS |
| S08 | 第二个交易支付同一业务单 | 不视为幂等，不覆盖首笔 transaction_id | INV-PAY-005 | `WechatPaymentSuccessServiceTest` duplicate transaction case | PASS |
| S09 | 回调 openid/商户/门店不符 | 不入账并记录安全冲突 | INV-PAY-006 | handler exact attempt/merchant/AppID/payer checks + full regression | PASS |
| S10 | 部署前无尝试的在途回调金额精确一致 | 兼容入账 | INV-PAY-002 | legacy exact-amount success case | PASS |
| S11 | 部署前无尝试的旧252回调、本地237 | 拒绝入账并保持订单未结 | INV-PAY-002 | legacy underpayment/amount-drift regression cases | PASS |
| S12 | Native/付款码/余额/现金/挂账 | 行为不回归 | preserved invariants | full Maven: 1348 tests, 0 failures/errors, 5 skipped | PASS |
| S13 | 微信成功回调结算订单 | 先写入/校验权威支付流水，再更新订单；流水失败时订单不结清且回调重试 | INV-PAY-008 | `WechatPaymentSuccessServiceTest` ordering + ledger failure cases | PASS |
| S14 | 收银手工结账与 JSAPI/回调竞争 | 先收敛 JSAPI、再写流水、最后更新订单；已有不同成功流水或已支付 JSAPI 时拒绝覆盖 | INV-PAY-004/008 | `CashierCheckoutServiceTest` ordering/conflict + `PaymentLedgerServiceTest` authoritative conflict | PASS |

全部场景必须 PASS；任何 NOT_VERIFIED / FAIL / BLOCKED 阻止 ACCEPT。
