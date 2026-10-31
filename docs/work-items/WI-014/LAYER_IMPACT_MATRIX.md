# Layer Impact Matrix — WI-014

| Layer | Status | Planned handling |
|---|---|---|
| UI | NOT_APPLICABLE | no production UI change |
| API request | AFFECTED | add void-stale-takeout-orders endpoint & params |
| Security | AFFECTED | map daily:settle / order:operate permission |
| Domain/Service | AFFECTED | precheck detection & atomic voiding with side effects |
| Persistence | VERIFIED_UNAFFECTED | no schema changes |
| Tests/build | AFFECTED | full test and package verification |

Material UNKNOWN count: 0
