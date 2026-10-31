# Layer Impact Matrix — WI-063

| Layer | Provider change | Consumer obligation | Status |
|---|---|---|---|
| API | 高风险失败响应输出三态 | 前端按 outcome 分流 | HANDOFF |
| Security | 共享动作授权门面 | Controller 不再拼接校验 | MAPPED |
| Persistence | V042 精确角色授权 | 部署先迁移后发版 | MAPPED |
| Business | 仅增加前置授权 | 保持金额/状态规则 | MAPPED |
| Flutter/admin | 无本仓代码修改 | 精确 permission + v2 binding | HANDOFF |
| Tests | 门面、接线、SQL 契约 | 持续防跨动作扩散 | MAPPED |

UNKNOWN count: 0
