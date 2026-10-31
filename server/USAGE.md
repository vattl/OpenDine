# AI Development OS v4.3 Usage

## Strict implementation path

For STANDARD+ implementation, `/work` prepares `TDD_CYCLE_REPORT.md`, `TASK_AGENT_LEDGER.md` and `WORKTREE_READINESS.md`. Run preflight before production edits:

```text
python .ai/scripts/worktree_preflight.py --work-item docs/work-items/WI-XXX --command-profile .ai/config/worktree-command-profile.json
python .ai/scripts/validate_worktree_readiness.py --work-item docs/work-items/WI-XXX
```

Record RED/GREEN/REFACTOR/REGRESSION with `.ai/scripts/execution_journal.py`. After each task, collect separate spec-compliance and code-quality review artifacts in `TASK_AGENT_LEDGER.md`. Use `/workflow-diagnose` after retries/conflicts or whenever the execution process needs auditing.

## Normal work

For a new product, use `/project` → `/research` → `/prd`, then enter `/work` after explicit product/PRD approval.

Executable gates:

- package: `python .ai/scripts/gate.py package`
- implementation ready: `python .ai/scripts/gate.py work --work-item <dir> --phase ready`
- acceptance: `python .ai/scripts/gate.py work --work-item <dir> --phase accept`
- local integration: `python .ai/scripts/gate.py work --work-item <dir> --phase integrate`
- release: `python .ai/scripts/gate.py release --work-item <dir> --release-evidence <file>`

Release requires Git integration plus artifact, deployment, smoke and production-verification evidence.

```text
/work
给订单列表增加订单来源筛选，并保证前后端完整支持。
```

The system should:
1. read project baseline
2. create/reuse one Work Item and route required tracks
3. discover current API/UI capability into one authoritative Impact Map
4. identify business invariants and any contract gap
5. design frontend + backend changes together
6. plan vertical slices and a Scenario Matrix for STANDARD+ work
7. pass `IMPLEMENTATION_READY = YES` before production edits
8. implement and verify end-to-end
9. seal the evidence and obtain a different fresh-context Agent's cross-audit
10. accept with evidence
11. stage only Work Item changes, create a local commit, and pass the clean-worktree integrate gate

## Audit routing and remediation

Each Work Item creates `AUDIT_PLAN.md` before implementation. FEATURE/CHANGE/REFACTOR require architecture audit; BUG/REPAIR require root-cause and regression audit; UI, contracts, security/data and reliability/performance impacts add their specialist tracks. CORE and THIRD_PARTY always remain required.

When an audit is BLOCKED, preserve it under `audit-history/<session-id>/`. The implementation owner fixes code/configuration, reruns tests, completes `AUDIT_REMEDIATION.md`, seals a new packet and dispatches a different fresh-context audit Agent. Editing only the report or severity is not remediation.

## Mandatory local commit

Normal work is not complete at `ACCEPTED`. Inspect the diff, exclude pre-existing/unknown user changes, commit the Work Item locally, record `INTEGRATED / NOT_RELEASED`, then run the integrate gate. If the directory is not a Git repository, safely initialize it or remain `READY_TO_COMMIT`. The workflow never pushes without explicit authorization.

## Third-party Agent acceptance audit

Before `ACCEPTED`, finalize the evidence and create `AUDIT_PACKET.md`. Seal its inventory with SHA-256 hashes, then start a different Agent with fresh context and no implementation-edit permission. The auditor produces `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`.

Run:

```text
python .ai/scripts/validate_third_party_audit.py --root . --work-item docs/work-items/WI-XXX
```

Only a PASS may set `Third Party Audit: PASS` in `DELIVERY_GATE.md`. Any changed evidence, incomplete criterion coverage, same-Agent self-approval, missing real session identity, failed audit axis, or open CRITICAL/HIGH finding blocks acceptance and requires a new sealed audit.

### Built-in or external audit Agent

If no provider is configured, start the guided selector:

```text
python .ai/scripts/agent_provider.py setup --evidence docs/work-items/WI-XXX/AGENT_PROVIDER_READINESS.md
```

Choose `builtin` for a different fresh-context built-in Agent, or select a registered CLI such as `codex`, `claude`, or `gemini`. For an external CLI the controller checks installation, authentication, and a bounded live model call. Missing installations and vendor login flows are previewed first and run only after explicit confirmation. Never paste a key into chat or a command argument; use the vendor login flow, terminal environment, or vendor credential store.

CLI/version/key presence alone is not READY. The external path remains blocked until `Provider State: READY` and `Live Probe: PASS`. Use the resulting readiness path and SHA-256 in both `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md` when `Audit Mode: EXTERNAL_PROVIDER`.

For diagnosis without mutation:

```text
python .ai/scripts/agent_provider.py list --json
python .ai/scripts/agent_provider.py doctor --provider codex
python .ai/scripts/agent_provider.py doctor --provider codex --live --evidence docs/work-items/WI-XXX/AGENT_PROVIDER_READINESS.md
```

## Structural UI

```text
/work
重构日志页面、二三级页面和弹窗，重新设计信息架构和视觉，但保留现有业务能力。
```

Expected route:
`UI_IMPACT=STRUCTURAL` → UI Design Track → HTML prototype/screenshot/critique/user approval/lock → production implementation → visual verification.

Before production UI implementation, also create `PROTOTYPE_INTERACTION_CONTRACT.md` and run:

```text
python .ai/scripts/validate_ui_capabilities.py --root . --ui-dir <artifact-dir> --phase plan
```

After implementation, run the same command with `--phase accept`. If it writes an OPEN `BACKEND_COORDINATION_REPORT.md`, show that report to the user and keep the UI BLOCKED/PARTIAL; do not replace missing interfaces with fake production behavior.

The same HTML review and explicit approval gate applies to REFINE/MINOR UI work; its prototype may be smaller, but it may not be skipped.

## Backend changed first
Use the same `/work`; the system should either update frontend consumers or generate a Frontend Consumer Handoff.

## Frontend need changed first
If the UI requires data/behavior the backend cannot provide, the system should generate a Backend Capability Request instead of inventing client-side fake behavior.

## Project baseline
Run `/baseline` when first installing into an existing repository. Normal `/work` reuses it and performs focused drift checks. Use `/rebaseline` only after accepted foundation changes.


## UI prototype rule

For every `/work` or `/ui` request that changes visible UI or interaction, the agent must create and present an isolated HTML/CSS/JS prototype before production UI implementation. Production editing remains blocked until you explicitly approve the rendered result and the approval is recorded as `Approval Status: APPROVED`.

After approval, run the translation plan gate before editing production UI. After implementation, present same-viewport prototype and production screenshots plus diff evidence; UI work cannot be accepted until the final fidelity gate reports `Target State Match: YES`, `Legacy Remaining: NO`, zero HIGH/CRITICAL deltas, and your explicit fidelity confirmation.

Also create `ADAPTIVE_UI_CONTRACT.md` before implementation. Declare only the terminals the product genuinely supports, but cover each REQUIRED terminal's input mode, orientation/context, component variants and business operations. Run `validate_ui_adaptive.py --phase plan`, then produce `DEVICE_UX_VERIFICATION_REPORT.md` from the real production stack and run `--phase accept`. A desktop-only product may truthfully declare one required profile; a multi-device product may not use one desktop screenshot as evidence for phone/tablet behavior.
