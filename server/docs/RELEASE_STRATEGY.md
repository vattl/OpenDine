# Release Strategy

## Default release mode

Define environment promotion, approvers, project deploy adapter/runbook and required observation window.

## High-risk release options

- feature flag
- canary
- percentage rollout
- shadow mode

## Rollback

Describe compatibility constraints for code and schema rollback.

## Backup / Restore

RPO:
RTO:
Last restore test:

## Evidence contract

Every release records `RELEASE_EVIDENCE.md` containing the integrated/deployed commit, immutable artifact hash, target environment, deployment run, smoke result, production verification, rollback readiness and approval.

Run the strict release gate after deployment evidence exists. Release notes or a READY decision alone do not prove deployment.

## Environment promotion

Development → Staging → Production, unless the project profile explicitly defines another policy.

## Post-deploy verification

Define critical journeys, health signals, observation duration, rollback triggers and accountable operator.
