# Scenario Matrix — WI-063

| ID | Scenario | Expected | Verification | Result |
|---|---|---|---|---|
| S01 | 当前人有退款 execute | 退款 ALLOW | unit/controller | PASS |
| S02 | 当前人仅 cashier entry | REQUIRE_APPROVAL，业务零调用 | unit/controller | PASS |
| S03 | 严格 token 匹配 | 核销一次并 ALLOW | unit | PASS |
| S04 | token 错动作/订单/金额/终端 | DENY，业务零调用 | existing approval + unit | PASS |
| S05 | 兼容现场密码 | v2 签发并立即核销，ALLOW | unit | PASS |
| S06 | 现场授权人缺 exact approve | DENY | unit | PASS |
| S07 | 仅 refund execute 调用 changePrice | REQUIRE_APPROVAL/ DENY，不直接 ALLOW | unit | PASS |
| S08 | 反结账无动作授权 | REQUIRE_APPROVAL，结账服务零调用 | controller | PASS |
| S09 | 反结账 exact execute | ALLOW | controller | PASS |
| S10 | 显式 DENY + 现场凭证 | DENY，不签发令牌 | unit | PASS |
| S11 | 运营微信退款 | 同一 refund 门面 | controller | PASS |
| S12 | V042 角色迁移 | 管理角色有精确权限，cashier 无执行权 | SQL contract test | PASS |
| S13 | 旧请求字段 | authorization/approvalToken 保持兼容 | controller/docs | PASS |
| S14 | 业务不变量 | 范围内权限、订单与结账回归通过 | regression | PASS；全仓既有失败另见测试报告 |
