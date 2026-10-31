# Impact Map — WI-028

## Authoritative Owner

`ApiPermissionMapping` is the code fallback authority; `t_api_permission` is the runtime database authority. Both must agree.

## Layer Coverage

API authorization, database migration, tests, documentation and package verification are in scope.

## Authoritative affected surfaces

| Surface | Evidence | Planned change |
|---|---|---|
| Static authorization | `ApiPermissionMapping` lacks version management routes | add four `admin:super` mappings |
| Runtime DB authorization | V026 creates version tables but no management mappings | add corrective V030 seed |
| Controller | `AdminAppVersionController` already checks `admin:super` | preserve; no behavior relaxation |
| Tests | completeness test does not cover version management | add exact-route assertions |
| API contract | endpoints documented but runtime prerequisite incomplete | document corrected authorization registration |
| Packaging | API auth behavior changes | full regression + runnable JAR |

## Consumers

- Operations/admin frontend calling `/admin/app/versions` and version mutation endpoints.
- `SysInterceptor` resolving permissions from DB then built-in mapping.

## Excluded

- Public client update query semantics.
- UI changes.
- Production deployment.

Material UNKNOWN count: 0
