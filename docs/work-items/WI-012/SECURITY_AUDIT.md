# Security Audit — WI-012

Security Decision: APPROVED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Secret Scan: PASS
Dependency Scan: NOT_APPLICABLE
SAST: NOT_APPLICABLE

## Threat Model

- Asset: 桌台待结账金额及订单财务一致性。
- Trust boundary: 已鉴权的桌台状态查询读取当前门店订单与明细。
- Tampering risk: 历史/重复套餐明细不得重新定义订单应付金额。
- Information disclosure / privilege risk: 本次未改变鉴权、门店隔离、查询范围或返回敏感字段。

## Findings

- 金额改为复用全项目统一的 `OrderNetRevenue.netRevenueYuan`，避免桌台路径产生第二套财务公式。
- 未增加输入、SQL、外部调用、依赖或写操作；GET 接口仍无金额回写副作用。
- 变更差异高风险凭据模式扫描无命中。
