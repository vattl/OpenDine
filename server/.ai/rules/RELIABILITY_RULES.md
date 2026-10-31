# Reliability Rules

## Purpose

Ensure features remain safe during failure, restart, prolonged operation, and dependency degradation.

## Core Questions

For runtime-relevant work ask:

- If this runs for hours/days, what accumulates?
- If an upstream dependency fails for 30 minutes, what happens?
- If traffic/load becomes 10x, what fails first?
- If the process restarts mid-operation, what state is lost?
- If the same event arrives twice, what happens?
- If only part of a multi-step operation succeeds, how is consistency restored?

## Failure Modes

Design intentional behavior for relevant cases:

SUCCESS
FAILURE
TIMEOUT
PARTIAL_SUCCESS
DUPLICATE
CANCELLED
DISCONNECTED
RECONNECTED
RESTARTED
OVERLOADED

## Graceful Degradation

Prefer controlled degradation over cascading failure when practical.

Examples:

- cap concurrency
- queue bounded work
- fall back to safe read-only behavior
- preserve confirmed business state when downstream side effects fail
- surface operational alerts rather than silently discarding work

## Soak/Longevity Testing

Use soak tests when long-running behavior is a material risk, especially for:

- servers
- KDS / always-on screens
- Electron/desktop apps
- workers/consumers
- WebSocket/SSE
- polling loops
- streaming
- resource-intensive background processing

Do not require arbitrary long tests for low-risk code. Duration should be enough to reveal the suspected failure mode.
