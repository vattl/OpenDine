# Workflow Self-Diagnosis Rules

`/workflow-diagnose` is a read-only operational capability inside `/work`, not a second lifecycle.

Start with the user's intake statement. Inventory and hash the durable Work Item evidence, then review:

- routing/skill and phase timeline;
- plan adherence;
- repeated work or repeated dispatch;
- stumbles, retries and blockers;
- test/review/audit quality evidence;
- request or policy conflicts;
- evidence-backed time/cost signals.

Every finding must cite a real `path:line`, state the observed fact, impact and recommendation. `Input Mutation: NONE` is mandatory. Unsupported metrics, inferred counts without evidence, or edits to source evidence are forbidden. A CLEAR report has no open findings. A BLOCKED report is valid diagnostic output, but cannot satisfy an acceptance gate until its findings are remediated and diagnosis is rerun.

Dimension status is fail-closed:

- `REVIEWED` means the dimension-specific source exists and the named check actually ran;
- `INSUFFICIENT_EVIDENCE` means the check cannot be completed from durable evidence;
- `BLOCKED` means the check found a lifecycle conflict that prevents a trustworthy CLEAR result.

Each of the seven dimensions must appear exactly once, use its matching `CHECK_<DIMENSION>` check, and cite inventoried evidence appropriate to that check. Every non-`REVIEWED` dimension requires an OPEN finding in the same dimension. Evidence IDs, evidence paths, dimension rows and finding IDs must be unique. Finding citations must point into the hashed Evidence Inventory; an arbitrary repository file is not acceptable support. `CLEAR` is valid only when all seven dimensions are `REVIEWED` and no finding is OPEN.

Use `.ai/scripts/workflow_diagnose.py` to generate the report and `validate_workflow_diagnosis.py` to validate it. Acceptance invokes `--require-clear` when the Diagnosis Gate is REQUIRED.
