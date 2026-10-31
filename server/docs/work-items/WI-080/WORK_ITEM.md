# WORK ITEM — WI-080
## Request
用户要求重写开源主分支 README，讲清中小商家痛点、环境变量作用，并补足陌生人独立部署启动说明。用户“执行吧”授权落地。
## Type
CHANGE
## State
DESIGN
## Requirement Contract
### Goal
Make OpenDine onboarding accurate and executable for a fresh installation.
### Current behavior
README overclaims; Compose omits required JWT key; schema-only init lacks administrator and current migrations.
### Target behavior
Merchant-facing README linked to complete deployment guide; safe explicit empty-database bootstrap; configurable isolated Compose stack.
### Must preserve
No production data/keys accessed; existing database never silently initialized; KDS cloud authority; existing HTTP contracts and client UI.
### Acceptance criteria
- [ ] AC1 README states merchant problems, actual modules and third-party limitations without unsupported guarantees.
- [ ] AC2 Guide covers prerequisites, build, env purpose/injection, new DB, admin, clients, verification, upgrades and backups.
- [ ] AC3 Fresh bootstrap initializes current schema/RBAC and operator-selected BCrypt admin; nonempty DB rejected.
- [ ] AC4 Compose supplies required secrets, keeps DB/Redis private and payment keys outside public uploads.
- [ ] AC5 Automated checks and isolated MySQL startup/login evidence establish supported startup path; unavailable platforms stated truthfully.
### Open product questions
NONE. Built-in audit provider selected by user on 2026-10-31.
## Impact Summary
IMPACT_MAP.md
## Design Summary
IMPLEMENTATION_DESIGN.md
## Tasks / Vertical Slices
- [ ] T01 Fresh deployment bootstrap, configuration and user documentation.
## Acceptance Decision
PENDING
## Business Invariants
Cloud is sole KDS authority; passwords BCrypt; no example secret becomes live default; no existing business DB mutated.
## Integration / Release
NOT_INTEGRATED / NOT_RELEASED

