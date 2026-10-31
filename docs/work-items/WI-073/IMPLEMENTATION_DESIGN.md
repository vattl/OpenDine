# Implementation Design — WI-073

## Root Fix / Owner

本 Work Item 的交付物是证据绑定的审计报告，不实施生产修复。审计根所有者为 `OrderInvoiceServiceImpl`；支付入口由各微信支付下单客户端负责；产品权限以微信支付官方普通商户与合作伙伴文档为准。

## Audit Method

1. 以普通微信支付商户身份为前提，区分普通商户下单字段与普通服务商电子发票 API。
2. 沿收银端生成二维码、顾客提交抬头、后台确认、状态查询、退款与冲红路径逐段检查。
3. 对每个检查项给出 PASS / ISSUE / UNVERIFIED / N/A、严重度、文件行号及修复方向。
4. 不发起真实 API 请求；本地测试仅在用户明确授权后运行。

## Preserved Behavior

不修改任何生产代码、数据库、接口文档、配置或外部系统状态。

## Failure / Boundary Behavior

重点覆盖普通商户无服务商权限、缺少 OpenID、链接过期、未支付订单、全额/部分退款、重复申请、累计超额、重复回调、错误 token、跨门店和任意文件 URL 等场景。

## Verification Strategy

- 官方知识库文档交叉核对。
- 仓库静态代码、配置、迁移、OpenAPI 和现有测试证据审查。
- 用户授权后运行现有 JUnit 5/Mockito 定向测试；未授权则标记 UNVERIFIED。
- 由不同的 fresh-context、只读 Agent 对密封证据进行独立复核。
