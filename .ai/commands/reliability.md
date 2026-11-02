# /reliability

Perform a production-reliability audit for a feature, module, or active work item.

Input: `$ARGUMENTS`

## Workflow

SCOPE → FAILURE MODEL → RESOURCE LIFECYCLE → CONCURRENCY → BOUNDARIES → RECOVERY → OBSERVABILITY → LONGEVITY

## Required Questions

For the selected scope, determine:

1. What can accumulate over time?
2. What resources are created and how are they released?
3. Can work duplicate or overlap?
4. What happens when dependencies timeout/fail?
5. What happens after restart/reconnect?
6. What happens at data/load boundaries?
7. Is backlog/concurrency bounded?
8. Can operators diagnose failure?

## Risk Levels

LOW / MEDIUM / HIGH / CRITICAL

## Findings

Classify findings:

CRITICAL / HIGH / MEDIUM / LOW

CRITICAL/HIGH should block release when they can cause data corruption, sustained outage, unbounded resource exhaustion, or unsafe duplicate business actions.

## Output

# Reliability Report

Scope:
Runtime Risk:
Resource Lifecycle:
Concurrency:
Failure Paths:
Boundary Risks:
Long-Running Risks:
Observability:
Blocking Findings:
Recommended Fixes:
Release Recommendation:
