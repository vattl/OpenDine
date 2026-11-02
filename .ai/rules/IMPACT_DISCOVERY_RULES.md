# Impact Discovery Rules

Consolidates capability mapping, consumer coverage, cross-layer consistency and contract impact into one discovery pass.

## Discover the capability, not only the named file

Search for:
- authoritative owner
- duplicate implementations of the same business rule
- direct/indirect consumers
- semantic equivalents, not only symbol references
- request and response propagation
- UI semantic meaning
- scheduled/event-driven consumers

## Layer classification

Each potentially relevant layer is classified as:
- AFFECTED
- VERIFIED_UNAFFECTED
- NOT_APPLICABLE
- UNKNOWN

Material UNKNOWN blocks acceptance.

## Public/shared contract trigger

Changes to public/shared APIs, DTOs, events, enums, config, shared components, state models or database semantics require consumer discovery.

## Central fix preference

If multiple consumers depend on one rule, prefer fixing the authoritative owner over caller-specific patches.
