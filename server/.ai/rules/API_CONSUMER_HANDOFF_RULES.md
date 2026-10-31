# API Consumer Handoff Rules

Backend/interface changes must not strand consumers.

## Trigger

Create/update consumer migration guidance when any of these materially change:
- request field added/removed/renamed/type/requiredness/default
- response field/shape/type/meaning
- route/method/query semantics
- enum/state semantics
- pagination/sort/filter contract
- auth/permission requirement
- error codes/behavior
- event/webhook/message contract

## Required outcome

Either:
1. all affected consumers are updated and verified in the same Work Item, or
2. create an `API_CONSUMER_HANDOFF` and keep the Work Item PARTIAL / consumer-pending as appropriate.

## Handoff must include

- interface and endpoint
- before/after contract
- compatibility: NON_BREAKING / ACTION_REQUIRED / BREAKING
- exact affected consumers/files when known
- frontend type/model changes
- request construction changes
- response mapping/display changes
- UI/interaction implications
- example request/response/call
- default/fallback behavior
- migration/rollout order
- verification checklist

Never silently call backend-only work fully complete when a required consumer is known stale.

## v4.1 bidirectional extension

This legacy rule is the backend→consumer half of `CONTRACT_COLLABORATION_RULES.md`. Frontend-originated capability needs use `BACKEND_CAPABILITY_REQUEST.md`. Prefer the unified collaboration rule for new Work Items.
