# Impact Map Authority Rules

The Work Item Impact Map is the authoritative record of affected engineering surfaces for that Work Item.

## Principle

Discover once, refine when evidence changes, and reuse downstream. Do not independently reinvent scope in DESIGN, PLAN, SELF_VERIFY, REVIEW or ACCEPT.

## Lifecycle

- DISCOVER creates the Impact Map.
- DESIGN consumes it and may propose refinements.
- IMPLEMENT updates it only when repository evidence reveals new impact.
- SELF_VERIFY derives checks from it.
- REVIEW challenges it for omissions.
- ACCEPT requires all material surfaces to be resolved.

## Status vocabulary

Each relevant surface must be one of:
- `AFFECTED`
- `VERIFIED_UNAFFECTED`
- `NOT_APPLICABLE`
- `UNKNOWN`

Material `UNKNOWN` blocks `IMPLEMENTATION_READY` and `ACCEPT`.
