# Agent Entry — AI Development OS v4.3

Read `.ai/SKILL.md` first.

For normal work, use the unified `/work` lifecycle. Do not bypass its router or pre-edit guard.

Before broad discovery, read the durable Project Baseline. Validate relevant facts against repository evidence rather than rescanning the whole repository by default.

For any UI-impacting request, enter the UI Design Track and complete HTML prototype review before production UI edits.

For cross-layer changes, no frontend/backend layer may silently assume the other will adapt. Use direct same-Work-Item changes or explicit Contract Handoff artifacts.

Completion requires evidence, not agent assertion.

## v4.3 mandatory workflow rules

- Treat `.ai/rules/WORKFLOW_CORE.md` as the single authoritative lifecycle. `docs/WORKFLOW_V4_2.md` is compatibility/migration context only.
- For new products/material initiatives, complete `.ai/rules/PRODUCT_LIFECYCLE_RULES.md` before engineering implementation.
- Use `.ai/scripts/gate.py` for package, Work Item and release decisions; package PASS never proves acceptance or release.
- Do not edit production code until `IMPLEMENTATION_READY = YES`.
- Before production edits, implementation work must have `WORKTREE_READINESS.md` PASS from live Git/worktree mapping, submodule guard, setup and clean baseline test evidence. Linked worktree is the STANDARD+ default; a primary-checkout exception must be explicit.
- Behavior-changing tasks require observed, hash-chained `RED → GREEN → REFACTOR → REGRESSION` evidence. Broken tests, environment failures and first-run PASS are not RED.
- Every implementation task uses a unique fresh implementer Agent, then a different fresh read-only specification reviewer and another different fresh read-only code-quality reviewer. Fixes invalidate old snapshot-bound reviews. Task double review never replaces final third-party audit.
- Use `/workflow-diagnose` for evidence-based workflow self-diagnosis. Findings must cite real `path:line` evidence; unsupported metrics and mutation of diagnostic inputs are forbidden.
- Use the Work Item Impact Map as the affected-surface authority downstream.
- Preserve applicable business invariants and verify them before acceptance.
- Use Scenario Matrix coverage for STANDARD+ work.
- Distinguish ACCEPTED, INTEGRATED and RELEASED; do not collapse them into a vague DONE.
- Before implementation readiness, create `AUDIT_PLAN.md` and select mandatory audit tracks from requirement type, risk and affected surfaces; `validate_audit_plan.py --phase plan` must pass.
- A blocked audit must be archived and must drive code/configuration remediation, retest, packet resealing and a different fresh-context re-audit. Paper-only closure is forbidden.
- A normal completed task must have a task-scoped local Git commit and `gate.py work --phase integrate` PASS from a clean worktree. Do not commit unrelated user changes and do not push unless requested.
- Before ACCEPTED, seal `AUDIT_PACKET.md` and require a different fresh-context, read-only Agent to produce `AUDIT_RECEIPT.md` and `THIRD_PARTY_AUDIT.md`. `validate_third_party_audit.py` must pass; implementer self-approval, tests, security review, or package PASS cannot waive this gate.
- If no audit Agent provider is selected, offer the built-in Agent or a registered external CLI through `.ai/scripts/agent_provider.py`. Never silently install or accept secrets in chat/argv/repository files. An external provider is usable only after a bounded live probe passes; `EXTERNAL_PROVIDER` audits require hash-bound `AGENT_PROVIDER_READINESS.md` evidence.



## v4.3 prototype enforcement

For any UI-impacting work, set `PROTOTYPE_REQUIREMENT=REQUIRED` and `PROTOTYPE_MODE=HTML`. Never equate a written strategy, implementation plan, or native-framework preview with the required review prototype. Create an isolated renderable `.html/.htm` prototype, capture visual evidence, critique it, present it to the user, record explicit `Approval Status: APPROVED`, lock the approved UI, and only then edit production UI. This workflow has no per-Work-Item prototype or approval waiver.

Prototype approval is not implementation acceptance. Before production UI editing, require a complete measured specification, implementation map, and classified legacy structural diff, then pass `validate_ui_fidelity.py --phase plan`. Before ACCEPT, require same-viewport prototype/production screenshots, diff evidence, zero HIGH/CRITICAL deltas, `Target State Match: YES`, `Legacy Remaining: NO`, final production presentation, and explicit user fidelity confirmation through `validate_ui_fidelity.py --phase accept`. Functional usability or approximate resemblance cannot override these gates.

Visual fidelity is not functional completion. Before production UI editing, map every prototype datum/action in `PROTOTYPE_INTERACTION_CONTRACT.md`, create assigned Backend Capability Requests for API_EXTENSION/NEW_API, resolve NOT_SUPPORTED interactions by revising/re-approving the prototype, and pass `validate_ui_capabilities.py --phase plan`. Before ACCEPT, require every interaction and backend request VERIFIED with real end-to-end evidence, zero production fake/mock/placeholder interactions, zero unresolved backend capabilities, and a CLEAR `BACKEND_COORDINATION_REPORT.md` through `validate_ui_capabilities.py --phase accept`. Any OPEN coordination item must be shown to the user and keeps the UI BLOCKED/PARTIAL.

Responsive fidelity is not adaptive UX completion. Before production UI editing, create `ADAPTIVE_UI_CONTRACT.md` covering every REQUIRED terminal/platform, orientation, input modality and usage context; define consistent component families/variants and every promised business operation; provide prototype evidence for each required profile; and pass `validate_ui_adaptive.py --phase plan`. Before ACCEPT, require real production evidence for every required profile and operation/profile pair, zero component consistency violations, zero critical operation failures, zero unintended clipping/overflow, and `validate_ui_adaptive.py --phase accept` PASS. A single desktop screenshot or generic breakpoint claim cannot satisfy this gate.

## Project-Specific Hard Rules (server project)

- **Mandatory API Documentation Sync**: Whenever any API endpoint is added, modified, or removed, `server/docs/openapi.yaml` (and `server/docs/API.md`) MUST be updated synchronously before concluding the task.
- **Mandatory JAR Package Build on API Changes**: Whenever any API endpoint is added, modified, or removed, a full Maven compilation and packaging command (in `server/`: `mvn clean package -DskipTests` / `.\mvnw.cmd clean package -DskipTests`) MUST be executed to generate the runnable JAR artifact before concluding the task.
- **KDS Architecture Source of Truth**: Before any KDS auth, API, WebSocket, database, delivery, or failover change, read `server/docs/KDS_ARCHITECTURE.md` and the cross-repository KDS-CA-1.0 document it references. Cloud is the only business authority; cashier is proxy/cache only. Historical replication documents and SQL cannot override this invariant.
