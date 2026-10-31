# Contract Delta — WI-059

## Additive fields
- Approval create requests: `bindingVersion` (1 or 2), `terminalId` required for v2.
- Approval responses/details: `bindingVersion`, `legacyBinding`.

## Semantic delta
V2 refuses placeholders and requires exact context binding. V1 remains compatibility-only and observable.

## Compatibility
No field removal or endpoint rename. Removal of v1 is out of scope.
