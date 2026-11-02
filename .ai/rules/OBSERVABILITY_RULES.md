# Observability Rules

## Purpose

Make runtime failures diagnosable without excessive logging or secret exposure.

## Apply Proportionally

For important runtime flows, consider whether operators can answer:

- Is the system healthy?
- Where is latency occurring?
- Are queues/backlogs growing?
- Are retries/failures increasing?
- Is memory/CPU trending upward?
- Which external dependency is failing?

## Signals

Use only where useful:

- structured logs
- metrics
- error tracking
- traces
- queue depth
- retry counts
- memory/handle counts
- rate/latency metrics

## Logging Rules

- Do not log secrets or sensitive payloads unnecessarily.
- Avoid high-frequency logs that can become their own performance problem.
- Prefer actionable context over noisy repetition.
- Correlation/request IDs are useful for distributed or multi-step flows.

## Completion

Critical failure modes should be observable enough to investigate when they occur.
