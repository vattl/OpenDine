# Layer Impact Matrix — WI-015

| Layer | Status | Planned handling |
|---|---|---|
| UI | NOT_APPLICABLE | Backend repository only; explicit cashier consumer handoff. |
| API request/response | AFFECTED | Add Native create/status/close endpoints; amount remains server-owned. |
| Cashier consumer | AFFECTED | Follow-up implementation described in `API_CONSUMER_HANDOFF.md`. |
| Security | AFFECTED | Cashier permission, shop scope, signed WeChat boundary and exact payload validation. |
| Domain/service | AFFECTED | Durable attempts and shared idempotent payment confirmation. |
| Persistence | AFFECTED | Add forward-only Native attempt migration/table. |
| WeChat integration | AFFECTED | Native create/query/close APIv3 calls. |
| Existing JSAPI/refund | VERIFIED_UNAFFECTED | Preserve contracts; run regression tests and reuse refund owner. |
| Ledger/reconciliation | AFFECTED | Confirm WECHAT ledger and existing statement matching remain intact. |
| Tests/build/docs | AFFECTED | Scenario coverage, OpenAPI/API sync and mandatory JAR package. |

Material UNKNOWN count: 0
