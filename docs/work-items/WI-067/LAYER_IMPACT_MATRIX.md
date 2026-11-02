# Layer Impact Matrix — WI-067

| Layer | Impact | Action | Evidence |
|---|---|---|---|
| Backend service | YES | implement authoritative close sequence and transaction guard | `IMPLEMENTATION_DESIGN.md` |
| Controller/API | YES | additive context fields and structured 409 | `CONTRACT_DELTA.md` |
| Persistence | YES | query latest snapshot, reuse reopened row, preserve unique key | V016 schema + design |
| Documentation | YES | sync OpenAPI and API.md | acceptance checklist |
| Tests | YES | TDD sequence/window/reopen/concurrency coverage | `SCENARIO_MATRIX.md` |
| Production UI | NO | explicit backend-only scope | user instruction 2026-10-25 |
| External consumer | HANDOFF | no code edit; migration documented | `API_CONSUMER_HANDOFF.md` |

UNKNOWN count: 0
