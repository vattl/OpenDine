# Contract Handoff — APPROVAL-PERMISSION-RATE-LIMIT

- Work Item: WI-061
- Origin layer: server
- Target layer: Flutter cashier/admin and role administration
- Status: READY_FOR_CONSUMER_IMPLEMENTATION
- Business goal: exact approval authority and bounded abuse behavior.

## Current Capability
Clients submit a business action permission and receive onsite grants or poll QR approval. Existing Flutter code does not parse limiter data and still omits binding v2/terminal identity.

## Required Capability
Handle `ACCESS_APPROVAL_RATE_LIMITED` using `retryAfterSeconds`; display/assign exact `:approve` permissions; send `bindingVersion=2` and a stable terminal identity for strict contextual binding.

## Contract Delta
Success shapes are unchanged. New 429 data and stricter 403 semantics are documented in OpenAPI/API.md.

## Affected Consumers / Providers
Flutter access approval repository/models/dialog, API error presentation, permission labels/role editor and relevant tests.

## Compatibility / Migration
Backend permission migration preserves established roles additively. Binding v1 remains temporarily accepted until consumer v2 evidence exists; this is a migration window, not a permanent guarantee.

## Verification
Client tests must prove body/header terminal agreement, v2 fields, countdown without retry storms, exact permission display, and normal QR polling.
