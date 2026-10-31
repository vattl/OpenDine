# Performance Rules

## Purpose

Prevent feature-complete code from becoming production-unsafe under realistic load, scale, or long-running operation.

## Core Principle

A feature that works only under ideal conditions is not complete when realistic runtime conditions can make it degrade, stall, exhaust resources, or amplify load.

## Risk-Adaptive Use

Do not benchmark every trivial change. Performance analysis becomes mandatory when work introduces or materially changes:

- polling, WebSocket, SSE, workers, timers, observers, subscriptions
- background jobs, queues, batch processing, retries
- high-frequency API calls or rendering loops
- database queries over growing data sets
- caches, buffers, histories, in-memory collections
- file/stream processing
- CPU-heavy or memory-heavy work
- critical user flows where latency materially affects operations

## Performance Questions

For relevant work, answer:

1. What is the expected steady-state load?
2. What grows with users, requests, rows, events, or time?
3. What is the computational complexity on the hot path?
4. Are requests or jobs bounded and concurrency-limited?
5. Can retries amplify failure?
6. Are list/query operations paginated and indexed?
7. Are expensive computations repeated unnecessarily?
8. Is there a measurable budget or acceptance target?

## Required Checks

Consider as applicable:

- request rate and duplicate requests
- overlapping polling/fetches
- p50/p95/p99 latency
- query count and N+1 behavior
- full-table scans / unbounded SELECTs
- render count and large-list rendering
- CPU utilization
- heap/RSS trend
- queue depth
- active handles/timers
- network payload size

## Unbounded Growth Rule

Any collection that can grow over time must have an explicit bound, eviction/retention rule, backpressure policy, or persistence strategy.

Examples:

- Array / Map / Set
- cache
- history
- log buffer
- pending promises/jobs
- retry queue
- event buffer

## Performance Budget

Use `docs/PERFORMANCE_BUDGET.md` when performance is material. The budget is a project target, not a universal constant.

Do not invent numeric limits without project context. When no budget exists, establish a reasonable measurement baseline and record assumptions.

## Completion

Relevant performance work is complete only when material risks are either:

- measured and acceptable,
- bounded by design,
- mitigated,
- or explicitly documented as accepted limitations.
