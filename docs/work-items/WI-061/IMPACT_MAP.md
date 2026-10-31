# Impact Map — WI-061

## Authoritative Owner
`ApprovalService` 负责审批决策与凭据流程；`ApprovalRateLimitService` 负责数据库权威的请求/失败窗口；权限表负责动作级审批授权。

## Change Propagation Path
```text
cashier / manager request
→ exact approval permission policy
→ durable rate-limit window
→ credential verification (onsite only)
→ approval state transition / grant
→ security audit
→ standardized success or 429/403 response
```

## Consumer Coverage
| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| Flutter cashier | onsite authorize, QR create/status | AFFECTED | RECOMMENDED | handle 429; send binding v2 and terminal identity |
| Flutter/admin approver | QR confirm | AFFECTED | YES | role must own exact `:approve`; handle 429/403 |
| Backend instances | shared throttling | AFFECTED | YES | database row locking is authority |
| Database/Flyway | permissions and limiter state | AFFECTED | YES | V040 migration；缺失/部分迁移环境由 V043 收敛 |
| Operations | monitor abuse/rejections | AFFECTED | YES | audit event semantics documented |

## Layer Coverage
| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | server repository has no production UI edit |
| Interaction | AFFECTED | retry must respect `retryAfterSeconds` |
| Frontend State | AFFECTED | countdown/disabled retry recommended |
| API Client | AFFECTED | parse 429 data; v2 binding handoff |
| Request Contract | VERIFIED_COMPATIBLE | no required field added in WI-061 |
| Backend/Domain | AFFECTED | exact permission and throttling |
| Persistence | AFFECTED | permission seeds, role mapping and limiter table |
| Response Contract | AFFECTED | new 429 error code/data and 403 semantics |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | none |
| Config/Security | AFFECTED | fixed security thresholds and audit |
| Runtime/NFR | AFFECTED | transactional row lock per protected attempt |
| Tests | AFFECTED | service, policy, limiter and contract tests |

## Duplicate Logic / Patch Smells
Controllers do not duplicate permission aliases or counters. Permission derivation and limiter state transitions each have one owner.

## Contract Delta Summary
Success schemas and paths are unchanged. A new structured HTTP 429 failure is added; QR rejection now requires the same action-level approval permission as agreement.

## UI Semantic Impact
No server UI edit. Frontend behavior changes are an explicit cross-repository handoff, not silently assumed.

## Risks
- Incorrect role backfill could remove operational capability; migration is additive and maps existing action permissions.
- Attacker-driven account throttling is possible; keys are scoped by shop and normalized account hash, window is bounded, and operator request throttling is separate.
- Database contention is bounded to one actor/scope row and does not affect status polling.
- 若部署环境跳过 V020/V037/V038/V040 中任一审批结构迁移，ORM 写入可能直接产生 500；V043 必须可在完整或部分结构上重复执行并收敛到最新字段集合。
