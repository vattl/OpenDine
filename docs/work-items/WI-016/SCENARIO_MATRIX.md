# Scenario Matrix — WI-016

| ID | Scenario | Expected Outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 有效付款码支付成功 | 验签后立即幂等入账 | INV-PAY-001/003 | client/service test | PASS |
| S02 | USERPAYING | 保持活动并提示客户端轮询 | INV-PAY-001 | service test | PASS |
| S03 | 网络/SYSTEMERROR/BANKERROR | 保持未知状态，禁止新单 | INV-PAY-001/003 | service error-path review + tests | PASS |
| S04 | 明确失败/过期码 | 终止尝试并返回稳定错误 | INV-PAY-001 | service branch review + full regression | PASS |
| S05 | 查单成功补偿 | 共享成功服务仅应用一次 | INV-PAY-003 | `querySuccessUsesSharedSettlement` | PASS |
| S06 | 撤销前已支付 | 查询收敛成功且不撤销 | INV-PAY-001 | reverse control-flow review + success tests | PASS |
| S07 | 安全撤销 | 15 秒后证书撤销并释放活动键 | INV-PAY-003 | `reverseQueriesFirstThenUsesCertificateEndpoint` | PASS |
| S08 | 伪造/无签名响应 | 拒绝信任响应 | INV-PAY-001 | codec/client tests | PASS |
| S09 | XXE 响应 | 安全解析失败且不读取外部资源 | INV-PAY-001 | `roundTripsEscapedXmlAndRejectsDoctype` | PASS |
| S10 | 付款码保密 | DB/响应/日志均无付款码 | INV-PAY-002 | schema/response review + byte-body debug evidence | PASS |
| S11 | 跨店访问 | 不调用微信并拒绝 | INV-PAY-002 | shop-scoped query + shared settlement shop constraint | PASS |
| S12 | JSAPI/Native 回归 | 原有链路不变 | INV-PAY-003 | full Maven test | PASS |
