# Impact Map — WI-065

## Authoritative Owner
- 菜品食材、营养与风味扩展：`t_dish_food_profile`，由门店商家配置管理，以数据库为权威。
- 餐桌协同会话与版本号：`t_dining_session.revision`，云端 MySQL 为唯一状态真相。
- 确定性求解引擎：`com.lanf.ai.solver.LexicographicalMealSolver` 为核心计算权威，LLM 仅为意图解释层。
- 订单草稿与二次复核：`t_order_draft`，以创建正式订单前的二次校价为安全防线。
- 正式订单与 KDS 调度：现有 `IOrderService` 与 `t_order`，维持既有交易与出餐权威不变。

## Change Propagation
```text
Diner Intent / Constraints / Patches
→ POST /api/v1/ai/dining-sessions (create or update session with revision)
→ POST /api/v1/ai/meal-plans:solve (fetch store menu snapshot + SHA-256 version)
→ LexicographicalMealSolver (Stage 1 Hard Filter + Stage 2 Multi-Objective Scoring)
→ Return 1~3 Candidate Plans + Explanation Cards
→ POST /api/v1/ai/order-drafts (create OrderDraft with 5-minute TTL)
→ POST /api/v1/ai/orders (Double validate menu_version & real-time stock -> idempotent create formal t_order)
→ Publish KDS Ticket Event -> Kitchen Screens
```

## Layer Coverage
| Layer | Classification | Evidence / obligation |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | 本仓库无生产 UI 代码（消费者为外部微信小程序及前端） |
| Mini Program / Agent | AFFECTED | 消费新 `/api/v1/ai/*` 接口与 MCP 工具；旧版保留 `add_ai_cart` |
| API contract | AFFECTED_COMPATIBLE | 新增 `/api/v1/ai/*` 体系与 Remote MCP 端点，不改动旧 `/order/*` 契约 |
| Controllers | AFFECTED | 新增 `AiSmartDiningController` 与 `AiMcpController` |
| Domain/service | AFFECTED | 新增 `com.lanf.ai` 包结构及求解器、会话服务、菜单适配器、草稿服务 |
| Persistence | AFFECTED | 新增 V044 增量表：`t_dish_food_profile`, `t_dining_session`, `t_dining_session_member`, `t_meal_plan`, `t_order_draft` |
| Inventory / Pricing | VERIFIED_PRESERVED | 金额统一采用整型分；必须二次校验库存与单价；不修改主库扣减规则 |
| KDS | VERIFIED_PRESERVED | 正式单创建后仍调用原 KDS 出餐分发机制，KDS 架构与云端真源不变 |
| Security / RBAC | AFFECTED_COMPATIBLE | 区分公开查询与高风险下单接口；配置 API 权限字典与匿名会话保护 |

## Consumers
| Consumer | Status | Obligation |
|---|---|---|
| WeChat Mini Program | HANDOFF | 支持餐桌 DNA 成员录入、方案对比与最终明确确认 |
| AI Coding Agents / MCP Clients | HANDOFF | 支持调用标准 Remote MCP 7 大工具，遵守确认与幂等规范 |
| Cashier / Merchant Console | COMPATIBLE | 保持原有收银开单与接单操作无缝显示 AI 渠道订单 |

## Material Unknowns
0
