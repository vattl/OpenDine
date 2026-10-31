# Contract Handoff — APPROVAL-BINDING-V2

- Work Item: WI-059
- Origin layer: server
- Target layer: Flutter cashier/admin client
- Status: READY_FOR_CLIENT_ADOPTION
- Business goal: bind every sensitive approval to the exact attempted operation.

## Current Capability
Client may omit terminal and use placeholder business IDs; server treats it as v1 legacy binding.

## Required Capability
Send `bindingVersion: 2`, `terminalId`, canonical resource type (`ORDER` for order operations), exact non-placeholder `bizId`, and the exact operation amount or omit amount consistently for non-monetary actions. Reuse the same values and `X-Terminal-Id` when retrying with `approvalToken`.

## Contract Delta
See `CONTRACT_DELTA.md` and updated OpenAPI.

## Affected Consumers / Providers
Flutter `access_approval_repository.dart`, approval dialog callers, and sensitive operation repositories.

## Implementation Guidance
Use the authenticated terminal's stable ID. Never derive `bizId` from display text. For bills, use `orderNo`; if absent, refresh the bill before requesting v2 approval.

## Compatibility / Migration
Omitting `bindingVersion` remains v1 temporarily and returns `legacyBinding: true`. Client adoption must be measured before WI-061 enforces v2.

## Examples
`{"bindingVersion":2,"terminalId":"POS-01","permission":"order:operate:refund","bizType":"ORDER","bizId":"ORD-123","amount":88.00}`

## Verification
Client contract tests must prove the approval request and retried sensitive request use identical context.
