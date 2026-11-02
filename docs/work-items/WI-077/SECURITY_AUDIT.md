# Security Audit — WI-077

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

- **T1: 外部 URL 注入与钓鱼链接风险**
  - **防护设计**：所有税局 URL 均严格由后端权威映射表 `TaxBureauResolver` 与前端静态规则表匹配生成，全部绑定在国家税务总局官方唯一官方主域 `chinatax.gov.cn`（如 `etax.shenzhen.chinatax.gov.cn`、`etax.guangdong.chinatax.gov.cn`、`etax.beijing.chinatax.gov.cn` 等）之下。绝不接受任意用户输入或不可信第三方链接，彻底杜绝钓鱼重定向与恶意 URL 伪造。
- **T2: 跨门店纳税主体篡改与越权开票**
  - **防护设计**：开票订单所属门店 `shop_id` 由订单系统强校验，发票分页查询与确认开票严格由服务端对齐，各门店纳税主体信息（名称、编码、地址、税局）仅在服务端查询并填充。即便工作人员在前端修改界面，服务端仍然只根据订单在数据库中真实的 `shop_id` 与对应微信商户凭据进行开票和卡包交付。
- **T3: XSS 跨站脚本与剪贴板污染**
  - **防护设计**：前端工作台 `admin.html` 中所有从订单对象提取并拼装到 HTML 属性（如 `title`、`onclick`）的地址与抬头文本，均经过严密的 `escapeAttr()` 转义处理；开票资料复制功能使用 `navigator.clipboard.writeText` 写入纯文本内容，不引入任何 HTML 或富文本解析漏洞。

## 2. Invariant & Security Decision

所有安全边界与业务不变量均已通过自动化规则与单元测试检验。
Security Decision: APPROVED
