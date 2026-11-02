# Scenario Matrix — WI-064

| ID | Context | Expected | Invariants | Verification | Result |
|---|---|---|---|---|---|
| S01 | 加菜 expectedVersion=current | 成功，revision +1 | ORDER-001/002 | service + add-dishes regression | PASS |
| S02 | 同一旧版本再次加菜 | HTTP 409 + latest summary，零副作用 | ORDER-002 | service/controller | PASS |
| S03 | 退菜陈旧版本 | 授权 token 不消费，明细/库存/KDS 不变 | ORDER-002/APPROVAL | controller no-interaction | PASS |
| S04 | 改价陈旧版本 | 明细、金额、支付尝试、桌台不变 | ORDER-002/TABLE | controller no-interaction | PASS |
| S05 | 优惠陈旧版本 | 订单和桌台金额不变 | ORDER-002/TABLE | controller no-interaction | PASS |
| S06 | 未传 expectedVersion | 兼容成功且 revision +1 | ORDER-002 | existing controller regressions + CAS unit | PASS |
| S07 | expected_version 别名 | 与 expectedVersion 等价 | ORDER-002 | DTO/service unit | PASS |
| S08 | 负数/小数/非数字 | 400 ORDER_VERSION_INVALID | ORDER-002 | service unit | PASS |
| S09 | CAS 0 行 | 409 并回滚全部副作用 | ORDER-002 | service unit + transactional boundary review | PASS |
| S10 | KDS POS 加菜 | t_order revision 只 +1，局部 KDS revision 正常 | ORDER-002/KDS-001 | KDS ownership contract | PASS |
| S11 | 未授权 C 端加菜携带旧版本 | 先返回 403，不泄露最新订单摘要 | AUTHZ/TABLE | controller no-interaction | PASS |
| S12 | 成功响应 | 各入口返回最新 revision | ORDER-002 | controller regressions + OpenAPI | PASS |
