# Adaptive Workflow

## Purpose

Use the lightest workflow that safely solves the task. Process is a safety tool, not the goal.

## Complexity Levels

### TRIVIAL
Use for localized, low-risk edits such as copy, labels, small visual adjustments, simple constants, and obviously isolated fixes.

Default flow:

CONTEXT CHECK → EDIT → LOCAL VERIFICATION

Do not create persistent Diff/Spec/Task documents unless the edit has hidden structural impact.

### STANDARD
Use for ordinary feature work or behavior changes with limited blast radius.

Default flow:

RELEVANT CONTEXT → CONCISE CURRENT/TARGET → IMPLEMENT → TEST → UPDATE STATE IF NEEDED

A persisted Diff is optional unless replacement/removal/move semantics matter.

### STRUCTURAL
Use when changing page structure, component hierarchy, workflow, module boundaries, replacing implementations, or removing/moving existing behavior.

Required flow:

CURRENT STATE → TARGET STATE → STRUCTURAL DIFF → IMPLEMENTATION → LEGACY CLEANUP → DIFF VERIFICATION → TEST

### CRITICAL
Use for payments, authentication/authorization, destructive or complex migrations, sensitive data, core transaction flows, major architecture changes, high-concurrency logic, or changes with large production blast radius.

Required flow:

FULL CONTEXT → IMPACT/RISK ANALYSIS → CURRENT/TARGET/DIFF → MIGRATION/ROLLBACK AS NEEDED → TASKS → IMPLEMENT → TEST → REVIEW → SYNC → RELEASE GATE

## Escalation Rule

Start with the lowest reasonable level and escalate when repository evidence reveals greater risk.

Examples:

- A CSS tweak that requires replacing the page shell escalates TRIVIAL → STRUCTURAL.
- A simple field addition that requires migrating millions of rows escalates STANDARD → CRITICAL.

## De-escalation Rule

Do not keep a task at a higher ceremony level when inspection proves the change is isolated and low risk.

## Engineering Judgment

Rules are guardrails, not a substitute for engineering judgment.

The agent may choose a better implementation path than an earlier plan when new evidence appears, but must:

1. Explain the material reason internally or in project artifacts when needed.
2. Update the Diff/Task/State if the active contract changes.
3. Preserve user intent and safety constraints.
4. Re-verify affected behavior.

## No Ceremony for Ceremony's Sake

Do not create documents, task files, or review reports that add no useful project memory, risk control, or verification value.


## Interruption Safety by Complexity

- TRIVIAL: no persistent execution cursor required unless interruption actually occurs.
- STANDARD: use cursor/atomic steps when work spans multiple meaningful edits or tools.
- STRUCTURAL: maintain cursor and atomic checkpoints during implementation.
- CRITICAL: maintain cursor, atomic checkpoints, explicit validation state, and recovery notes.
