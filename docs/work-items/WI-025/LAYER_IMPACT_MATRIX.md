# Layer Impact Matrix — WI-025

| Layer | Impact | State |
|---|---|---|
| UI | None | NOT_APPLICABLE |
| API/controller | Existing admin checkout, cashier refund and daily precheck semantics tighten | IMPLEMENTED_VERIFIED |
| Domain/service | Ledger lifecycle, entry points and consistency gate | IMPLEMENTED_VERIFIED |
| Persistence | Existing immutable ledger schema reused | VERIFIED_UNAFFECTED |
| External WeChat | Transport/signature unchanged; refund settlement ordering fixed | IMPLEMENTED_VERIFIED |
| Reporting/reconciliation | Read-only behavior and business-day formulas | IMPLEMENTED_VERIFIED |
| External consumers | Same request/success shapes; must already display server errors | COMPATIBLE |
| Tests/docs/build | Scenario tests, API docs and runnable JAR | COMPLETE |

Material UNKNOWN count: 0
