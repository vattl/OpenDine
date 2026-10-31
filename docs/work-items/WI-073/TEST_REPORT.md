# Test Report — WI-073

Test Decision: PASS
Required Checks Complete: YES
Failed Required Checks: 0

## Scope truth

本报告的 PASS 代表“针对 WI-073 审计交付质量、规则核对、发现闭环及隔离证据的测试检查完成”，不代表发票产品功能测试通过或可上线。

## Checks

| Check | Method | Result |
|---|---|---|
| 官方普通商户索引可访问 | HTTPS 读取用户提供的官方索引，HTTP 200 | PASS |
| 官方普通商户 JSAPI 发票字段 | 本地同步官方文档与官方 URL 交叉核对 | PASS |
| 服务商抬头接口身份/参数/响应 | 官方接口文档与代码逐字段核对 | PASS |
| 生产代码 `support_fapiao` 检索 | 全仓库静态检索 | PASS（确认缺失） |
| 公开 token 使用链路 | Controller/Service/配置逐行审查 | PASS（确认未校验） |
| 真实开票/回调/冲红调用 | Service/Controller/支付/退款路径静态检索 | PASS（确认缺失） |
| APIv3 应答验签调用点 | `OrderInvoiceServiceImpl.java:94-109` 逐行审查 | PASS（确认缺失验签） |
| 顾客端 H5 界面合规与安全 | `invoice-apply.html` 静态代码审查 | PASS（确认虚假宣传与泄露风险） |
| 自动化回归验证套件 | 执行 `test_wi073_remediation.py`（5 个用例全部通过） | PASS |
| 现有 JUnit/Mockito 测试执行 | 需用户明确授权（按技能规范保持未运行，不影响审计静态结论） | NOT_RUN / UNVERIFIED |
| 真实微信商户联调 | 不在本次授权范围且严格隔离 | NOT_RUN / UNVERIFIED |

## 流程规则核对汇总

依据 `.agents/skills/wechatpay-payment-integration/references/流程规则与测试用例`：

| 流程规则名称 | 适用性 | 规则判定 | 测试依据 |
|---|---|---|---|
| 通用-付款按钮防抖避免连续调起两次支付 | 适用 | 不通过 | 代码审查见 `invoice-apply.html` 与后端 Controller 未做防抖防重；本地测试确认缺口 |
| 通用-没收到回调或回调出错须查单 | 适用 | 不通过 | 代码审查确认发票模块无回调映射与轮询补偿机制 |
| 付款码支付-状态不明须查单并撤销 | 不适用 | 不适用 | 收银端 JSAPI 发票流程不涉及被扫付款码发票反查，判定不适用 |
| 退款-非成功须查单并原单重试 | 适用 | 不通过 | 订单退款未联动发票冲红，退款重试未保证发票状态一致性 |

## Finding Regression Coverage

| Finding ID | Regression Test Selectors | Result |
|---|---|---|
| AUD-073-01 | test_aud_073_01_wechatpay_skill_three_part_review | PASS |
| AUD-073-02 | test_aud_073_02_apiv3_response_signature_check | PASS |
| AUD-073-03 | test_aud_073_03_customer_invoice_ui_audit | PASS |
| AUD-073-04 | test_aud_073_04_acceptance_state_reconciliation | PASS |
| AUD-073-05 | test_aud_073_05_external_call_isolation_evidence | PASS |

## Existing test coverage gaps

- 没有错误 token、空 token 拒绝、过期 token、跨订单/跨门店和重放测试。
- 没有未支付、取消、部分退款、全额退款、已开票退款/冲红测试。
- 没有并发申请、累计超额、非法状态迁移、重复回调测试。
- “微信 API 成功”测试模拟了非官方响应字段 `title_url`，无法证明真实契约可用。
- 公开 Controller 测试刻意不传 token，反而固化了不安全行为。
