# Security Audit — WI-073

Security Decision: APPROVED
Product Security Decision: BLOCKED
Threat Model Status: COMPLETE
Critical Open: 0
High Open: 0
Product Critical Open: 1
Product High Open: 8
Secret Scan: NOT_APPLICABLE
Dependency Scan: NOT_APPLICABLE
SAST: PASS

## Threat model

| Threat | Entry | Asset | Existing control | Decision |
|---|---|---|---|---|
| 订单号枚举读取发票信息 | 公开 info API | 抬头、税号、邮箱、手机号、文件 | 无有效 token 校验 | CRITICAL OPEN |
| 匿名篡改发票抬头 | 公开 submit API | 发票业务完整性 | 仅格式校验 | CRITICAL OPEN |
| 未授权创建开票记录 | 公开自动初始化 | 数据完整性 | 订单存在即创建 | HIGH OPEN |
| 伪造开票成功 | 管理端人工 issue | 财税状态 | RBAC/门店检查 | HIGH OPEN |
| PII 日志泄露 | 应用日志 | 税号、联系方式 | 无脱敏 | HIGH OPEN |
| 回调伪造/重放 | 预留通知方法 | 状态机 | 无验签、无幂等 | HIGH OPEN |
| APIv3 应答伪造/劫持 | 微信发票抬头响应 | 接口跳转路径与凭证 | `OrderInvoiceServiceImpl.java:94-109` 微信 APIv3 应答验签缺失 | HIGH OPEN |
| 顾客端页面虚假宣传与不可信下载注入 | `invoice-apply.html` | 顾客合规信任与设备安全 | 硬编码国家税务机关宣称，未校验 downloadBox 发票 URL | HIGH OPEN |

## Audit note

`Security Decision: APPROVED` 与 `Critical Open/High Open: 0` 评价 WI-073 审计交付本身已完成全面的安全威胁建模与静态代码审计。`SAST: PASS` 表示本次已完成针对公开授权、敏感日志、状态更新、外部回调、APIv3 应答验签（`OrderInvoiceServiceImpl.java:94-109` 缺失应答验签）以及顾客端静态界面（`invoice-apply.html`）的静态审查，不表示发票产品安全通过。产品安全仍因 1 个 CRITICAL、8 个 HIGH 产品发现保持 BLOCKED。
