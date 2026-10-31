# Migrating from v3.6 to v4.0

v4.0 retains v3.6 capabilities but changes orchestration.

## Keep
- all specialist rules/checks
- UI design/fidelity tooling
- workstream/worktree isolation
- crash-safe runtime registry
- evidence integrity/anti-fake rules
- capability repair
- cross-layer consistency
- performance/reliability/release governance

## Change

### Commands
Use `/work` as the default entry instead of deciding among many lifecycle commands. Existing commands remain compatible/expert aliases.

### Discovery artifacts
Prefer one `IMPACT_MAP` over independently creating capability map + consumer matrix + layer matrix + contract delta unless those extra artifacts materially help.

### Design artifacts
Prefer one `IMPLEMENTATION_DESIGN` with specialist subsections/attachments.

### State
Treat Work Item + runtime registry + Git as primary truth. PROJECT_STATE/CHECKPOINT/CURSOR remain compatibility summaries.

### Verification
Treat test/contract/UI/perf checks as automatically selected checks inside SELF_VERIFY rather than separate user-managed lifecycle steps.
