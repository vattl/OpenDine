# Security Audit — WI-023

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Threat Model

- 金额篡改：挂账金额仅由服务端订单净应付计算，客户端无金额字段。
- 跨门店访问：订单、应收单与流水查询均带 merchant/shop 条件；客户对账单也限定当前门店流水。
- 跨店共享账户滥用：`MERCHANT` 账户的创建和生命周期管理额外要求 `receivable:merchant_manage` 或超级管理员；门店店长只能管理 `SHOP` 账户。
- 越权财务操作：查看、账户管理、挂账、回款、坏账/撤销拆分权限；控制器在接口映射之外执行动作级二次校验。
- 重放和并发：商户级 requestId 唯一约束、活动应收唯一键、订单/账户/应收行锁；获得订单锁后再次读取幂等结果。
- 虚假收款：挂账订单支付分项归零并跳过 PaymentLedger；坏账和撤销只追加应收流水，均不计实际收款。
- 退款混淆：挂账订单被现有支付退款接口明确拒绝，不会误调微信或余额退款。
- 敏感信息：新增代码、迁移、文档未包含密钥、令牌或证书内容。

## Residual Risk

生产部署仍需先备份并执行 V025，在真实 MySQL 上完成迁移演练；外部 UI 未在本仓库，需按 handoff 实现并做端到端验收。
