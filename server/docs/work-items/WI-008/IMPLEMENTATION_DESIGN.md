# Implementation Design — WI-008

## Root Fix / Owner

`CashierOrderController.today` owns this read contract. Authentication and base route authorization remain in `SysInterceptor`; the controller performs the conditional `admin:super` check because elevation depends on optional query parameters rather than the route alone.

## Contract

- Add optional `startTime` and `endTime` query parameters.
- No custom input: `shop_id = currentShop AND (transac_status = unsettled OR order_time >= now-3h)`.
- Explicit range: `shop_id = currentShop AND order_time >= start AND order_time <= end`.
- Existing `transac_status` remains an additional filter.
- `date` is retained as a super-only compatibility alias for an operational 24-hour window.

## Validation and security

- Any of `startTime`, `endTime`, or `date` marks the request as custom.
- Custom requests require current admin ID plus exact permission code `admin:super`; failure closes with 403 before DB access.
- `startTime/endTime` must appear together, cannot mix with `date`, must parse, be ordered, and span at most 31 days.
- Query construction remains parameterized through MyBatis-Plus.
- Current resolved shop remains mandatory and request `shopId` cannot select another store.

## Permission migration

Register `admin:super` in `t_permission` and grant it only to `t_role.role_code='super_admin'`. Migration is idempotent and must run before deploying the JAR.

## Compatibility

Response shape is unchanged. Ordinary clients need no request change but will intentionally see a narrower default dataset. Clients needing older bills must expose the optional range only when their session permissions contain `admin:super`.

## Verification Strategy

Controller tests inspect generated predicates and prove fail-closed behavior. Run targeted tests, full Maven suite, OpenAPI parse, acceptance gate, and mandatory clean package.
