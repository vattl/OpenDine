# Contract Handoff — APPROVAL-TOKEN-ENVELOPE

- Work Item: WI-060
- Origin layer: server
- Target layer: deployment/operations
- Status: READY_FOR_DEPLOYMENT_CONFIGURATION
- Business goal: remove usable approval secrets from database plaintext.

## Current Capability
All application instances read `t_access_approval` to support cross-instance polling.

## Required Capability
Configure the same high-entropy `APPROVAL_TOKEN_ENVELOPE_KEY` on every backend instance before starting the new artifact. Keep it separate from JWT and payment keys.

## Contract Delta
HTTP schema is unchanged. QR confirmation fails closed when the key is missing; invalid or corrupted envelopes are never returned.

## Affected Consumers / Providers
Backend deployment configuration and secret management only. Flutter clients require no adaptation.

## Implementation Guidance
Generate at least 32 random bytes with an approved secret manager, inject through the environment, rotate only with a coordinated drain exceeding the 120-second token lifetime, and never log the value.

## Compatibility / Migration
The migration expires and clears outstanding legacy plaintext approvals. Users may need to regenerate QR codes created immediately before deployment.

## Verification
Start two instances with the same key and prove one can poll a token approved through the other; verify a mismatched key cannot disclose it.
