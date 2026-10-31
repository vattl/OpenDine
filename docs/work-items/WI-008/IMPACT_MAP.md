# Impact Map — WI-008

## Authoritative Owner

`CashierOrderController.today` 是账单列表查询语义所有者；`SysInterceptor` 与 `IAdminPermissionService` 是认证及权限事实来源。

## Layer Coverage

| Surface | Evidence | Impact | Planned action |
|---|---|---|---|
| API provider | `CashierOrderController.today` | Default and custom time semantics | Modify controller boundary/query |
| AuthN/AuthZ | `SysInterceptor`, `IAdminPermissionService` | Conditional elevated permission | Reuse authenticated admin ID and exact permission set |
| Tenant isolation | `AdminShopRequest` | Must remain current-shop only | Preserve resolved shop checks |
| Persistence | `IOrderService` / MyBatis-Plus wrapper | Query predicate changes only | Parameterized wrapper conditions |
| Permission data | `t_permission`, `t_role_permission` | New `admin:super` code | Idempotent migration, grant only `super_admin` |
| Consumers | Cashier clients calling `/cashier/order/today` | Default result window narrows; optional new params | Backward-compatible request shape; handoff documented |
| API docs | `docs/openapi.yaml`, `docs/API.md` | Contract change | Synchronize before acceptance |
| Tests | `CashierOrderControllerTest` | Existing 24h expectation obsolete | RED/GREEN behavior tests |
| UI | none in this repository/request | NONE | UI gate N/A |
| KDS | no KDS auth/API/data path touched | NONE | KDS architecture reading not required |

Material UNKNOWN count: 0
