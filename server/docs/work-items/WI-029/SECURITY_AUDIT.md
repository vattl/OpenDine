# Security Audit — WI-029

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Threat model

- Asset: 门店营业日报、挂账应收变动与资金结算数据。
- Trust boundary: report:view 与 daily:settle 管理端接口。
- Spoofing/elevation: 未修改认证授权，沿用已有接口权限及门店数据权限隔离规则。
- Information disclosure: 挂账应收变动及实际收款合计仅包含当前门店聚合汇总指标与流水截止水位，不输出敏感客户信息、商户密钥或第三方报文。
- Tampering/repudiation: 已结日结快照保持不可变性，新增 receivable_reversed_fen 列并加入快照 SHA-256 校验和防篡改计算。
- Denial of service: 导出与统计复用既有批量 SQL 与营业窗口聚合，未引入 N+1 查询。

## Checks

- 门店隔离：所有挂账与应收数据均以 shopId 严格隔离，未授权越权访问直接拦截。
- 变更差异中无硬编码密钥、私钥、Token 或敏感密码模式。
- 未引入第三方外部新依赖，依赖扫描不适用。
