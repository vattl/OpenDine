# /rebaseline — Rebuild Project Baseline After Foundation Change

Use after intentional, accepted foundation changes such as framework migration, major state-management migration, architecture restructuring, API paradigm replacement, or product-wide design-system replacement.

Prerequisites:
- the foundation change is accepted or explicitly approved
- repository is in a stable state suitable for re-discovery

Produce new `PB-n` and/or `DS-n`, update baseline history, and mark prior versions superseded rather than silently rewriting history.
