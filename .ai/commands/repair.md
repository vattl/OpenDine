# v4.0 Unified Routing

This command is a typed entry into `/work` with Work Type = `REPAIR`. Do not create a separate lifecycle. Attach all discovery, design, implementation, verification and acceptance evidence to the parent Work Item.


---

# /repair

Use when a problem has been patched repeatedly, related consumers disagree, or the root capability is likely duplicated.

## Flow

Symptom → Root Cause → Capability Owner → Consumer Discovery → Duplicate Logic Discovery → Layer Impact Matrix → Upstream/Downstream Graph → Central Repair → Cross-Layer Regression → End-to-End Verification

Output must include:

- authoritative owner
- consumer matrix
- layer impact matrix
- local patches removed/retained with reason
- regression evidence
- unresolved risks
