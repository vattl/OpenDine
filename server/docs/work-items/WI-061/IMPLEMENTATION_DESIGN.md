# Implementation Design — WI-061

## Root Fix / Owner
Introduce an exact approval-permission policy and a database-backed `ApprovalRateLimitService`. `ApprovalService` remains the only approval workflow owner; controllers remain transport adapters.

## End-to-End Change
### Backend
Derive required permission as `<requested permission>:approve`, with only `admin:super` bypass. Enforce it for onsite approval and both QR decisions. Protect request entry points with fixed-window counters and protect credential verification with failure-only windows keyed by SHA-256 of normalized account.

### Frontend
No production frontend edit in this repository. Consumers must handle structured 429 and assign/display new permissions. Binding v2 adoption is documented as the next compatibility requirement.

### UI / Interaction
No UI file is edited; HTML prototype is NOT_APPLICABLE. Consumer guidance specifies countdown and disabled retry behavior without claiming it is implemented.

### Data / Persistence
V040 creates `t_access_approval_rate_limit`, seeds three known action approval permissions, and additively maps roles from matching action permissions and established legacy approver permissions.

生产缺陷回补使用更高版本 V043，不修改可能已执行的 V020/V037/V038/V040。V043 在空库、旧表和部分迁移三种状态下幂等创建/补齐 `t_access_approval` 的 `binding_version`、`token_value` 及 `t_access_approval_rate_limit`，重放精确审批权限与既有管理角色加法授权；同一最新结构同步进入全量建库和增量同步基线。

### Interfaces / Contracts
Add error contract: HTTP 429, code `ACCESS_APPROVAL_RATE_LIMITED`, data `{retryAfterSeconds, rateLimitScope}`. Success contracts remain stable.

## Permission Model
- Canonical permissions: `order:operate:refund:approve`, `order:operate:changePrice:approve`, `order:operate:discount:approve`.
- Requested action permission is normalized and the exact suffix is required.
- `admin:super` is the only bypass; broad `access:approve`, `refund:approve`, `order:operate` and `admin:manage` are not runtime substitutes.
- AGREE and REJECT require identical authorization.

## Rate-Limit Model
- `ONSITE_AUTHORIZE`: 10 attempts / 60 seconds, block 300 seconds.
- `QR_CREATE`: 10 attempts / 60 seconds, block 300 seconds.
- `QR_CONFIRM`: 20 attempts / 60 seconds, block 300 seconds.
- `CREDENTIAL_FAILURE`: 5 failures / 900 seconds, block 900 seconds; success clears the row.
- Rows use stable hashed composite keys; raw account, credential and token never enter the table.
- Transactional `SELECT ... FOR UPDATE` makes counters consistent across service instances.
- Status polling is deliberately excluded.

## Audit
Permission denial, operational throttling, credential throttling and invalid credential are recorded with explicit HTTP result code and non-sensitive identifiers.

## Failure / Boundary Behavior
Blocked requests return the ceiling of remaining seconds with a minimum of one. Expired windows reset atomically. Unknown action permissions still derive an exact approval permission and fail unless explicitly assigned. Database failure fails closed for protected mutations.

## Runtime / Performance / Reliability
One short transaction and a single keyed row lock are added per protected mutation. Stable keys cap row growth by actor/shop/scope. A cleanup query may be added operationally later without affecting correctness.

## Security / Permissions
Super admin does not bypass throttling or credentials. Constant-time password/PIN check behavior remains owned by existing encoders. No secret is logged or returned in audit metadata.

## UI Design Track
NOT_APPLICABLE: no production UI is modified. Cross-repository client behavior is handled through contract handoff.

## Vertical Slice Plan
1. Add RED tests for exact permissions, symmetric decisions and rate-limit state transitions.
2. Implement mapper/entity/service and ApprovalService integration.
3. Add V040 migration and audit support.
4. Synchronize OpenAPI/API docs and frontend handoff.
5. Run focused/full verification, review and gates.
6. Add a RED migration-convergence contract, implement V043 and synchronize install baselines.

## Verification Strategy
Unit tests cover permission derivation, broad-permission rejection, super-admin path, AGREE/REJECT parity, fixed-window reset/block/retry, failure-only reset, key hashing and no secret leakage. Existing approval regression tests and mandatory clean package run afterward.

## Rollback / Recovery
Application rollback can ignore the additive table and permissions. Do not remove seeded permissions until role usage is audited. Rate-limit rows contain no business records and may expire naturally.
