# Release Governance Rules

High-risk changes should prefer progressive exposure where practical:

- feature flags,
- internal-only release,
- canary rollout,
- percentage rollout,
- shadow mode.

A rollback strategy is not complete until compatibility is assessed.

For schema/data changes verify:
- can previous code still read the new schema?
- is rollback data-safe?
- is forward-only migration explicitly accepted if rollback is impossible?

Release readiness requires configuration and contract checks in addition to tests.

## Release evidence gate

Release is in these distinct states:

`RELEASE_READY → DEPLOYED → PRODUCTION_VERIFIED → RELEASED → MONITORED`.

Record `RELEASE_EVIDENCE.md` with the integrated Git SHA, deployed SHA, artifact path/hash, target environment, deployment command/run, migration/config results, smoke result, production verification, rollback readiness, approval and remote references.

Run `python .ai/scripts/gate.py release --work-item <dir> --release-evidence <file>`. Missing Git integration, artifact identity, real deployment, smoke evidence or production verification blocks RELEASED. The existence of release notes never proves deployment.
