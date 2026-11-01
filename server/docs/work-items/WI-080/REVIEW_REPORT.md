# Review Report — WI-080

Scope: merchant README, deployment guide/configuration, fresh-install database bootstrap and focused tests
Date: 2026-11-02
Overall Status: PASS_WITH_ISSUES
Review Decision: PASS

## Requested Diff

Explain actual small-merchant value and provide a reproducible, safe, independently deployable startup path with clear environment-variable purposes.

## Planned Structural Diff

Merchant-first README; current deployment guide; buildable/digest-pinned Compose stack; isolated networks/private key storage; empty-database bootstrap with explicit migration/readiness and operator-selected administrator; validation tooling.

## Implemented Diff

Matches the plan and AC1–AC5. The final production range is `9037d372..afe877d1`, with no API/client production change.

## Missing Diff

NONE for the accepted scope. Docker Engine, client/device, real payment and hardware validation remain target-environment responsibilities and are explicitly disclosed.

## Unexpected Diff

NONE. Review remediation added internal network segmentation and official-image digest pins within the deployment-hardening scope.

## Legacy Diff Remaining

The historical migration guide remains for background with a prominent warning; it is not the new-install entry point.

## Critical Findings

NONE

## High Findings

NONE

## Medium Findings

- Non-blocking follow-up: move bootstrap-only administrator inputs to a short-lived environment file/invocation so the value can be deleted after first-login password rotation and normal Compose commands do not require it.

## Low Findings

NONE

## Regression Risk

MEDIUM

## Database Risk

HIGH by surface; bounded to an explicit empty-database-only CLI with real MySQL verification and fail-closed reuse behavior.

## API Compatibility

No endpoint or OpenAPI contract change.

## Security

PASS: independent secrets, private data network, unexposed state stores, private payment-key volume, BCrypt admin, no default credentials, digest-pinned images.

## Performance

No steady-state business-path change; bootstrap is one-shot. No performance claim added.

## Testing Confidence

HIGH for Java/package/bootstrap/login/refusal/static Compose behavior; explicitly limited for Docker runtime, Redis multi-instance delivery, clients/devices and third-party/hardware integration.

## Documentation Status

PASS

## Release Recommendation

APPROVE

## Required Fix Tasks

- None before acceptance; track the bootstrap-only environment-file improvement as a separate hardening change.
