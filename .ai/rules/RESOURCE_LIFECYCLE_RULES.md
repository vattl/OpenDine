# Resource Lifecycle Rules

## Purpose

Prevent memory leaks, orphaned async work, duplicate subscriptions, and long-running resource accumulation.

## Lifecycle Model

For every long-lived or externally managed resource, identify:

CREATE → OWN → USE → RELEASE

Examples:

- setInterval / setTimeout
- event listeners
- WebSocket / SSE
- Observer / Subscription
- Worker / Stream
- AbortController
- DB connections / transactions
- file handles
- background consumers
- Blob/Object URLs
- caches and buffers

## Mandatory Questions

1. Who creates the resource?
2. Who owns it?
3. What is its intended lifetime?
4. Can it be created more than once?
5. What happens on remount/reconnect/retry?
6. What cancels or releases it?
7. What happens when its owner exits or fails?
8. Can async work outlive the owner and write stale state?

## Rules

- Every listener/subscription must have a corresponding release path where the platform requires one.
- Reconnect logic must not create duplicate active resources.
- Polling must not create overlapping requests unless intentionally designed.
- Long-running resources should be observable enough to diagnose leaks when risk is material.
- Cleanup must be idempotent where repeated teardown is possible.
- Async operations that may outlive their owner should support cancellation/ignore-stale-result patterns when relevant.

## Memory Leak vs Unbounded Retention

Treat both as runtime defects:

- leaked resource: unreachable/obsolete work remains referenced or active
- unbounded retention: valid data remains intentionally referenced forever without a bound

## Completion Gate

For HIGH/CRITICAL runtime-risk tasks, resource lifecycle must be explicitly verified before DONE.
