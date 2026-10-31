# Project Baseline Rules

The repository owns durable project knowledge so each agent does not rediscover the project from zero.

## Baseline artifacts
Human-readable:
- `docs/project/PROJECT_PROFILE.md`
- `docs/project/ARCHITECTURE_MAP.md`
- `docs/project/DESIGN_SYSTEM_PROFILE.md`
- `docs/project/BASELINE_HISTORY.md`

Machine-readable:
- `.ai/project/project-profile.json`
- `.ai/project/architecture-map.json`
- `.ai/project/design-system.json`
- `.ai/project/baseline-meta.json`

## Read strategy
Normal `/work`:
1. read baseline first
2. validate only relevant facts against current repository
3. inspect affected capability deeply
4. broaden discovery only if drift or uncertainty appears

## Baseline change levels
- LEVEL_0: normal bug/text/spacing/local field change; no baseline update
- LEVEL_1: shared component/module/pattern addition; targeted baseline update
- LEVEL_2: significant architecture/UI-system/navigation/pattern change; baseline review required after acceptance
- LEVEL_3: foundation migration; full rebaseline required

## Trust
Baseline is a cache of verified repository reality, not higher authority than code. Repository evidence wins when they disagree.
