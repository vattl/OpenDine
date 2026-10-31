# Security Audit — WI-013

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Threat Model

- Asset: 订单结账状态机、资金到账一致性、收款意向台账。
- Trust boundary: 收银端/管理端特权结账入口。
- Privilege escalation risk: 普通操作员不得自行绕过已确认收款会话直接强结。已通过强制要求 `admin:manage` 权限码、超管豁免、或通过现场店长密码/审批令牌授权核验。
- Audit & non-repudiation: 所有 `force: true` 强制结账行为均通过 `SecurityAuditService.recordPrivilegedAction` 写入 `t_operation_log`，记录操作人、门店、订单号及支付快照。
- Data integrity risk: 强结放行后，原子将该订单名下所有待确认与已确认收款意向收敛为 `COMPLETED`，防止意向滞留导致后续出码死锁。

## Findings

- 严格校验 `admin:manage` 权限，未通过校验时拦截并返回 403 `{"code": 403, "msg": "强制结账需要具备 admin:manage 权限"}`。
- 完整支持审批令牌 `approvalToken` 与店长现场密码授权机制，适应收银现场店长授权场景。
- 变更差异高风险凭据模式扫描无命中。
