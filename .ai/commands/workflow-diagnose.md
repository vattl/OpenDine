# /workflow-diagnose

Generate an evidence-based, read-only diagnosis for the active or specified Work Item.

1. Record the user's intake statement verbatim or faithfully summarized.
2. Run `python .ai/scripts/workflow_diagnose.py --work-item <dir> --intake <statement>`.
3. Review every finding against its inventoried `path:line` citation. Confirm every dimension appears exactly once, uses its matching named check, and has dimension-specific durable evidence. Do not invent durations, token counts, retries or causes.
4. Run `python .ai/scripts/validate_workflow_diagnosis.py --work-item <dir>`.
5. If the report is BLOCKED, route real findings back to the appropriate lifecycle phase. After remediation and revalidation, regenerate the report.

The command may create or replace only `WORKFLOW_DIAGNOSIS.md`; it must not modify the evidence it diagnoses. A structurally valid BLOCKED report is useful output but does not satisfy an acceptance gate.

Do not manually upgrade `INSUFFICIENT_EVIDENCE` or `BLOCKED` to `REVIEWED`. Remediate the cited evidence gap or conflict, then regenerate the diagnosis from the changed durable evidence.
