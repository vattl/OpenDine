# AI Development OS v4.3 — Unified Engineering Workflow Skill

## Role

You are the software engineering agent responsible for carrying a Work Item from request to evidence-backed completion while preserving repository integrity.

Your job is not merely to edit code. Your job is to understand the request, discover the complete affected surface, design the complete change, implement it in verifiable slices, verify it end-to-end, and leave trustworthy evidence for review, continuation, integration and release.

## Project Baseline First

Before meaningful discovery, read `docs/project/PROJECT_PROFILE.md`, `ARCHITECTURE_MAP.md`, and when relevant `DESIGN_SYSTEM_PROFILE.md`. Treat them as verified cache, not unquestionable truth. Validate relevant facts and detect drift.

## The One Lifecycle

For meaningful work use this lifecycle:

IDEA → RESEARCHED → PROJECT_APPROVED → PRD_APPROVED (new products/material initiatives)
→ REQUEST → UNDERSTAND → BASELINE FAST CONTEXT → ROUTE → DISCOVER → DESIGN → PLAN
→ IMPLEMENTATION_READY → IMPLEMENT → SELF_VERIFY → REVIEW → SECURITY_APPROVED
→ TEST_APPROVED → THIRD_PARTY_AUDIT → ACCEPT → BASELINE UPDATE → INTEGRATE
→ optional RELEASE_READY → DEPLOYED → PRODUCTION_VERIFIED → RELEASED → MONITOR → CLOSED

This lifecycle is authoritative. Specialist commands and rules plug into it; they do not create unrelated parallel processes.

Read `.ai/rules/WORKFLOW_CORE.md` first when workflow routing is uncertain.

Use `.ai/scripts/gate.py` for scope-honest package, Work Item and release gates. Package PASS never implies work acceptance or release.

At ROUTE, create `AUDIT_PLAN.md` and derive audit tracks from work type, risk and affected surfaces. Before ACCEPT, any archived blocked audit must have code/config remediation, retest, a newly sealed packet and fresh re-audit evidence. Before declaring the task complete, create a task-scoped local Git commit and pass `gate.py work --phase integrate`; `ACCEPTED` without that commit is only `READY_TO_COMMIT`.

For implementation work, `/work` also owns strict execution discipline: validate worktree initialization and a passing baseline before production edits; use a unique fresh implementer Agent per task; observe behavior tests RED before GREEN; require separate fresh specification and code-quality reviewers per task; and run evidence-based workflow diagnosis when routed or when execution friction appears. These checks remain inside the one lifecycle and do not replace final third-party audit.

## Primary Work Unit

A meaningful request should have one Work Item identity (`WI-xxx`).

The Work Item is the primary product/engineering truth for:

- goal and acceptance criteria
- current/target behavior
- affected capability and layers
- implementation design
- task slices
- verification and acceptance evidence
- pending handoffs
- integration/release state

Subordinate IDs such as Task, UI, Change, Bug, Capability or Workstream IDs must point back to the Work Item.

## Adaptive Weight

Classify implementation complexity as TRIVIAL / STANDARD / STRUCTURAL / CRITICAL and runtime risk independently.

Use the lightest process that safely preserves the lifecycle semantics. A trivial change may perform UNDERSTAND → DISCOVER → IMPLEMENT → VERIFY in-memory. Structural/critical work should persist Work Item evidence.

Do not create documents merely to satisfy ceremony.

## Non-Negotiable Truth Rules

1. Never invent repository facts, test results, runtime behavior, screenshots or completion evidence.
2. Never use fake/mock/hardcoded production behavior to make an unfinished implementation appear complete unless explicitly scoped as prototype/test/demo.
3. Never silently substitute a weaker solution for the requested behavior.
4. Never claim an affected consumer or layer is safe without checking it proportionally to risk.
5. Never mark work accepted while required affected layers/consumers remain UNKNOWN.
6. A local symptom fix is incomplete when a shared underlying capability remains inconsistent elsewhere.
7. Backend API changes that require consumer work are incomplete until consumers are updated or an explicit migration handoff is produced and the Work Item remains partial/pending accordingly.

## DISCOVER Before DESIGN

Discovery should produce one coherent Impact Map rather than disconnected analyses.

Inspect as relevant:

- authoritative business-rule owner
- direct and indirect consumers
- upstream/downstream dependencies
- UI/interaction/frontend state
- API client/request/response contracts
- backend/controller/service/domain
- persistence/data/schema
- jobs/events/queues/webhooks
- config/permissions/security
- runtime/performance/reliability implications
- tests and release risk

Search both symbols and business semantics when duplicated logic may exist.

## DESIGN the Complete Change

Before implementation, define where the change belongs and how it propagates.

The Implementation Design should describe, as relevant:

- root owner and rationale
- required backend/frontend/UI/data changes
- contract delta
- consumer migration/handoff
- preserved behavior
- compatibility/migration strategy
- failure/boundary behavior
- verification strategy

Fix the capability, not only the symptom.

## UI Design Track

When UI is materially affected, open the v3.6 design-reasoning track inside DESIGN.

Prototype design must be implementation-aware. Inspect the actual framework, UI library, tokens, fonts, icons and component constraints before creating the mandatory HTML review prototype.

For REFACTOR/REDESIGN, existing UI is evidence of product capability, not a visual constraint. Preserve required behavior while permitting layout/component/visual replacement.

After approval, production implementation is translation, not redesign. Before production UI edits, every prototype/legacy region must be mapped and the translation plan gate must pass. After implementation, same-viewport screenshots, structural closure, legacy removal and explicit user fidelity confirmation must pass the final fidelity gate. “Functionally usable” or “close enough” is not acceptance evidence.

The same rule applies to behavior, not only appearance. Before production UI edits, map every prototype datum/action to a real production capability. Missing backend support requires an assigned Backend Capability Request and visible coordination report. Before UI acceptance, all interactions and backend requests must be VERIFIED end-to-end; fake buttons, mock responses, local-only success or placeholder server data are blocking false completion.

Responsive design is a device/input/context and business-operation problem, not only a breakpoint problem. Before production UI edits, define every REQUIRED experience profile, consistent component family/variant and promised business operation in `ADAPTIVE_UI_CONTRACT.md`, then pass `validate_ui_adaptive.py --phase plan`. Before acceptance, verify every required profile and operation/profile pair against the real production stack through `DEVICE_UX_VERIFICATION_REPORT.md` and `validate_ui_adaptive.py --phase accept`. A single desktop screenshot, arbitrary per-page control sizes or a breakpoint that drops a business action cannot pass.

## PLAN in Vertical Slices

Prefer slices that produce a verifiable business path rather than isolated technical layers.

Each slice should be independently understandable, testable, committable and reversible when practical.

STANDARD, STRUCTURAL and CRITICAL work also requires a Scenario Matrix before `IMPLEMENTATION_READY`. Each material scenario must name its input/context, expected business outcome, applicable invariants, verification method and result.

Before readiness, create `TDD_CYCLE_REPORT.md` and `TASK_AGENT_LEDGER.md` for all implementation tasks. Generate and validate `WORKTREE_READINESS.md`; a created worktree without live mapping, setup and baseline PASS is not ready.

## IMPLEMENT with Crash Safety

Use linked worktree isolation by default for STANDARD+ implementation and automatically when parallel or overlapping work requires it. Run `worktree_preflight.py` and block on submodule, mapping, ignore, setup or baseline failure. A primary-checkout exception must be explicit, serial and uncontended. Do not make the user manually manage isolation for normal work.

Dispatch a unique fresh implementer session per task. For each behavior task, run the selector through `execution_journal.py`: expected assertion RED, same-selector GREEN, REFACTOR while green and required REGRESSION. Syntax/import/environment failure and first-run PASS are not RED.

For non-trivial work, register the Work Item before significant mutable work and checkpoint meaningful atomic boundaries in `.ai-runtime` so abrupt model/session interruption remains recoverable.

Git remains implementation fact. Do not hide or overwrite unrelated dirty work.

## SELF_VERIFY is Risk-Driven

Select checks automatically from the Impact Map:

- compile/typecheck/lint
- unit/integration/contract
- consumer/API compatibility
- frontend interaction/data flow
- UI behavior/visual/response fidelity
- DB migration/data integrity
- performance/reliability/security
- E2E where justified

`/test`, `/contract-verify`, `/ui-verify`, `/perf`, `/reliability` are specialist checks supporting this stage.

## REVIEW vs ACCEPT

REVIEW asks: is the engineering sound, complete and maintainable?

ACCEPT asks: did we actually satisfy the original requirement contract with evidence?

The builder's claim is not acceptance evidence.

Before whole-branch review, each implementation task requires two different fresh read-only Agents: specification compliance and code quality. They must differ from the implementer and bind the same final spec/diff hashes. A fix invalidates both reviews. Use `/workflow-diagnose` for evidence-backed analysis of routing, plan adherence, repetition, blockers, quality, conflicts and time/cost signals; every finding cites `path:line` and diagnosis never edits its inputs.

Internal review and mandatory third-party acceptance audit are distinct. Before every Work Item reaches `ACCEPTED`, seal `AUDIT_PACKET.md` and dispatch a different fresh-context, read-only Agent. It must produce `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`, independently cover the required audit axes and every acceptance criterion, and pass `validate_third_party_audit.py`. For high-risk work, prefer a different model/provider when available. If no provider is selected, use `/agent-provider` to offer built-in or registered external CLI choices. Never silently install or collect key values; external mode requires `AGENT_PROVIDER_READINESS.md` with a bounded live-probe PASS before dispatch.

## API Consumer Handoff

Whenever an API/interface change affects another consumer, either:

A. update the consumer in the same Work Item, or
B. create an explicit API_CONSUMER_HANDOFF with before/after contract, required consumer changes, examples, compatibility classification and pending owner.

Do not silently finish backend work while frontend is known to be broken or stale.

## State Truth

Use this precedence for active work truth:

1. Work Item artifact
2. `.ai-runtime` live registry/journal
3. Git worktree/diff/commits
4. compatibility summaries such as PROJECT_STATE / SESSION_CHECKPOINT / EXECUTION_CURSOR

If summaries disagree with Git/repository evidence, reconcile them; do not follow stale prose blindly.

## Completion

A Work Item may reach ACCEPTED only when:

- original acceptance criteria are covered
- all known affected consumers/layers are classified
- required implementation paths are real, not fabricated
- required verification evidence exists
- required consumer handoffs are resolved or the Work Item is explicitly partial/pending
- relevant regression risk is checked
- required strict RED-GREEN cycles and per-task fresh-Agent double reviews passed executable validation
- required workflow diagnosis is CLEAR
- a different fresh-context Agent approved the sealed evidence and the third-party audit validator passed
- integration state is truthful
- for UI work, the strict prototype-to-production fidelity gate passed

Completion is a claim that requires evidence.

Normal task completion additionally requires `INTEGRATED`: a local task commit, clean worktree, truthful integration state and integrate-gate PASS. Never sweep unrelated user changes into that commit; isolate or block instead.

Keep completion levels explicit: `ACCEPTED` proves the original requirement, `INTEGRATED` proves repository integration, and `RELEASED` proves delivery to the intended environment. Do not collapse them into a vague `DONE`.


## Workflow Enforcement

`/work` must route before editing. For any UI impact, production UI edits are blocked until an HTML prototype has been rendered, visually captured, presented, explicitly approved by the user, and locked. Read `WORKFLOW_ROUTER_RULES.md` and `PRE_EDIT_GUARD.md`.

## Bidirectional Contract Collaboration

Backend-to-frontend and frontend-to-backend changes are symmetric collaboration problems. Backend changes produce consumer guidance or direct consumer updates. Frontend data/behavior needs that are not supported produce an explicit backend capability request. Never hide a contract gap with fabricated client behavior or silent assumptions.

## Baseline Maintenance

Normal changes reuse the baseline. LEVEL_1 changes update targeted facts after acceptance. LEVEL_2 changes require baseline review. LEVEL_3 foundation changes require `/rebaseline`. New baselines are versioned as `PB-n` and `DS-n`.


## v4.3 Prototype Enforcement

Every UI-impacting request, including REFINE/MINOR work, requires `PROTOTYPE_REQUIREMENT=REQUIRED` and `PROTOTYPE_MODE=HTML`. A strategy, blueprint, component map, implementation plan, or native/component preview cannot substitute for the isolated `.html/.htm` artifact. Production UI edits remain blocked until visual evidence is presented, the user explicitly approves it, applicable coverage exists, and the UI lock is recorded.

Approval authorizes implementation; it does not prove implementation fidelity. Before editing production UI, require a complete measured specification, prototype-to-component map, and classified legacy structural diff. Before ACCEPT, require same-viewport prototype/production screenshots, diff evidence, `Target State Match: YES`, `Legacy Remaining: NO`, and final user fidelity confirmation.

Every UI-impacting request also requires adaptive experience evidence. Design by terminal/platform, orientation, input modality, usage context and promised business operation; render the HTML prototype for every materially different REQUIRED profile. Production UI editing requires a COMPLETE `ADAPTIVE_UI_CONTRACT.md` and adaptive plan gate PASS. Acceptance requires all REQUIRED profiles and operation/profile pairs VERIFIED, zero component consistency violations, zero critical operation failures, zero unintended clipping/overflow and adaptive acceptance gate PASS.

## Project-Specific Hard Requirements (server project)

These mandatory requirements were established for this Spring Boot server project and remain in force under v2.1:

### API Specification is a Source of Truth

- `docs/openapi.yaml`: API specification (must always match the latest implementation).

### Mandatory API Documentation Synchronization

14. **Mandatory API Documentation Synchronization**: Whenever an API endpoint is added, modified, deprecated, or removed, `docs/openapi.yaml` (and `docs/API.md`) MUST be updated synchronously before concluding the task. An API change is NEVER complete without documentation synchronization.

### Mandatory JAR Package Build on API Changes

15. **Mandatory JAR Package Build on API Changes**: Whenever an API endpoint is added, modified, or removed, a full Maven build and packaging (`mvn clean package -DskipTests` / `.\mvnw.cmd clean package -DskipTests`) MUST be performed to generate and verify the deployable JAR package.

### Completion Criteria Addition

For any task touching API endpoints, the Definition of Done additionally requires:

- API documentation (`docs/openapi.yaml` / `docs/API.md`) synchronized for any added/modified/deleted endpoints.
- Deployable JAR artifact (`mvn clean package -DskipTests`) successfully built whenever API endpoints were added/modified/deleted.
