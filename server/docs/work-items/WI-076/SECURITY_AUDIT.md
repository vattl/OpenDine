# Security Audit — WI-076

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Medium Open: 0
Low Open: 0
Secret Scan: PASS
Dependency Scan: PASS
SAST: PASS

## 1. Threat Modeling & Invariant Verification

- **T1: 越权与多门店隔离风险**
  - **防护设计**：外卖自动派发严格从当前订单主键 `t_order.id` 获取归属 `shop_id` 与绑定 `t_takeout_delivery` 记录，由系统后端事件内部触发，无任何前端传入参数注入风险，绝不产生跨门店或跨租户越权。
- **T2: 重复派单与资金计费防重风险**
  - **防护设计**：真省钱及第三方聚合配送涉及实际运费与手续费扣除。实施状态机三层防重拦截（`zsq_dispatch_status` 与 `dispatch_status`）：凡已处于 `dispatched`（已发配送）、`delivering`（履约中）、`completed`（已完成）或 `pending`（发起中）的订单，自动跳过，坚决杜绝重复呼叫与重复扣费。
- **T3: 第三方接口超时与事务雪崩风险**
  - **防护设计**：遵守 `docs/KDS_ARCHITECTURE.md` 规范。外卖自动叫骑手位于 `@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)` 阶段，在主事务成功提交后执行。内部使用独立 try-catch 包裹，外部接口超时或异常时仅记录 WARN 日志，绝不阻断核心划菜出餐状态的持久化。

## 2. Invariant & Security Decision

All security invariants verified through automated tests in `KdsTakeoutAutoDispatchTest`.
Security Decision: APPROVED
