# /work — Unified Work Item Entry (v4.3)

Use for normal product and engineering work. `/work` owns routing and specialist-track selection.

## 1. REQUEST
Create/reuse one Work Item and capture the raw request.

For a new product/material initiative, route through `/project`, `/research` and `/prd` first. Do not use an engineering Work Item to manufacture product approval.

## 2. UNDERSTAND — PRODUCT TRUTH
Define Goal / Current / Target / Must Preserve / Acceptance / Open Questions. Identify relevant known business invariants. Do not guess product decisions that materially change the target.

## 3. BASELINE FAST CONTEXT
Read project profile, architecture map, business rules, and design-system profile when UI may matter. Treat baseline as cached context; repository evidence wins.

## 4. ROUTE — TRACK SELECTION ONLY
Classify work type, complexity/risk and required tracks/gates. ROUTE does not choose exact files or implementation details.

Create `AUDIT_PLAN.md` and derive required audit tracks from type, risk and affected surfaces. Run `validate_audit_plan.py --phase plan`; missing specialist coverage blocks implementation readiness.

Possible required tracks include UI Design, Contract Collaboration, Migration/Data, Reliability/Performance, Security and Baseline Review.

## 5. DISCOVER — ENGINEERING TRUTH
Build/update one authoritative Impact Map from focused repository evidence. Resolve the authoritative owner, consumers, propagation path, interfaces, UI/data/runtime/release surfaces and relevant invariants.

Material `UNKNOWN` blocks implementation.

## 6. DESIGN
Produce one Implementation Design for non-trivial work. Specialist outputs become sections/attachments of this Work Item, not parallel lifecycles.

## 7. PLAN
Split into end-to-end verifiable vertical slices. Build a Scenario Matrix for STANDARD+ work. Each slice must state business outcome, start point, end point, observable result and DoD.

Create `TDD_CYCLE_REPORT.md` and `TASK_AGENT_LEDGER.md`. Map every implementation task to a behavior-test selector or an allowed explicit N/A classification and reserve fresh implementer, specification-review and code-quality-review slots.

## 8. IMPLEMENTATION_READY — HARD GATE
Evaluate `.ai/rules/IMPLEMENTATION_READY_RULES.md`. Production edits are forbidden until the result is `YES`.

For implementation work, generate `WORKTREE_READINESS.md` with `worktree_preflight.py`; setup and baseline tests must pass. Linked worktree is the default for STANDARD+ work. A primary-checkout exception must be explicit, serial and uncontended.

Create `DELIVERY_GATE.md` and run `python .ai/scripts/gate.py work --work-item <dir> --phase ready`. Ready validates plans and initialization evidence, not future review results. A failed or unrun executable gate keeps the result `NO`.

## 9. IMPLEMENT
Implement one task at a time with a new fresh-context implementer Agent. For behavior work, use `execution_journal.py` to observe the expected assertion RED, make the minimum GREEN change, refactor while green and record required regression. No silent mocks, fake completion, local workaround that contradicts the design, or undocumented contract substitution.

## 10. SELF_VERIFY
Derive checks from the Impact Map + Scenario Matrix + Business Invariants. Verify technical behavior and cross-layer propagation.

## 11. REVIEW
For each task, dispatch a different fresh read-only spec reviewer and another different fresh read-only quality reviewer. Both bind the same final spec/diff hashes. Important findings return to IMPLEMENT and invalidate both reviews. After all task reviews pass, run the independent whole-branch pass for omissions, patch smells, stale consumers, regression risk, architecture drift, invariant violations and false completion.

## 12. THIRD_PARTY_AUDIT — HARD GATE
After internal review, security, and test evidence are final, seal `AUDIT_PACKET.md`. Dispatch a different fresh-context, read-only Agent using `/third-party-audit`. Require its session receipt, criterion-by-criterion report, zero open CRITICAL/HIGH findings, and `validate_third_party_audit.py` PASS.

If no audit provider is configured, use `/agent-provider` to offer the built-in Agent or registered external Agent CLIs. External selection must pass install/auth diagnosis and a bounded live probe; `EXTERNAL_PROVIDER` audits require hash-bound `AGENT_PROVIDER_READINESS.md` evidence. Never accept CLI/key presence alone as readiness.

The auditor reports; it does not repair implementation. Valid findings return the Work Item to IMPLEMENT, invalidate the old packet, and require a new independent audit.

Before rerunning, archive the blocked receipt/report under `audit-history/<session-id>/`, fix code/configuration, rerun tests, record `AUDIT_REMEDIATION.md`, and seal a new packet. Status-only edits cannot close findings.

## 13. ACCEPT
Re-read original requirement and acceptance criteria. Require evidence for every material requirement, scenario, invariant and affected surface.

When routed, or when retries/review rejections/process conflicts occurred, run `/workflow-diagnose`; acceptance requires a validated CLEAR report. A structurally valid BLOCKED diagnosis is not acceptance.

Run the security, test, independent-review, mandatory third-party-audit, and acceptance gates in `DELIVERY_GATE.md`, then run the work gate with `--phase accept`.

## 14. BASELINE UPDATE
Only after acceptance, update Project/Architecture/Design/Business baseline when the accepted change intentionally creates durable new project truth.

## 15. INTEGRATE / optional RELEASE / optional MONITOR
`ACCEPTED`, `INTEGRATED`, `RELEASED` and `MONITORED` are distinct states. Do not require deployment for work whose scope ends at engineering or repository completion.

Stage only Work Item changes, review the staged diff, create a descriptive local commit, set integration truth, and run `gate.py work --phase integrate` from a clean worktree. Do not call the task complete at merely ACCEPTED/READY_TO_COMMIT. Never include unrelated user changes and never push without authorization.

## Critical principles
- Understand before changing.
- Fix the capability, not only the symptom.
- Impact Map is the Work Item's affected-surface authority.
- No affected layer may silently assume another layer will adapt.
- Any UI impact requires an HTML/HTM prototype, visual reference, explicit user approval, and UI lock. Native previews, silence, inference, and per-Work-Item waivers do not satisfy the gate.
- Any UI impact also requires a complete prototype interaction capability contract. Missing backend capabilities become assigned requests and visible coordination items; they may not be replaced with fake production UI or hidden at completion.
- Any UI impact requires an adaptive UI contract derived from terminal/platform, orientation, input modality, usage context and promised business operations. Every REQUIRED profile needs prototype and production evidence; arbitrary component sizing or lost breakpoint actions block completion.
- Completion requires evidence; an agent's claim is not evidence.
- Acceptance requires an independently sealed and validated third-party Agent audit; the implementer cannot approve its own work.
- External Agent setup requires explicit install/login authorization, never records secret values, and remains blocked until a real live probe passes.
- Business invariants must survive the change.
