# Scenario Matrix — WI-019

| ID | Scenario | Expected Outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 微信返回 400 `PARAM_ERROR` | `40231`，尝试 `CLOSED/PAYERROR`，释放活动键 | INV-PAY-002 | `createReleasesActiveAttemptWhenWechatExplicitlyRejectsRequest` | PASS |
| S02 | 微信返回 401/403 | `40231`，安全化返回微信错误码 | INV-PAY-002 | 4xx classification unit path | PASS |
| S03 | 微信返回 5xx | `50331`，尝试保持 `UNKNOWN` | INV-PAY-003 | `createKeepsWechatFiveHundredAsUncertain`; service uncertainty test | PASS |
| S04 | 网络超时或 I/O 异常 | `50331`，尝试保持 `UNKNOWN` | INV-PAY-003 | generic uncertain branch + regression | PASS |
| S05 | 微信成功响应验签失败 | `50331`，不接受二维码 | INV-PAY-001/003 | `createRejectsInvalidWechatResponseSignature` | PASS |
| S06 | 正确签名成功响应 | 返回 `code=0/codeUrl` | INV-PAY-001 | `createAcceptsVerifiedResponseAndUsesExistingMerchantCertificateIdentity` | PASS |
