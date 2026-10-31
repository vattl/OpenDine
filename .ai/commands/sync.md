# /sync

Synchronize documentation/state with implemented reality.

Input: `$ARGUMENTS`


## Workstream Reconciliation (v3.1)

During sync, reconcile `workstreams/REGISTRY.md` and workstream STATE files against actual Git branches/worktrees. Mark contradictions as stale/unknown instead of deleting state automatically.

## Adaptive Sync Rule

Synchronize only artifacts whose truth materially changed. Do not rewrite PRD, architecture, API, database, and changelog after every tiny implementation edit. Documentation should remain useful project memory rather than generated noise.

Modes:

- `/sync --check` → detect only
- `/sync` → detect and repair confirmed documentation drift

## Compare

- Target State
- Active Diff
- Code
- Database
- API
- Tests
- Documentation
- PROJECT_STATE

## Drift Classes

- MATCH
- DOCUMENTATION_STALE
- CODE_SUSPECT
- STATE_STALE
- UNKNOWN

Do not rewrite docs to legitimize suspected bad code.

If implementation defect is found, return to IMPLEMENTATION or BLOCKED.

When active Diff is fully verified and released, archive to `docs/history/diffs/`.

## Interruption-Safe Sync

If synchronization is interrupted, record which artifacts were verified/updated and which remain. Do not mark Documentation Sync PASS until required scope is fully reconciled.


---

# Sync Commit

When `/sync` modifies global documentation or project state, prefer a dedicated documentation/state commit rather than mixing it into an unrelated implementation task commit.

Example:

`docs(state): sync F012 reservation release state`


# UI Artifact Sync

When an approved prototype materially defines current production UI, verify that project state and active UI Diff reflect the implemented target. Do not treat disposable unapproved prototypes as product truth.

---

# UI Artifact Sync Extension

For released UI work governed by an approved HTML prototype, verify relevant design artifacts remain coherent:

- approved prototype
- measured UI spec
- UI Diff
- implementation map
- visual comparison report
- production state

Do not leave an obsolete prototype marked as the current approved target after the production design intentionally changes.


---

# v2.6 NFR Sync

When runtime contracts materially changed, synchronize relevant project memory:

- `docs/NON_FUNCTIONAL_REQUIREMENTS.md`
- `docs/PERFORMANCE_BUDGET.md`
- runtime-risk notes in feature/change/task artifacts

Do not update these documents for trivial changes that do not affect runtime expectations.

# v3.2 UI Acceptance State

For material UI work, synchronize the final visual acceptance state and approved reference revision where the project tracks them. Do not document a UI as accepted if screenshot verification remains CORRECTION_REQUIRED or BLOCKED.
