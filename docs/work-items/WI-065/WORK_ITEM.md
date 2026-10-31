# WORK ITEM — WI-065

## Request
依据《深圳烧烤店 AI 智能配餐与点餐系统 PRD V1.0》与架构执行方案，落地深圳单店真实菜单驱动的多人协同智能点餐后端能力（M1最小可用闭环），包括数据模型、菜单适配器、两阶段确定性约束求解器、餐桌会话管理、双重校价订单草稿与对外 REST / MCP 接口。

## Type
FEATURE / AI / ALGORITHM / API

## State
ACCEPTED

## Requirement Contract

### Goal
在 Spring Boot 2.3 / Java 8 架构下，实现真实菜单驱动的多人协同智能配餐服务。满足 6人、150元、2人不吃辣、健身控重等复杂硬约束与多目标优化，提供确定性整数求解、动态微调解释、不可行协商、二次校价草稿及 7 大 MCP 工具。

### Target behavior
- 提供 `t_dish_food_profile`、`t_dining_session`、`t_dining_session_member`、`t_meal_plan`、`t_order_draft` 数据持久化与版本控制。
- 菜单适配器实时读取 `t_dish` 与 `t_dish_shop` 在售可点数据，计算数据版本摘要 `menu_version`，绝不虚构菜品或写死售价；未接入菜单返回 `REQUIRES_MENU_DATA`。
- Java 原生两阶段词典序约束求解器：阶段一严格过滤硬约束（预算 ≤ Budget 分、免辣隔离、过敏原安全排除、库存上限）；阶段二根据均衡/预算/吃饱等策略进行多目标效用评分；不可行时计算最小可行预算差额。
- 提供结构化餐桌会话管理，维护成员卡片（餐桌 DNA），支持携带 `revision` 乐观锁并发保护与动态意图补丁。
- 订单草稿在落单前强制二次校验价格与库存；通过后用户显式确认，幂等生成正式订单并接入现有 `t_order` 及 KDS。
- 提供 `/api/v1/ai/*` REST 接口以及标准 Remote MCP 7 大工具端点。

### Must preserve
- INV-ORDER-001、INV-ORDER-002、INV-TABLE-001、INV-KDS-001。
- 现有 `OrderController`、收银加退菜、KDS 云端唯一权威架构不变。
- 保持对老版本小程序 `<<<ACTION:add_ai_cart|PAYLOAD>>>` 的向后兼容。
- 保持深圳店与其它门店的强多租户隔离。

### Acceptance criteria
- [x] 数据库 V044 增量迁移脚本与实体映射健全。
- [x] 菜单适配器准确计算在售菜品与版本 Hash，无真实数据时返回 `REQUIRES_MENU_DATA`。
- [x] 求解器稳定复现「6人/150元/2人不辣/健身/均衡」用例，求解延迟 < 50ms，且绝无超预算或辣度违规。
- [x] 动态补丁微调准确计算新旧方案差异，未修改约束不丢失。
- [x] 预算不足等不可行场景诚实返回 `INFEASIBLE` 并计算精确最小差额。
- [x] 订单草稿支持提交前二次校价与校库存校验，变动时自动阻断并失效原确认。
- [x] 7 大 MCP 工具契约符合规范，写操作强制要求授权与幂等。
- [x] 自动化测试集覆盖 TC01~TC14，通过 `mvnw.cmd clean package -DskipTests` 并同步更新 OpenAPI。

## Business Invariants
- Applicable: INV-ORDER-001, INV-ORDER-002, INV-TABLE-001, INV-KDS-001, INV-SHOP-001
- Target promotion after acceptance: AI Dining Hard Constraints Enforced (Budget in Cents, Non-Spicy Isolation, Allergen Defense, Real Menu Only).

## Impact Map Authority
`docs/work-items/WI-065/IMPACT_MAP.md`，Material UNKNOWN = 0。

## Scenario Matrix
`docs/work-items/WI-065/SCENARIO_MATRIX.md`。

## Implementation Ready
`IMPLEMENTATION_READY = YES`

## Tasks / Vertical Slices
- [x] T01 数据库实体、Mapper 与 DTO 架构搭建 (V044 对应实体与仓储)。
- [x] T02 真实菜单适配器与版本 Hash 服务 (AiMenuAdapterService)。
- [x] T03 两阶段确定性约束规划求解器与不可行协商引擎 (LexicographicalMealSolver)。
- [x] T04 餐桌协同会话与订单草稿服务 (DiningSessionService, OrderDraftService)。
- [x] T05 REST API 控制器与错误码体系 (AiSmartDiningController)。
- [x] T06 Remote MCP 工具集适配层 (AiMcpToolService)。
- [x] T07 自动化测试套件 (TC01~TC14)。
- [x] T08 OpenAPI/API 文档同步、代码审查与全量 Maven 打包。

## Integration / Release
目标为 `feat/ai-smart-dining` 分支 ACCEPTED；保持现有生产代码主干稳定。

## Acceptance Decision
ACCEPTED

