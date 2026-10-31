# Install v4.3

1. Copy the package contents into the repository root.
2. Ask the agent to read `.ai/SKILL.md` and `AGENTS.md`.
3. For an existing project, run `/baseline` once to initialize durable project/design/architecture knowledge.
4. Use `/work` for normal engineering requests.

Optional validation:

```bash
python .ai/scripts/validate_v41_package.py
python .ai/scripts/validate_baseline.py
python .ai/scripts/validate_contract_handoff.py
```

The baseline placeholder is intentionally `NOT_INITIALIZED` until a real repository is inspected.


## v4.3 UI enforcement check

After installation, required HTML prototype evidence for any UI change can be checked with:

```bash
python .ai/scripts/validate_ui_gate.py --root . --require-ui-prototype
```

The legacy `--require-structural-ui` flag remains a compatibility alias. Both flags intentionally block unless an HTML/HTM prototype, screenshot, explicit `Approval Status: APPROVED`, and UI lock are present.

Before production UI editing and again before UI acceptance, run:

```bash
python .ai/scripts/validate_ui_fidelity.py --root . --ui-dir design/visual-verification/UI001 --phase plan
python .ai/scripts/validate_ui_fidelity.py --root . --ui-dir design/visual-verification/UI001 --phase accept
```

The plan phase blocks unmapped prototype/legacy regions. The accept phase additionally blocks missing screenshots/diffs, retained legacy structure, target-state mismatch, material deltas, or missing final user confirmation.
