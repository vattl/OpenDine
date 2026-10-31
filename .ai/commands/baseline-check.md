# /baseline-check — Detect Baseline Drift

Compare relevant baseline facts with current repository reality.

Normal Work Items should perform this check only for affected areas; do not rescan the whole repository unless evidence indicates broad drift.

Report:
- VERIFIED_CURRENT
- LOCAL_DRIFT
- SIGNIFICANT_DRIFT
- REBASELINE_REQUIRED

A drift finding must cite concrete repository evidence and propose the smallest safe baseline update.
