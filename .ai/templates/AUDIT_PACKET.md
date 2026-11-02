# Third-Party Audit Packet — WI-XXX

Packet Status: DRAFT / SEALED
Work Item: WI-XXX
Implementer Agent: AGENT-ID
Prepared At: ISO-8601 timestamp
Reviewed Snapshot: immutable snapshot identifier
Acceptance Criteria: 0
Acceptance Contract SHA256: 64-character-sha256
Evidence Files: 0
Material Unknowns: 0

## Evidence Inventory

Paths are resolved from the Work Item directory and must remain inside the repository. Seal each final evidence file with its SHA-256 digest. Do not inventory this packet or the third-party report.

| Evidence ID | Path | SHA256 | Purpose |
|---|---|---|---|
| EV-01 | path/to/final-evidence | 64-character-sha256 | What this evidence proves |

## Acceptance Contract

Include every acceptance criterion from `WORK_ITEM.md` exactly once, in source order, using canonical IDs `AC-01`, `AC-02`, and so on. Requirement text must match exactly. `Acceptance Contract SHA256` is SHA-256 over UTF-8 lines formatted `AC-NN|exact requirement text`, joined with `\n`. Every Claimed Evidence cell is a comma-separated list containing only exact Evidence IDs or inventoried paths; prose and mixed valid/unknown references are invalid.

| Criterion ID | Requirement | Claimed Evidence |
|---|---|---|
| AC-01 | Original criterion | Evidence IDs and observable proof |

## Sealing Declaration

The implementer declares that this packet contains the complete evidence submitted for independent acceptance audit. Any change to an inventoried file invalidates the audit.

