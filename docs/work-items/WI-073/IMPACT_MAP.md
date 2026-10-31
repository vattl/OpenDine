# Impact Map — WI-073

## Audit Routing Inputs

Risk Level: HIGH
UI Impact: NONE
Contract Impact: NONE
Security Impact: YES
Data / Migration Impact: NO
Reliability / Performance Impact: YES

## Authoritative Owner

`OrderInvoiceServiceImpl` owns the current invoice lifecycle. `WechatJsapiChannel` and other WeChat order clients own payment-order request construction. WeChat Pay official documentation is authoritative for product and API eligibility.

## Change Propagation Path

```text
Cashier / customer request
→ admin or public invoice controller
→ OrderInvoiceServiceImpl
→ t_order_invoice / WeChat Pay APIv3
→ status query or invoice delivery (invoice-apply.html)
→ refund / red-flush handling
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 收银端 | 发起二维码、查询状态、人工登记 | AFFECTED | Audit only | `AdminOrderController` |
| 顾客 H5 页面 (`invoice-apply.html`) | 顾客发票抬头录入、状态回显与凭证下载 | AFFECTED | Audit only (受检消费表面) | `src/main/resources/static/invoice-apply.html`（及 `target/classes/static/invoice-apply.html`） |
| 顾客 H5 API | 查询订单、提交抬头 | AFFECTED | Audit only | `PublicInvoiceController` |
| 微信支付下单 | 决定支付详情页开票入口 | AFFECTED | Audit only | `WechatJsapiChannel`、`WechatNativeApiClient` |
| 微信电子发票服务 | 抬头、开具、插卡、回调 | AFFECTED | Audit only | 官方 partner 文档 |
| 退款链路 | 改变可开票金额、触发冲红 | AFFECTED | Audit only | `OrderNetRevenue` 及退款代码 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | AFFECTED | 本次为只读审计，不直接修改生产 UI 代码，但对仓库内顾客端 H5 界面（`src/main/resources/static/invoice-apply.html`）展开合规与隐私审计 |
| Interaction | AFFECTED | 扫码、提交、查询和人工登记链路 |
| Frontend State | AFFECTED | 顾客端 H5 页面状态切换逻辑 |
| API Client | AFFECTED | 微信支付及发票 APIv3 请求 |
| Request Contract | AFFECTED | 当前公开 token、金额、税率及开票输入 |
| Backend/Domain | AFFECTED | 发票状态机和业务不变量 |
| Persistence | AFFECTED | `t_order_invoice` 唯一性、状态和敏感数据 |
| Response Contract | AFFECTED | 开票状态、下载地址和公开信息 |
| Jobs/Events/Integrations | AFFECTED | 微信回调、退款、冲红与税控平台 |
| Config/Security | AFFECTED | 公开白名单、CORS、权限与密钥身份 |
| Runtime/NFR | AFFECTED | 外部 API 降级、幂等和可追溯性 |
| Tests | AFFECTED | 现有测试覆盖和运行证据 |

Classifications: AFFECTED / VERIFIED_UNAFFECTED / NOT_APPLICABLE / UNKNOWN.

## Duplicate Logic / Patch Smells

- 支付下单存在多个构造路径，必须分别确认 `support_fapiao`。
- 公开查询和提交均包含“查不到就自动初始化”逻辑，扩大未授权写入面。
- `error_msg` 同时承载访问 token 和错误信息，语义与保密边界混杂。
- 顾客端 `invoice-apply.html` 存在双副本（`src/` 与 `target/classes/`），包含虚假税务系统宣传与敏感信息直接渲染。

## Contract Delta Summary

本 Work Item 不改变契约；发现的契约缺口在审计报告中提出后续整改建议。

## UI Semantic Impact

NONE。本次不修改现有收银端或顾客端页面代码。

## Risks

- 普通商户误调用服务商专属 API，真实环境必然失败。
- 公开接口授权失效导致订单及发票个人信息泄露或被篡改。
- “抬头已收集/人工录入号码”被误标为“真实开票成功”。
- 退款后仍可重复或超额开票，已开票退款无冲红闭环。
- 顾客端 H5 页面虚假宣称税务总局对接与自动交付，引发客诉与监管合规风险。
