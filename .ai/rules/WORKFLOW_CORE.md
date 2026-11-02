# Unified Product Delivery Workflow Core — v4.3

This file defines the authoritative normal engineering lifecycle.

## Core objects

1. Project Baseline — durable project context
2. Work Item — one unit of requested change
3. Business Invariants — durable domain truths
4. Impact Map — authoritative affected-surface map
5. Implementation Design — coherent solution
6. Vertical Slices + Scenario Matrix — executable/observable plan
7. Acceptance Evidence — proof of completion
8. Third-Party Audit Packet — immutable evidence submitted to an independent Agent

## Product inception lifecycle

For new products/material initiatives, complete:

`IDEA → RESEARCHED → PROJECT_APPROVED → PRD_APPROVED`

using `.ai/rules/PRODUCT_LIFECYCLE_RULES.md`. Existing-product maintenance may route this track as NOT_APPLICABLE with rationale.

## Engineering lifecycle

### REQUEST
Create one Work Item identity.

### UNDERSTAND
Resolve product intent: goal, current/target behavior, must-preserve behavior, acceptance and open product questions. No technical scope guessing here.

### BASELINE FAST CONTEXT
Load reusable project context. Repository evidence overrides stale baseline.

### ROUTE
Select required tracks/gates only. Do not decide exact implementation.

Create `AUDIT_PLAN.md` from requirement type, risk and affected surfaces. The audit-plan gate must pass before implementation readiness.

### DISCOVER
Establish engineering reality and create the Impact Map. Material unknown surfaces block progress.

### DESIGN
Create one implementation design. UI/contract/migration/NFR/security tracks attach here when required.

### PLAN
Create vertical slices and scenario coverage with observable business outcomes. Map implementation tasks into TDD and fresh-Agent double-review ledgers.

### IMPLEMENTATION_READY
Single hard pre-edit gate. Implementation work also requires live worktree/setup/baseline readiness and complete execution-discipline plans. `NO` means production edits are blocked.

### IMPLEMENT
Execute each task with a unique fresh implementer. Behavior changes use an observed, hash-chained `RED → GREEN → REFACTOR` cycle before regression. Execute with safe Git/workstream/recovery infrastructure.

### SELF_VERIFY
Prove technical behavior using checks selected from Impact Map, Scenario Matrix and invariants. Record real commands/results; final PASS cannot replace a missing RED.

### REVIEW
For every task, run a different fresh read-only specification reviewer and another different fresh read-only code-quality reviewer against the same final spec/diff snapshots. Fixes invalidate old reviews. Then run the independent whole-branch review for omissions, regressions, local patches, stale consumers, fake success, architecture drift and invariant breakage.

### THIRD_PARTY_AUDIT
Seal the acceptance evidence and submit it to a different fresh-context, read-only Agent. The independent auditor must verify every required review axis and every original acceptance criterion. A failed or stale audit returns the Work Item to implementation and requires a newly sealed packet.

Archive every failed audit. Findings must drive real code/configuration remediation, retest, resealing and a different fresh-context re-audit; paper closure is forbidden.

### ACCEPT
Prove the user's requested business outcome against original acceptance criteria. Required strict-TDD, task-Agent double-review and workflow-diagnosis gates must pass. Tests alone are insufficient. `ACCEPTED` is forbidden until the mandatory third-party audit validator passes.

### BASELINE UPDATE
After acceptance, promote intentional durable changes into project/design/architecture/business baseline.

### INTEGRATE
Create the task-scoped local Git commit and perform semantic/Git integration checks. Normal task completion requires a clean-worktree `work --phase integrate` PASS; acceptance without a commit is `READY_TO_COMMIT`, not complete.

### RELEASE / MONITOR
Optional depending on scope and project policy. Engineering work may validly end at ACCEPTED or INTEGRATED.

When release is in scope, use distinct evidence-backed states:

`RELEASE_READY → DEPLOYED → PRODUCTION_VERIFIED → RELEASED → MONITORED → CLOSED`

Package validation, release preparation and deployment are not interchangeable.

## Specialist tracks

UI design/fidelity, adaptive multi-device UX, contract collaboration, capability repair, migration/data, performance/reliability, security, accessibility, multi-agent orchestration, strict TDD, worktree initialization, workflow diagnosis and release governance are specialist tracks/checks inside this lifecycle, not separate competing workflows. Third-party Agent cross-audit is a universal acceptance control, not an optional specialist track.

## Executable gate

Use `.ai/scripts/gate.py` as the scope-honest orchestrator:

- `package` validates installation/package integrity only;
- `work --phase ready|accept|integrate` validates the routed Work Item;
- `release` requires accepted work, Git integration, artifact, deployment, smoke and production-verification evidence.

Required gates that are missing, unexecuted, pending or failed block the transition.

## State authority

- durable work truth: Work Item + accepted project baseline
- runtime execution truth: `.ai-runtime`
- code truth: Git/repository
- legacy state summaries are compatibility aids only

## Incident fast lane

`DETECT → TRIAGE → MITIGATE → STABILIZE → ROOT_CAUSE`

Permanent fixes create or re-enter a normal Work Item. Do not use incident urgency as a permanent excuse to bypass engineering controls.
