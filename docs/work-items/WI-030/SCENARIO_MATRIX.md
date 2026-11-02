# Scenario Matrix — WI-030

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 客户端订单带 `merchantId=2` 且无路由规则 | 门店 default/small_amount 均启用 | 新支付固定选择 default | INV-PAY-030-01 | router unit | PASS |
| S02 | 金额/就餐规则命中指定商户 | 有有效规则 | 选择规则目标商户 | INV-PAY-030-01 | router unit | PASS |
| S03 | 另一实例停用商户后创建支付 | 本节点缓存仍有旧行 | DB 权威查询拒绝旧商户 | INV-PAY-030-01 | config service unit | PASS |
| S04 | 固化配置属于其他门店 | order.shop=5, config.shop=6 | 拒绝解析/入账 | INV-PAY-030-02 | key store/success unit | PASS |
| S05 | 支付回调缺失或错误 mchid/appid | 已存在有效支付尝试 | 返回失败且订单/流水不变 | INV-PAY-030-03 | success unit | PASS |
| S06 | 正确支付回调 | 门店、金额、商户、AppID 全匹配 | 流水先写、订单成功、重复回调幂等 | INV-PAY-030-03 | payment regression | PASS |
| S07 | 未登记退款回调 | out_refund_no 不存在 | 返回失败，不创建退款台账、不改订单 | INV-PAY-030-04 | refund ledger/controller unit | PASS |
| S08 | 退款金额/交易号/商户号任一不符 | 已登记退款申请 | 返回失败，不入账 | INV-PAY-030-04 | refund unit | PASS |
| S09 | 正确退款回调及重复通知 | 已登记且绑定完整 | 只入账一次并写退款流水 | INV-PAY-030-04 | refund integration unit | PASS |
| S10 | 重复订单号或大量回调商户历史 | 迁移/查询检查 | 唯一约束阻止重复；回调按序列号索引查询 | INV-PAY-030-05 | migration/static test | PASS |

## Acceptance rule

所有场景必须 PASS；任何资金身份场景 UNKNOWN、NOT_RUN、FAIL 或 BLOCKED 均阻止验收。
