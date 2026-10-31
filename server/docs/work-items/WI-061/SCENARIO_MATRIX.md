# Scenario Matrix — WI-061

| ID | Family | Input / Context | Expected outcome | Invariant | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | permission | exact action `:approve` | onsite approval succeeds | INV-APPROVAL-001 | service test | PASS |
| S02 | permission | broad legacy permission only | 403 and audited | INV-APPROVAL-001 | policy/service test | PASS |
| S03 | permission | `admin:super` | permission passes, limits/credentials still apply | INV-APPROVAL-001 | service test | PASS |
| S04 | decision | QR AGREE and REJECT | identical action permission enforcement | INV-APPROVAL-001 | service test | PASS |
| S05 | request limit | below/at/above threshold | allow, then 429 with retry data | security | limiter test | PASS |
| S06 | multi-instance | two service objects share mapper/database row | combined attempts are enforced | security | shared-mapper service test + row-lock SQL | PASS |
| S07 | window | window/block expires | next attempt resets and succeeds | security | limiter state inspection | PASS |
| S08 | credential | five invalid PIN/password attempts | failure window blocks further verification | security | service/limiter test | PASS |
| S09 | credential | valid credential after prior failures | failure state cleared | security | service test | PASS |
| S10 | privacy | limiter/audit persistence | no raw account/PIN/password/token | security | unit + schema inspection | PASS |
| S11 | compatibility | existing success calls | path and success response shape unchanged | INV-APPROVAL-001 | 58 regressions + OpenAPI | PASS |
| S12 | migration | legacy approver/admin permissions | exact permissions additively backfilled; action-only roles excluded | security | SQL inspection/package | PASS |
| S13 | polling | QR status every two seconds | not rate limited | availability | service regression | PASS |
| S14 | migration recovery | empty/legacy/partially migrated approval schema | V043 idempotently converges required approval tables/columns without dropping data | INV-APPROVAL-001 | migration contract + packaged resource inspection | PASS |
