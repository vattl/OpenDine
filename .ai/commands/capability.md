# /capability — Discover a Business Capability Surface

Input: `$ARGUMENTS`

Read-only unless explicitly asked to persist the map.

## Purpose

Map where a business capability actually lives before a shared change/repair.

## Output

- capability name
- authoritative owner candidate(s)
- direct and indirect consumers
- upstream/downstream dependencies
- contracts/interfaces
- duplicate logic candidates
- related tests
- confidence and unknowns

Use symbol search plus semantic/business-term search. Do not infer a complete graph from a single file.
