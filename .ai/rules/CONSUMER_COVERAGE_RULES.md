# v4.0 Integration

Consumer coverage is recorded primarily in the Work Item IMPACT_MAP. Material UNKNOWN consumers block acceptance.


---

# Consumer Coverage Rules

## Trigger

Apply when changing a shared:

- service method/domain rule
- API/DTO/schema
- DB field/enum/constraint
- event/queue/websocket message
- shared component/hook/utility
- configuration semantics
- date/time/business-window calculation

## Required Actions

1. Find definitions/implementations.
2. Find direct references/callers.
3. Search semantic equivalents/duplicated logic.
4. Identify indirect consumers where material.
5. Classify every known consumer.
6. Verify affected consumers proportionally to risk.

## Coverage Summary

Record:

- consumers found
- consumers reviewed
- consumers changed
- consumers regression-tested
- consumers unknown

For material shared changes, `reviewed == found` is the default expectation.
