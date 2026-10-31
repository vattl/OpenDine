# Security Audit — WI-026

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Threat model

- Asset: 门店订单及资金流水诊断数据。
- Trust boundary: 已有 `daily:settle` 管理端接口。
- Spoofing/elevation: 未修改认证授权；继续使用原接口权限。
- Information disclosure: 新增字段仅含当前门店订单标识、支付方式、渠道及分金额；不包含密钥、证书、openid、第三方交易号或完整第三方报文。
- Tampering/repudiation: 预检保持只读，未引入资金写入或状态修改。
- Denial of service: 复用批量查询，异常详情继续限制 50 笔，未新增 N+1 查询。

## Checks

- 门店范围来自已解析门店并用于订单、流水查询，未接受客户端注入的跨门店标识。
- 原因文本由服务端固定枚举和内部渠道值生成，不执行动态 SQL/脚本。
- 变更差异中未发现私钥头、API key 或硬编码 secret 模式。
- 未增加或升级依赖，因此依赖扫描不适用。
