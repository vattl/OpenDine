# Layer Impact Matrix — WI-068

| Layer | Impact | Action | Evidence |
|---|---|---|---|
| Backend service | YES | 连续营业日列表和状态映射 | `IMPLEMENTATION_DESIGN.md` |
| Controller/API | YES | 响应契约语义扩展 | `CONTRACT_DELTA.md` |
| Persistence | YES | 日期窗口快照读取，无 schema 变更 | `IMPACT_MAP.md` |
| Documentation | YES | 同步 OpenAPI/API.md | acceptance checklist |
| Tests | YES | 连续性、状态、分页、兼容测试 | `SCENARIO_MATRIX.md` |
| Production UI | NO | 用户明确仅后端 | request |
| External consumer | HANDOFF | 点击规则和游标迁移 | `API_CONSUMER_HANDOFF.md` |

UNKNOWN count: 0
