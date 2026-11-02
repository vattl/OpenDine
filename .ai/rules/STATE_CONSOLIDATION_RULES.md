# State Consolidation Rules — v4.2

Avoid multiple competing sources of work truth.

## Authority order

1. Work Item — durable intent, impact, design, plan and acceptance state
2. `.ai-runtime` — active runtime/heartbeat/interruption state
3. Git/repository — actual code, diff and commit truth
4. Legacy `PROJECT_STATE`, `SESSION_CHECKPOINT`, `EXECUTION_CURSOR`, old task/workstream summaries — compatibility/read-only hints unless explicitly needed

## Rules

- Do not duplicate the same field across several state files when a canonical owner exists.
- `/continue` should recover from Work Item + runtime registry + Git first.
- Legacy summaries must not override newer runtime or Git evidence.
- Keep state writing lightweight; engineering work is primary.
