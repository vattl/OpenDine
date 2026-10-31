# /policy-check

Run repository governance validations.

Input: $ARGUMENTS

Default checks:
- project state coherence,
- task Git transaction state,
- configuration contract,
- active workstream isolation metadata,
- release readiness markers when requested.

Use scope-honest checks:

- package installation: `python .ai/scripts/gate.py package`
- implementation readiness: `python .ai/scripts/gate.py work --work-item <dir> --phase ready`
- acceptance: `python .ai/scripts/gate.py work --work-item <dir> --phase accept`
- release: `python .ai/scripts/gate.py release --work-item <dir> --release-evidence <file>`

`validate.py` remains a compatibility package/policy check. Do not present its ordinary PASS as Work Item or release approval.

Report machine-detected failures separately from judgment-based review findings.
