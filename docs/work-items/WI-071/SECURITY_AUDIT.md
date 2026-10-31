# Security Audit — WI-071

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: PASS
SAST: PASS

## 1. 审计范围
本次审计针对会员注册统一默认昵称及用户资料修改接口的安全性、防篡改性与越权风险进行全面评估。

## 2. 检查项与审计结论

| 检查项 | 风险等级 | 防护实现 | 审计结论 |
|---|---|---|---|
| **昵称恶意重置/覆盖漏洞** | HIGH | 严格限制默认昵称 `老肥吃货{id}` 仅在新用户初次插入落库时触发；微信二次登录、手机号绑定等日常业务操作只更新必要会话或手机字段，严禁触碰 `name` 字段。 | PASS |
| **越权篡改他人资料** | MEDIUM | `/order/updateUser` 与 `/order/updateAvatar` 强绑定 `openid`，经由统一拦截器 `UserIdentityInterceptor` 与身份守卫核验，无法伪造 openid 修改他人昵称。 | PASS |
| **XSS 与特殊字符注入** | LOW | 实体类与修改服务进行 `.trim()` 处理，数据库持久化使用预编译参数化 SQL（MyBatis-Plus），杜绝 SQL 注入；前端与小程序采用标准文本转义展示。 | PASS |
| **敏感信息泄露** | LOW | `/order/getUserInfo` 及修改接口仅返回用户自身公开信息，不输出数据库底层敏感凭据（如 session_key、密码等）。 | PASS |

## 3. 自动化用例验证
- `UserRegistrationNicknameTest.testBindPhone_DoesNotOverwriteExistingNickname`：验证手机号绑定不覆盖已有昵称；
- `UserRegistrationNicknameTest.testNewUserRegistration_ExplicitNicknamePreserved`：验证显式传入昵称不被重置；
- `UserRegistrationNicknameTest.testUpdateUser_ModifiesNickname`：验证用户修改自身昵称安全生效。
