# Scenario Matrix — WI-013

| Scenario ID | Input / Context | Expected Outcome | Invariants | Verification Method | Result |
|---|---|---|---|---|---|
| SC-01 | 无 `admin:manage` 权限发起 `force: true` 结账 | 拦截并返回 403 / 4001 拒绝 | 安全凭据不越权 | 单元测试 | PENDING |
| SC-02 | 具有 `admin:manage` 且存在其他会话 `CONFIRMED` 意向 | 绕过阻断，订单结账成功置为 `success` | 订单最终一致性 | 单元测试 | PENDING |
| SC-03 | 强制结账成功后检查意向表 | 意向全部由 `CONFIRMED`/`PENDING` 转为 `COMPLETED` | 意向无死锁残留 | 单元测试 | PENDING |
| SC-04 | 具有 `admin:manage` 强制结账时 | 写入特权操作审计日志 `force_checkout` | 特权操作可审计 | 单元测试 | PENDING |
| SC-05 | 普通收银结账（`force: false`） | 原有资金校验逻辑完全保持不变 | 不影响既有流程 | 回归测试 | PENDING |
