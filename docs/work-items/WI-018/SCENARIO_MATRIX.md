# Scenario Matrix — WI-018

| ID | Scenario | Expected Outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|
| S01 | 正确签名的 Native 下单响应 | 返回微信 `code_url` | INV-PAY-001/002 | `createAcceptsVerifiedResponseAndUsesExistingMerchantCertificateIdentity` | PASS |
| S02 | 响应签名伪造或签名头缺失 | 拒绝响应并保持不确定 | INV-PAY-001/003 | `createRejectsInvalidWechatResponseSignature`; `createRejectsResponseWithMissingSignatureHeaders` | PASS |
| S03 | 平台公钥 ID 不匹配 | 拒绝响应 | INV-PAY-001 | `closeRejectsResponseWithWrongPlatformPublicKeyId` | PASS |
| S04 | 响应时间戳超过五分钟 | 拒绝重放响应 | INV-PAY-001 | `createRejectsExpiredWechatResponse` | PASS |
| S05 | 平台公钥无法加载 | 调用微信前失败 | INV-PAY-001/002 | `createDoesNotCallWechatWhenPlatformPublicKeyCannotBeLoaded` | PASS |
| S06 | 查单/关单 | 与下单使用同一响应验证器 | INV-PAY-001 | `queryAcceptsVerifiedWechatResponse` + code review | PASS |
