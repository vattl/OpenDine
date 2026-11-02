# Layer Impact Matrix — WI-008

| Layer | Status | Evidence / action |
|---|---|---|
| UI/frontend | NOT_APPLICABLE | No consumer repository in scope; handoff recorded |
| API contract | REQUIRED | Controller + OpenAPI + API.md |
| Authorization | REQUIRED | Conditional `admin:super` check |
| Service/domain | REQUIRED | Query behavior at existing controller owner |
| Persistence/schema | REQUIRED | Permission dictionary/grant migration; no order schema change |
| Jobs/events | NOT_APPLICABLE | Read-only endpoint |
| Tests | REQUIRED | Controller behavior/regression |
| Deployment | REQUIRED | Migration-before-JAR order |

Material UNKNOWN count: 0
