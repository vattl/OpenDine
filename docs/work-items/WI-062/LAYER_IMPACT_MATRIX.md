# Layer Impact Matrix — WI-062

| Layer | Provider change | Consumer obligation | Status |
|---|---|---|---|
| API | evaluate 新增 outcome | 客户端逐步改用三态 | HANDOFF |
| Domain | 决策和词汇统一 | WI-063 复用，不重复实现 | MAPPED |
| Persistence | DB 映射为唯一权威 | 部署必须完成迁移/初始化 | MAPPED |
| Security | 映射缺失失败关闭 | 监控 permission_mapping_missing | MAPPED |
| Flutter | 无本仓代码修改 | 三态驱动授权交互 | HANDOFF |
| Tests/CI | 映射差异门禁 | 变更映射时同步清单与 SQL | MAPPED |

UNKNOWN count: 0

