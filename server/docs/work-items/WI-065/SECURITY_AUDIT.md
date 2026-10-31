# Security Audit — WI-065

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Findings Addressed
- 会话并发安全：`t_dining_session` 携带 `revision` 乐观锁机制，更新时强校验 `expected_revision`，杜绝多端或多人并发协同覆盖。
- 数据真源安全：菜单与价格完全由服务端 `AiMenuAdapterService` 与 `DishShopOverrides` 真实读取，菜品价格强制使用整数分 `budget_fen` / `price_total_fen`，前端或大模型不可篡改。
- 菜品与过敏原安全：求解器前置硬过滤免辣制作支持（`non_spicy_customizable`）及成员过敏原（`allergens` 严格排查），不满足硬隔离约束的菜品严禁分配给目标成员。
- 落单防漂移与二次校对：草稿落单前必须经过 `validateSnapshot` 二次校价校库；若发生变动，原显式确认强制失效，杜绝以旧价落单。
- 强幂等保障：提交订单接口接入 `PaymentOrderNoUtil`，基于 `idempotency_key` 保证并发提交仅产生一笔正式订单，不重复扣费与出票。
- 提示词注入防护（Prompt Injection）：用户备注与成员偏好严格作为普通字符串处理与转义，绝不拼接入系统元指令，杜绝权限绕过与求解器被劫持。
- 云端权威与收银隔离：正式订单落盘直接归属于云端核心 `t_order` 状态机，严格对齐 KDS 架构单一云端真源。

## Residual Risk
- 试点阶段菜品画像（热量、过敏原、保底克重）若初期由商户手工录入不完整，系统将诚实降级标注，但不影响硬约束价格和免辣安全过滤。
