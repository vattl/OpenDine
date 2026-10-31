# Layer Impact Matrix — WI-024

| Layer | Impact | State |
|---|---|---|
| Mini program consumer | Handle new conflict and refresh; success shape compatible | HANDOFF_PENDING |
| API/controller | Existing prepay behavior tightened, additive metadata | IMPLEMENTED_VERIFIED |
| Domain/service | Durable JSAPI attempt owner and mutation guard | IMPLEMENTED_VERIFIED |
| External WeChat | JSAPI create/query/close through API v3 client | IMPLEMENTED_VERIFIED |
| Persistence | Additive V026 attempt table | IMPLEMENTED_NOT_MIGRATED |
| Callback | Exact attempt, amount, trade type, payer and transaction matching | IMPLEMENTED_VERIFIED |
| Reporting/ledger | Authoritative ledger written before order settlement; exact idempotency and conflicting settlement rejection | IMPLEMENTED_VERIFIED |
| Tests/build/docs | Tests, API docs, migration and runnable JAR | COMPLETE |
