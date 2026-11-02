# Layer Impact Matrix

Task: WI-023
Capability: accounts-receivable
Authoritative owner: `com.lanf.receivable`

| Layer | Relevant | Action | Planned change/check | Evidence | Status |
|---|---:|---|---|---|---|
| UI | NO | NOT_APPLICABLE | 外部仓库，提供 handoff | API_CONSUMER_HANDOFF.md | NOT_APPLICABLE |
| Interaction | YES | CHANGE | 挂账/回款/撤销/坏账语义 | CONTRACT_DELTA.md | CHANGE |
| Frontend State | YES | CHANGE | 账户与应收状态 | API_CONSUMER_HANDOFF.md | CHANGE |
| API Client | YES | CHANGE | 新增资源端点 | openapi + handoff | CHANGE |
| Request Contract | YES | CHANGE | DTO/幂等/分页 | CONTRACT_DELTA.md | CHANGE |
| Controller/Handler | YES | CHANGE | admin/cashier controllers | implementation design | CHANGE |
| Service/Domain | YES | CHANGE | ReceivableService | implementation design | CHANGE |
| Persistence/DB | YES | CHANGE | V025 migration | implementation design | CHANGE |
| Response Contract | YES | CHANGE | 资源与日结摘要 | CONTRACT_DELTA.md | CHANGE |
| Frontend Mapping | YES | CHANGE | consumer-owned | API_CONSUMER_HANDOFF.md | CHANGE |
| UI Display | YES | CHANGE | consumer-owned | API_CONSUMER_HANDOFF.md | CHANGE |
| Tests/Regression | YES | CHANGE | 15 scenarios + full suite | SCENARIO_MATRIX.md | CHANGE |

UNKNOWN count: 0
Completion allowed: NO
