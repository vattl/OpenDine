# Layer Impact Matrix — WI-064

| Layer | Provider change | Consumer obligation | Status |
|---|---|---|---|
| API | expectedVersion、revision、409 conflict | 刷新而非盲重试 | HANDOFF |
| Controller | 五个入口接入共享守卫 | 无分散版本逻辑 | MAPPED |
| Persistence | 现有 revision 原子 +1 | 无 schema 变更 | MAPPED |
| Approval | 冲突先于 token 核销 | 继续使用 WI-063 三态 | MAPPED |
| KDS | POS 加菜去除重复 t_order bump | command_id/局部版本不变 | MAPPED |
| UI | 本仓无生产 UI | 外部客户端按 handoff 实施 | HANDOFF |

UNKNOWN count: 0
