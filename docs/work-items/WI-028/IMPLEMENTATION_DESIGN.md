# Implementation Design — WI-028

## Root Fix / Owner

Repair the shared authorization capability at its two owners: built-in `ApiPermissionMapping` and runtime `t_api_permission` migration data.

## Design

1. Register exact routes in `ApiPermissionMapping` with `admin:super`.
2. Add V030 as an idempotent corrective migration for `t_api_permission`; do not alter V026.
3. Use exact path patterns because the table is path-unique and authorization is intentionally strict.
4. Keep Controller-level `admin:super` checks as defense in depth.
5. Extend completeness tests for all four routes and preserve similar-prefix rejection.
6. Synchronize `docs/API.md` and `docs/openapi.yaml`.

## Migration compatibility

- Insert/update by unique `path_pattern` using `ON DUPLICATE KEY UPDATE`.
- Use method `*` because the schema permits one row per path; each path currently has only one management method.
- Safe for existing databases and fresh installs.

## Contract impact

Provider auth repair only. Successful response schema and request fields do not change. Previously blocked super-admin calls now reach the documented Controller behavior.

## Rollback

Application rollback restores failure-closed behavior. Migration rows may remain because older versions ignore unmatched routes; no destructive schema change is introduced.

## Verification Strategy

- RED/GREEN permission mapping regression assertions for all four routes.
- Existing Controller tests for super/non-super behavior.
- Migration uniqueness and SQL inspection.
- OpenAPI parsing, full Maven tests, and mandatory clean package.
