# Acceptance Report — WI-074

Decision: ACCEPTED

## 1. 验收结论
- **状态**: ACCEPTED
- **决议**: 收银端与顾客端电子发票模块已按照 WI-073 审计结论完成全面修复。P0 安全鉴权（Token 校验、防遍历、防空白初始化）、P0 敏感隐私脱敏（日志脱敏、H5 掩码渲染）、P1 状态机约束（未支付订单拦截、累计开票金额校验）、顾客端 H5 合规整改（消除虚假宣传、防抖控制、安全协议过滤）以及微信 JSAPI 下单通道 `support_fapiao: true` 配置均已落实。所有 29 项单元与集成测试通过，三项 UI 验收子 Gate 全部通过，OpenAPI 文档与 API.md 同步完成，可执行 JAR 构建成功。

## 2. 验收清单核对 (Acceptance Criteria)

| 准则项 | 状态 | 验证说明 |
|---|---|---|
| AC-01: Token 强校验与防遍历，禁止匿名自动创建记录 | PASS | `PublicInvoiceController` 强制要求 `token` 参数；`OrderInvoiceServiceImpl` 校验 `token_hash` 与时效；查无记录返回 404，移除自动创建代码 |
| AC-02: 敏感数据（税号、手机、邮箱）脱敏打印与掩码显示 | PASS | `maskTaxNo`, `maskPhone`, `maskEmail` 实施掩码脱敏；日志中无明文 PII；H5 页面回显掩码数据 |
| AC-03: 顾客端 H5 界面合规整改与防抖控制 | PASS | 标题文案更正为“老肥家餐饮 · 电子发票服务”；增加隐私横幅；按钮增加防抖锁定；下载链接校验协议白名单 |
| AC-04: 状态机流转与可开票金额防超额校验 | PASS | 仅允许已支付订单申请发票；累计有效发票金额不得超出实付扣除退款后的净额；禁止未提交抬头直接开票 |
| AC-05: 微信 JSAPI 下单通道 `support_fapiao: true` | PASS | `WechatJsapiChannel.createPrepay` 中注入 `support_fapiao: true`，单测断言通过 |
| AC-06: Flyway V050 脚本、API 文档同步与 Maven 打包 | PASS | `V050__invoice_token_auth_and_audit.sql` 创建；`docs/openapi.yaml` 与 `docs/API.md` 同步；Maven 打包生成 `target/diancan-0.0.1-SNAPSHOT.jar` |
