# Policy as Code and Workstream Automation

These scripts automate machine-verifiable invariants while preserving model engineering judgment.

## Execution-discipline tools

- `worktree_preflight.py` runs the hash-bound repository command profile with `shell=False` and creates `WORKTREE_READINESS.md`.
- `validate_worktree_readiness.py` checks it against live Git/worktree state.
- `execution_journal.py` runs test argv and appends hash-chained RED/GREEN/REFACTOR/REGRESSION events and logs.
- `validate_execution_discipline.py` validates TDD order, logs/hashes and per-task fresh implementer plus two-reviewer evidence.
- `workflow_diagnose.py` creates a read-only evidence inventory/report; `validate_workflow_diagnosis.py` validates citations and requires CLEAR at acceptance.

## Policy validation

```bash
python .ai/scripts/validate.py
python .ai/scripts/validate.py --release
```

The v4.3 policy check always validates current workflow semantics, governance state, and required package structure. `--release` additionally validates `MANIFEST.json` file count, paths, sizes, and SHA-256 hashes; this keeps normal runtime/baseline state changes from being mistaken for distribution corruption. A non-Git distribution directory produces an explicit warning and skips Git-only transaction checks.

Release validation is intentionally read-only. Refresh `MANIFEST.json` only as an explicit packaging step after all intended files and mutable template state are finalized; do not auto-accept unexplained drift.

## Audit routing, remediation and local integration

```bash
python .ai/scripts/validate_audit_plan.py --root . --work-item docs/work-items/WI-XXX --phase plan
python .ai/scripts/validate_audit_plan.py --root . --work-item docs/work-items/WI-XXX --phase accept
python .ai/scripts/gate.py work --work-item docs/work-items/WI-XXX --phase integrate
```

The plan phase derives mandatory tracks from requirement type, risk and impacts. The accept phase rejects unresolved findings and archived BLOCKED audits without code/configuration fixes, retesting, packet resealing and a fresh re-audit. After the task-scoped local commit, the integrate phase requires an existing Git HEAD, `INTEGRATED` Work Item truth, `Git Integration: PASS` and a clean working tree.

## HTML UI prototype gate

```bash
python .ai/scripts/validate_ui_gate.py \
  --root . \
  --require-ui-prototype \
  --prototype-dir design/prototypes/UI001-example
```

The gate accepts only `.html/.htm` review prototypes and requires a screenshot, a single approval record containing both `Presented To User: YES` and `Approval Status: APPROVED`, and a UI lock. `--require-structural-ui` remains a compatibility alias with the same strict behavior.

## Prototype-to-production fidelity gates

```bash
python .ai/scripts/validate_ui_fidelity.py --root . --ui-dir <artifact-dir> --phase plan
python .ai/scripts/validate_ui_fidelity.py --root . --ui-dir <artifact-dir> --phase accept
```

The plan phase requires complete prototype/component mapping, measurements, and classification of every legacy region before production UI editing. The accept phase additionally requires structural target closure, no legacy residue, same-viewport screenshot/diff evidence, zero HIGH/CRITICAL deltas, and explicit final user fidelity confirmation.

## Prototype interaction capability gate

```bash
python .ai/scripts/validate_ui_capabilities.py --root . --ui-dir <artifact-dir> --phase plan
python .ai/scripts/validate_ui_capabilities.py --root . --ui-dir <artifact-dir> --phase accept
```

The plan phase requires every prototype datum/action to map to a real production capability or assigned Backend Capability Request. The accept phase requires VERIFIED provider/consumer integration, real E2E evidence, zero fake production interactions and zero unresolved backend capabilities. On failure it writes `BACKEND_COORDINATION_REPORT.md`; surface that report to the user instead of claiming UI completion.

## Adaptive multi-device UI/UX gate

```bash
python .ai/scripts/validate_ui_adaptive.py --root . --ui-dir <artifact-dir> --phase plan
python .ai/scripts/validate_ui_adaptive.py --root . --ui-dir <artifact-dir> --phase accept
```

The plan phase requires truthful terminal/input/context profiles, prototype evidence for every REQUIRED profile, consistent component families/variants and complete business-operation coverage. The accept phase requires real production evidence for every required profile and operation/profile pair, with zero component consistency violations, critical operation failures and unintended clipping/overflow.

## Third-party Agent acceptance audit

```bash
python .ai/scripts/validate_third_party_audit.py \
  --root . \
  --work-item docs/work-items/WI-XXX
```

Before running it, seal `AUDIT_PACKET.md` with the final evidence paths and SHA-256 hashes. A different fresh-context, read-only Agent must create `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`. The validator rejects self-approval, stale evidence, unverifiable session/receipt data, missing audit axes, incomplete acceptance-criterion coverage, and unresolved findings. This gate supplements rather than replaces security, tests, UI gates, and user approval.

### Agent provider controller

```bash
python .ai/scripts/agent_provider.py list --json
python .ai/scripts/agent_provider.py setup \
  --evidence docs/work-items/WI-XXX/AGENT_PROVIDER_READINESS.md
```

The controller offers the built-in Agent and registered external CLIs. For external providers it detects the CLI and authentication state, previews registry-defined install/login argv, requires explicit confirmation before mutation, and requires a bounded read-only/plan live probe before READY. It never accepts or persists key values. `validate_third_party_audit.py` requires the readiness artifact and matching SHA-256 in both receipt and report whenever audit mode is `EXTERNAL_PROVIDER`.

## Automatic workstream isolation

```bash
python .ai/scripts/workstream.py status
python .ai/scripts/workstream.py list
python .ai/scripts/workstream.py ensure --type FEATURE --parent F012 --title "reservation ordering"
```

See `WORKSTREAM_README.md` and `.ai/rules/AUTO_ISOLATION_RULES.md`.

The scripts must not replace engineering reasoning. Add project-specific checks only when they are reliably machine-verifiable.

## UI screenshot tools (introduced in v3.2)

### Capture a deterministic screenshot

Requires Playwright in the target project:

```bash
node .ai/scripts/capture_ui.mjs \
  --url http://localhost:3000/members \
  --out production.png \
  --width 1440 \
  --height 900
```

### Generate diagnostic image diff

Requires Pillow:

```bash
python .ai/scripts/visual_diff.py \
  prototype.png production.png \
  --out-dir visual-diff-output
```

The generated pixel-difference ratio is diagnostic only. Use `/ui-verify` for acceptance.
