# /baseline — Build or Show Project Baseline

Use when initializing a repository, when the baseline is missing, or when the user asks to inspect project fundamentals.

## Goal
Create/update the persistent project knowledge that normal Work Items can reuse without rescanning the whole repository.

## Outputs
- `docs/project/PROJECT_PROFILE.md`
- `docs/project/ARCHITECTURE_MAP.md`
- `docs/project/DESIGN_SYSTEM_PROFILE.md`
- `.ai/project/project-profile.json`
- `.ai/project/architecture-map.json`
- `.ai/project/design-system.json`
- `.ai/project/baseline-meta.json`

## Procedure
1. Inspect repository manifests, entry points, build/runtime config and representative UI/backend modules.
2. Record only verified facts.
3. Identify current design language from real production UI, not screenshots alone.
4. Assign Project Baseline version `PB-n` and Design System version `DS-n`.
5. Record evidence paths and last-verified areas.

Do not turn temporary experimental code into baseline policy.
