# Documentation Rules

Responsibilities:

- PRD: intended product behavior
- PROJECT_STATE: current development state
- SESSION_CHECKPOINT: latest resume state
- ARCHITECTURE: current system architecture
- DATABASE: logical data model
- API: API contract
- openapi.yaml: API specification (must always match the latest implementation)
- CHANGELOG: meaningful release history
- Feature/Change/Bug: work-item knowledge
- Diff: explicit Current → Target transformation contract

Update only affected sections; do not rewrite everything.

PROJECT_STATE should be concise, not a diary.

SESSION_CHECKPOINT should remain operational and short-lived.

Before release, verify relevant docs are synchronized.


## Execution Cursor

`docs/EXECUTION_CURSOR.md` is the precise short-form resume pointer for active non-trivial work. Keep it smaller and more immediate than `SESSION_CHECKPOINT.md`. Do not use it as a diary.
