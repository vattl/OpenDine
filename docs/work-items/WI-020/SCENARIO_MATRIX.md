# Scenario Matrix — WI-020

| ID | Scenario | Expected Outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 无主密钥保存 APIv3/APIv2 key | 拒绝保存，不产生 `plain:` | INV-004 | cipher/service unit | PASS |
| S02 | 删除已用商户 | 标记 RETIRED，凭据/历史保留 | INV-003 | lifecycle service test | PASS |
| S03 | 恢复退役商户 | ACTIVE 且缓存刷新 | INV-003 | controller/service test | PASS |
| S04 | 门店无本店商户且未允许继承 | 支付就绪失败，不使用全局商户 | INV-001 | resolver isolation test | PASS |
| S05 | 门店明确允许全局继承 | 可解析全局模板并标记来源 | INV-001 | policy resolver test | PASS |
| S06 | 任意 merchantKey | 精确解析对应本店商户 | INV-001/005 | key-store unit | PASS |
| S07 | 金额/就餐方式命中规则 | 自动选择目标 merchantKey | INV-005 | router unit | PASS |
| S08 | Native/MICROPAY 创建后配置轮换 | 查单仍按绑定版本解析 | INV-002 | payment service/client test | PASS |
| S09 | JSAPI 回调/退款 | 按订单绑定校验 mchId/appId/凭据 | INV-002 | success/refund regression | PASS |
| S10 | 跨店读取/修改/路由 | 返回拒绝或无可用商户 | INV-001 | scope/security tests | PASS |
| S11 | API 密钥/私钥输出 | 仅掩码/引用，无明文 | INV-004 | response + secret scan | PASS |
