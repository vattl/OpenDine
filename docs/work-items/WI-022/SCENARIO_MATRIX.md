# Scenario Matrix — WI-022

| ID | Input / Context | Expected Business Outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 收银总开；线上微信关；微信个人码开 | 微信个人码成功出码 | INV-001/002 | controller + capability unit | PASS |
| S02 | 收银总开；线上微信开；微信个人码关 | 返回“未启用微信收款码” | INV-001/002 | controller + capability unit | PASS |
| S03 | 收银总开；支付宝个人码开/关与线上开关相反 | 只依据 `offline_alipay_qr` 放行或拒绝 | INV-002 | controller + capability unit | PASS |
| S04 | 收银总开关关 | 微信/支付宝个人码均不可出码 | INV-003 | capability regression | PASS |
| S05 | Native/付款码微信商户支付 | 继续只受线上微信与商户配置约束 | INV-001 | full Maven suite | PASS |
