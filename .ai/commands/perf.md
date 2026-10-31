# /perf

Assess and, when requested, improve performance and runtime resource behavior for a defined scope.

Input: `$ARGUMENTS`

## Scope

If unspecified, use current active work from PROJECT_STATE.

## Workflow

SCOPE → RUNTIME RISK → HOT PATHS → RESOURCE/LATENCY BASELINE → BOTTLENECKS → TARGETED FIX → MEASURE AGAIN

## Inspect

As relevant:

- CPU / expensive loops
- memory / heap / RSS trend
- active timers/listeners/handles
- render churn
- repeated/overlapping network calls
- payload size
- database query count / indexes / pagination
- cache growth
- queue depth / worker concurrency
- retry amplification

## Rules

- Measure when tools are available; do not claim speedups without evidence.
- Avoid broad rewrites solely for theoretical micro-optimization.
- Fix the highest material bottleneck first.
- Preserve correctness while optimizing.
- Use `docs/PERFORMANCE_BUDGET.md` when present.

## Output

# Performance Report

Scope:
Runtime Risk:
Baseline:
Findings:
Changes:
Verification:
Remaining Risks:
Budget Status:
