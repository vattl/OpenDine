# /release

Perform Release Gate and release preparation.

Input: `$ARGUMENTS`


## Workstream Release Gate (v3.1)

Before release, verify there are no unintentionally unmerged workstreams required by the release candidate and no active workstream has silently modified release-critical contracts/config outside the integration branch.

Release validation should operate on the intended integrated branch, not an arbitrary feature worktree.

## Adaptive Release Rule

Apply release gates proportionally to the release risk, but never skip gates that protect data integrity, security, migrations, or critical business flows. A local development edit does not become "released" merely because code was changed.

## Gate

Verify relevant:

- Implementation COMPLETE
- Active Diff VERIFIED
- Unresolved Diff Rows = 0
- Unexpected Diff = NONE or explicitly accepted
- Tests PASS
- Review PASS
- Documentation SYNCED
- Migration READY
- API compatibility verified
- Release Notes READY
- Rollback strategy defined
- Blocking issues NONE

Decision:

- READY
- BLOCKED

Only after actual release completion may work be marked RELEASED and PROJECT_STATE return to IDLE.

Create `RELEASE_EVIDENCE.md`, deploy through `/deploy`, then run the strict executable release gate. `READY` means prepared; only verified environment evidence can establish `DEPLOYED` and `PRODUCTION_VERIFIED`.

## Interruption-Safe Release Gate

If release preparation is interrupted, distinguish READY evidence already verified from checks still pending. Never infer deployment or release completion from preparation state.


---

# Git Release Gate

Before RELEASE_READY, verify:

- completed tasks have required commit evidence
- no completed task remains `IMPLEMENTED_UNCOMMITTED`
- working tree contains no unexplained release-related modifications
- release commit history is understandable enough to support targeted revert

Unrelated user changes may remain dirty, but must be clearly identified and excluded from release assumptions.


---

# v2.6 Production Reliability Release Gate

When Runtime Risk is HIGH/CRITICAL, release readiness must include required evidence for applicable:

- resource lifecycle
- concurrency/idempotency
- boundary/failure paths
- performance budget or measured baseline
- backlog/backpressure strategy
- soak/longevity test
- observability

Required unresolved CRITICAL/HIGH runtime findings block release.
