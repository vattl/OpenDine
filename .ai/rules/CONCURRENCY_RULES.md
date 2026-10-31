# Concurrency Rules

## Purpose

Prevent duplicate work, race conditions, inconsistent state, queue explosions, and unsafe retries.

## Apply When Relevant

Analyze concurrency for:

- order/payment/refund/inventory mutations
- webhooks
- jobs and queue consumers
- repeated UI submissions
- polling / refresh loops
- shared caches or mutable state
- multi-step database writes
- distributed or multi-instance services

## Required Analysis

Consider:

- idempotency
- duplicate delivery / duplicate clicks
- race conditions
- transaction boundaries
- locking / optimistic concurrency
- ordering requirements
- max concurrency
- timeout behavior
- retry policy
- cancellation
- partial success

## Retry Rule

Retries must be bounded and intentional.

Avoid infinite or aggressive retry loops. Consider:

- max attempts
- exponential backoff / jitter
- retryable vs non-retryable errors
- idempotency before retrying writes
- circuit breaking for failing dependencies when justified

## Backpressure Rule

If producers can outpace consumers, define a bounded behavior:

- queue/concurrency limit
- batching
- delay
- reject/defer
- dead-letter handling
- degradation strategy

Do not allow silent unbounded backlog growth.

## Completion

A concurrent flow is not complete merely because the single-request happy path works.
