# Workflow Rules — v4.0

## One lifecycle, adaptive depth

All normal engineering work follows the Unified Workflow Core. Commands are entry points or specialist tools, not separate lifecycles.

Primary user-facing entry points:
- `/work` — normal work item
- `/continue` — resume existing work
- `/review` — independent review
- `/release` — release readiness/release flow
- `/incident` — production incident fast lane
- `/ui` — UI-led work; still belongs to a Work Item

Compatibility/expert commands remain available but must attach to the same Work Item.

## Routing

`/feature`, `/change`, `/bug`, `/repair` are typed aliases into `/work`.

`/bug` may automatically escalate to capability repair when repeated patches/shared rules/multiple consumers are discovered.

`/test`, `/verify`, `/contract-verify`, `/ui-verify`, `/perf`, `/reliability`, `/policy-check` are checks/audits supporting SELF_VERIFY/REVIEW/ACCEPT rather than mandatory user-managed stages.

`/workstream` is execution infrastructure and should normally be automatic.

## Artifact minimization

Prefer these core artifacts for non-trivial work:
1. WORK_ITEM
2. IMPACT_MAP
3. IMPLEMENTATION_DESIGN
4. TASKS/vertical slices
5. ACCEPTANCE_REPORT

Only create specialist artifacts when material (UI lock, DB migration, API consumer handoff, incident report, etc.).

## State precedence

Work Item → runtime registry/journal → Git → compatibility summaries.

Do not maintain multiple conflicting narratives.

## API Documentation Synchronization Rule

Whenever a workflow (Feature, Change, Bug, or Continue) touches API contracts:

- Adding a new endpoint
- Modifying request parameters / headers / body
- Updating response schemas / status codes / error codes
- Deprecating or removing an endpoint

`docs/openapi.yaml` (and `docs/API.md`) MUST be updated before advancing to `REVIEW`, `SYNC`, or `RELEASE_READY`.

An API change without corresponding OpenAPI documentation is treated as an incomplete task and an automatic review-blocking finding.

## Mandatory JAR Build on API Changes

Whenever an API endpoint is added, modified, deprecated, or removed:

- A complete Maven build and packaging (`mvn clean package -DskipTests` / `.\mvnw.cmd clean package -DskipTests`) MUST be executed.
- The build must exit with status `BUILD SUCCESS` and output a valid deployable JAR artifact under `target/`.
- Failure to build the JAR or compilation/packaging breakage is treated as a blocking error that prevents completing the task.
