# AI Development OS v4.3 — Prototype Enforcement Full Edition

v4.3 is a full superset of v4.2. This package policy requires an HTML review prototype and explicit user approval for every UI-impacting request before production UI editing.

## Execution discipline inside `/work`

- Behavior work carries observed, hash-chained `RED → GREEN → REFACTOR → REGRESSION` evidence; final green tests cannot hide missing TDD.
- Every implementation task uses a unique fresh implementer Agent plus separate fresh specification and code-quality reviewers bound to the same final snapshots.
- `worktree_preflight.py` verifies real linked-worktree/submodule/mapping state, setup and a passing baseline before production edits.
- `/workflow-diagnose` produces a read-only, `path:line`-cited report for routing drift, repeated work, blockers, evidence gaps and request conflicts.
- `gate.py` validates planning at ready and completed discipline at accept/integrate; the final sealed third-party audit remains mandatory.

## v4.3 core change

For `UI_IMPACT=MINOR|STRUCTURAL` or UI intent `REFINE|REFACTOR|REDESIGN`:

```text
Design Strategy
→ Prototype Requirement = REQUIRED
→ Prototype Mode = HTML
→ Renderable .html/.htm Prototype
→ Screenshot / Visual Reference
→ Design Critique
→ User Presentation
→ Explicit User Approval (`Approval Status: APPROVED`)
→ UI Lock
→ IMPLEMENTATION_READY=YES
→ Production UI implementation
```

The HTML artifact is the mandatory review format. Native/component-compatible previews may assist feasibility work, but they do not satisfy the approval gate or replace target-stack production implementation.

Prototype approval only authorizes implementation. It does not permit a “close enough” result. Before production UI edits, every prototype and legacy region must be mapped and the translation plan gate must pass. Before UI acceptance, same-viewport screenshots, structural closure, legacy removal, diff evidence and explicit user fidelity confirmation must pass the final fidelity gate.

Prototype interactions are governed separately from visual fidelity. Every material datum/action must map to AVAILABLE, DERIVABLE, API_EXTENSION, NEW_API, or NOT_SUPPORTED. Missing backend support must produce an assigned Backend Capability Request and `BACKEND_COORDINATION_REPORT.md`; production mocks or fake buttons are forbidden. UI acceptance requires `validate_ui_capabilities.py --phase accept` with all interactions verified end-to-end and no open backend items.

Adaptive device UX is a third independent UI concern. Every UI Work Item must define terminal/platform, orientation, input modality, usage context, consistent component families/variants and promised business operations in `ADAPTIVE_UI_CONTRACT.md`. Each REQUIRED profile needs HTML prototype evidence before implementation and real production/operation evidence before acceptance. `validate_ui_adaptive.py` blocks arbitrary component sizes, missing device layouts, overflow/clipping and breakpoint-specific loss of business operations.

Every Work Item also has a mandatory third-party Agent acceptance audit. After implementation, tests, security review and internal review are final, the implementer seals `AUDIT_PACKET.md` with SHA-256 evidence hashes. A different fresh-context, read-only Agent writes `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`, covers every required audit axis and every acceptance criterion, and must pass `validate_third_party_audit.py`. The implementer cannot approve its own work.

Audit execution supports either the built-in Agent or registered external CLIs (Codex, Claude Code, and Gemini CLI by default). When no provider is selected, `/agent-provider` prompts for a choice. External setup detects CLI/auth state, previews official install/login actions, requires explicit confirmation for every system mutation, and loops until a bounded read-only/plan live probe passes or the user cancels. Key values are never accepted in chat/argv or written to repository evidence. `EXTERNAL_PROVIDER` audits must bind `AGENT_PROVIDER_READINESS.md` into the receipt and report.

See `docs/UI_PROTOTYPE_ENFORCEMENT.md`.

---

# AI Development OS v4.2 — Domain & Workflow Consolidation

v4.2 keeps every v4.1 capability while tightening the business logic of the workflow. The system now centers on Project Baseline, Work Item, Business Invariants, Impact Map, Implementation Design, Vertical Slices/Scenario Matrix, and Acceptance Evidence.

See `.ai/rules/WORKFLOW_CORE.md` for the authoritative v4.3 lifecycle.

For a new product, begin with `/project`, `/research`, and `/prd`. Executable gates are deliberately scope-specific:

```bash
python .ai/scripts/gate.py package
python .ai/scripts/gate.py work --work-item docs/work-items/WI-XXX --phase ready
python .ai/scripts/gate.py work --work-item docs/work-items/WI-XXX --phase accept
python .ai/scripts/gate.py work --work-item docs/work-items/WI-XXX --phase integrate
python .ai/scripts/gate.py release --work-item docs/work-items/WI-XXX --release-evidence path/to/RELEASE_EVIDENCE.md
```

Package integrity is not implementation acceptance, and release preparation is not deployment.

---

# AI Development OS v4.1 — Full Edition

A repository-owned engineering operating system for AI coding agents.

## What v4.1 fixes

### 1. Workflow enforcement
`/work` is the main entry and routes before editing. Any UI-impacting work must pass HTML prototype review and explicit user approval before production UI changes.

### 2. Persistent project understanding
Agents read a reusable Project Baseline instead of rediscovering the entire repository every time. The baseline covers technology, architecture and accepted design language, and is versioned/updated when intentional major changes occur.

### 3. Frontend ↔ backend collaboration
Contract changes work both directions:
- backend change → frontend consumer handoff/update
- frontend need → backend capability request

No layer silently assumes another layer will adapt.

## Primary lifecycle

The current authoritative normal lifecycle is:

`REQUEST → UNDERSTAND → BASELINE FAST CONTEXT → ROUTE → DISCOVER → DESIGN → PLAN → IMPLEMENTATION_READY → IMPLEMENT → SELF_VERIFY → REVIEW → THIRD_PARTY_AUDIT → ACCEPT → BASELINE UPDATE → INTEGRATE → optional RELEASE → optional MONITOR`

`ACCEPTED`, `INTEGRATED`, and `RELEASED` are distinct evidence-backed states. The older “PRE-EDIT GUARD” name remains only as a compatibility reference; `IMPLEMENTATION_READY` is the hard production-edit gate.

Every request creates `AUDIT_PLAN.md` during routing. Work type, risk and affected surfaces select specialist audit tracks automatically. A failed audit is archived and must cause code/configuration remediation, retesting, packet resealing and a new independent audit. Normal task completion also requires a task-scoped local Git commit and clean-worktree integration gate; `ACCEPTED` without the commit is only `READY_TO_COMMIT`.

## Main commands
- `/work` normal work
- `/continue` resume
- `/review` independent review
- `/third-party-audit` mandatory fresh-context acceptance cross-audit
- `/agent-provider` choose and prove a built-in or external audit Agent
- `/release` release flow
- `/incident` incident fast lane
- `/ui` UI specialist entry
- `/baseline`, `/baseline-check`, `/rebaseline` baseline maintenance
- `/contract-handoff` contract collaboration specialist

Older specialist commands remain available but are supporting tools, not competing workflows.
