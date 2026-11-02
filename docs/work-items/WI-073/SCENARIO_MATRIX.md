# Scenario Matrix — WI-073

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 普通商户支付成功页开票入口 | 微信支付下单且已开通发票 | 下单携带 `support_fapiao=true` | 产品身份匹配 | 静态代码 + 官方文档 | ISSUE |
| S02 | 收银端扫码采集抬头 | 已支付订单、有效二维码 | 仅授权用户可提交且金额正确 | 强 token 绑定 | 静态代码审计 | ISSUE |
| S03 | 真实开具并交付 | 抬头已提交 | 税控平台真实开票，状态和文件可追溯 | 不得伪造 SUCCESS | 静态代码审计 | ISSUE |
| S04 | 微信服务商抬头链接 | 已授权普通服务商、子商户、OpenID | 官方链接可获取且回调闭环 | 服务商身份匹配 | 静态代码 + 官方文档 | ISSUE |
| S05 | 未支付/取消订单 | 订单未支付 | 禁止申请和登记发票 | 仅已支付可开票 | 静态代码审计 | ISSUE |
| S06 | 部分或全额退款前开票 | 订单已退款 | 可开票余额准确且不超额 | 累计金额约束 | 静态代码审计 | ISSUE |
| S07 | 已开票后退款 | 发票 SUCCESS 后退款 | 冲红或人工异常流程闭环 | 发票与退款一致 | 静态代码审计 | ISSUE |
| S08 | 重复申请/并发/回调重放 | 同一订单多次操作 | 幂等且不重复、不错乱 | 唯一性与状态机 | 静态代码审计 | ISSUE |

## Acceptance rule

本 Work Item 接受的是审计交付质量，不代表发票模块上线通过。每个场景必须形成有证据的 PASS / ISSUE / UNVERIFIED / N/A；任何产品 HIGH/CRITICAL ISSUE 均使模块上线判定为 BLOCKED。
