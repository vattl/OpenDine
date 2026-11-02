# Scenario Matrix — WI-028

| ID | Scenario | Expected Business Outcome | Verification | Result |
|---|---|---|---|---|
| S01 | 超管获取版本列表 | 请求通过统一权限层并进入 Controller | mapping test + controller test | PASS |
| S02 | 超管保存版本策略 | POST 路由要求 `admin:super` | mapping test | PASS |
| S03 | 超管启停/删除策略 | 两个路由均要求 `admin:super` | mapping test | PASS |
| S04 | 非超管调用 | 统一权限层或 Controller 返回 403 | existing controller tests | PASS |
| S05 | 部署到既有库 | V030 幂等补齐映射且版本唯一 | migration inspection/check | PASS |

Material NOT_VERIFIED count: 0
