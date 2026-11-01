# Impact Map — WI-080
Risk Level: HIGH
UI Impact: NONE
Contract Impact: NONE
Security Impact: YES
Data / Migration Impact: YES
Reliability / Performance Impact: YES

## Authoritative Owner
Deployment onboarding: root README.md and deploy/. Bootstrap uses existing server migration implementations, never changes live API semantics.
## Layer Coverage
| Surface | Classification | Evidence / change |
|---|---|---|
| Documentation | AFFECTED | README.md; new server/docs/DEPLOYMENT.md; historical deployment guide notice |
| Configuration | AFFECTED | deploy/docker-compose.yml, Dockerfile, environment example, nginx private path protection, root ignore |
| Data/bootstrap | AFFECTED | deploy/sql/init.sql, new FreshInstallBootstrap CLI, existing migrations read/reused |
| Security | AFFECTED | operator supplied admin password, independent runtime secrets, nonempty DB refusal |
| Tests | AFFECTED | bootstrap unit/integration and deployment validation |
| Server HTTP API | UNAFFECTED | no endpoint changes |
| Client UI | UNAFFECTED | guide documents actual current build/address behavior; no client edits |
| KDS business logic | UNAFFECTED | existing schema migrations only, cloud authority preserved |
| Release | NOT_IN_SCOPE | local commits only; no push or production rollout |
Baseline drift: open-source monorepo contains clients, unlike PB-2 original sibling-only wording.
Material UNKNOWN count: 0

