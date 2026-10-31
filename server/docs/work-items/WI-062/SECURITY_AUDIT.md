# Security Audit — WI-062

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Findings addressed
- 删除 DB 未命中时的代码清单静默授权，防止环境间策略漂移。
- 映射缺失与首次加载失败均失败关闭；失败重载不会清空最后成功快照。
- 入口权限只允许发起精确动作审批，不能直接获得执行权。
- 无效、过期或已使用审批令牌返回 DENY；严格绑定和一次性核销继续由 `ApprovalService` 负责。
- 动作显式 DENY 与入口显式 DENY 均优先；超管不绕过显式 DENY 和策略评估。
- 单动作执行权限不扩散到同域其他动作。

## Residual risk
部署环境若跳过 V041，部分接口会按失败关闭返回 403；这是预期安全行为，运维需先完成迁移并观察启动漂移日志。WI-063 尚未切换实际高风险 Controller，因此当前业务操作仍使用既有二次授权实现，不宣称已完成端到端迁移。

