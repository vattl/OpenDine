# WORK ITEM — WI-058

## Request

依据《后端业务治理审计与渐进式执行方案 V1.0》先完成阶段 0：统一后端业务不变量基线，建立可版本化的治理路线与契约清单，阻断后续分支再次回退。

## Type
MAINTENANCE / REPAIR

## State
ACCEPTED

## Requirement Contract

### Goal

让订单、价格、桌台、套餐、支付、退款、审批和 KDS 的关键业务真相只有一个权威来源，并使接口、权限、兼容路由、错误码和状态值可以被重复生成与检查。

### Current behavior

- `.ai/project/business-rules.json` 已有支付/KDS 不变量，但 `docs/project/BUSINESS_RULES.md` 仍声明没有项目不变量。
- 审计方案中的订单、价格、桌台、套餐和审批规则尚未进入耐久基线。
- 后续治理事项没有一个带稳定编号、依赖和验收边界的总路线图。
- 接口/权限/路由别名/错误码/状态值缺少同一份可复核清单。

### Target behavior

- `.ai/project/business-rules.json` 是机器可读权威源，`docs/project/BUSINESS_RULES.md` 与其内容一致并说明同步规则。
- 新增审计确认的业务不变量，并为每条记录 owner 与 verification。
- 建立 WI-059～WI-069 的治理路线、依赖和交付边界。
- 增加可重复运行的基线校验/清单生成工具，提交生成的契约清单。

### Must preserve

- 不改变任何运行时 API、数据库结构或业务行为。
- 保留现有支付和 KDS 不变量的 ID 与语义。
- KDS 云端唯一业务权威不变。

### Acceptance criteria

- [ ] 两个业务规则文件不再矛盾。
- [ ] 审计方案要求的六条新增核心不变量进入权威源。
- [ ] 后续治理 Work Item 的顺序、依赖、主要交付和验收边界明确。
- [ ] 契约清单可重复生成且校验通过。
- [ ] 相关基线测试与 Maven 测试通过。

### Open product questions

无。本 Work Item 只固化已审计确认的现有目标，不引入新业务决策。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 统一业务不变量候选权威源和人类可读视图。
- [x] T02 固化治理路线图与兼容策略。
- [x] T03 生成并校验后端契约清单。

## Verification Evidence

见 `TEST_REPORT.md`、`SECURITY_AUDIT.md`、`REVIEW_REPORT.md` 与 `ACCEPTANCE_REPORT.md`。

## Review

PASS

## Acceptance Decision

ACCEPTED

## Consumer Handoffs

NONE：本 Work Item 不修改运行时契约。

## Integration / Release

工程范围止于 ACCEPTED/INTEGRATED，不包含部署。

## Related IDs

Workstream: backend-governance-v1
UI: NOT_APPLICABLE
Capability: project-baseline / contract-inventory
Commits: PENDING

## Business Invariants

- Applicable invariant IDs: INV-PAY-001, INV-PAY-002, INV-PAY-003, INV-KDS-001
- New invariant candidates: INV-ORDER-001, INV-ORDER-002, INV-PRICE-001, INV-TABLE-001, INV-COMBO-001, INV-APPROVAL-001

## Impact Map Authority

- Impact map path: `docs/work-items/WI-058/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-058/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`
