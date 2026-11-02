# WORK ITEM — WI-074

## Request

基于 WI-073 审计结论，在普通商户模式下完成收银端与顾客端电子发票全链路的修复与优化工作（包含 P0 安全鉴权与隐私脱敏、P1 状态机与防超额退款约束、H5 页面合规修正，以及下单通道的 `support_fapiao` 可配置支持）。

## Type

REPAIR

## State

IN_PROGRESS

## Requirement Contract

### Goal

在普通微信支付商户架构下，全面修复电子发票模块的 P0 安全越权与信息泄露漏洞，健全状态机流转与订单累计可开票金额防超额约束，规范顾客端 H5 界面展示与防抖，并在微信支付 JSAPI 下单通道中可配置开启官方 `support_fapiao` 入口。

### Current behavior

- 公开开票查询与提交接口未对 `token` 进行强制校验，未授权用户可凭订单号遍历发票信息、匿名提交篡改抬头，甚至查不到时自动创建空白发票记录；
- 个人与企业敏感数据（抬头、税号、邮箱、手机号）在日志中明文打印，且在 H5 页面中未脱敏直接回显；
- 顾客端 H5 页面硬编码“国家税务总局全国统一规范电子发票开具服务”等虚假合规宣传，容易误导消费者；
- 金额校验与解析使用浮点数，且税率由客户端自由传入；
- 代码尝试调用微信普通服务商专属抬头 API，在普通商户模式下必然因权限不足报错；
- 未严格校验订单已支付状态，未对多次申请进行防重，未校验累计开票金额是否超过实付减去已退款金额；
- 微信支付下单通道未传递 `support_fapiao=true`。

### Target behavior

- 公开开票接口（查询与提交）强制要求高熵 `token`，并在后端使用 SHA-256 哈希比对 `token_hash`，绑定 `order_no + fapiao_apply_id + shop_id` 与有效截止时间 `token_expire_at`；未授权或查无记录直接拒绝，严禁匿名自动初始化；
- 彻底清理明文日志，对手机号、邮箱、纳税人识别号实施分类脱敏；
- 顾客端 H5 页面修正文案为“老肥家餐饮 · 发票抬头登记服务”，渲染回显时进行掩码脱敏，提交按钮增加防抖锁定，下载链接增加安全协议校验；
- 金额全程使用整数分/精确 `BigDecimal`，税率由服务端统一受控；
- 移除误导性的普通服务商专属抬头 API 调用，普通商户模式直接安全降级到本地受控登记二维码；
- 建立严格状态机与不变量检查：仅在订单支付成功（`transac_status == SUCCESS`）且实付扣除退款后仍有可开票余额时允许申请；累计有效发票金额不得超额；
- 微信 JSAPI 下单通道可配置开启 `support_fapiao: true`；
- 同步更新 OpenAPI 文档并生成可运行的生产 JAR 包。

### Must preserve

- 保持普通微信支付商户模式，不依赖未授权的微信服务商电子发票私有接口；
- 保持既有扫码开票二维码的 URL 格式与兼容性，确保收银端扫码流程顺畅；
- 遵循零信任与最小权限原则，不破坏任何已有的门店数据隔离边界；
- 保证退款与日结财务链路不受干扰，退款后可开票余额正确扣减。

### Acceptance criteria

- [x] AC-01: 公开开票查询与提交接口实现 Token 强校验与防遍历，无有效 Token 或查无申请时直接返回错误，禁止匿名自动创建记录。
- [x] AC-02: 敏感数据（税号、手机、邮箱）在日志中脱敏打印，在顾客端 H5 界面中掩码显示，修复公开泄露风险。
- [x] AC-03: 顾客端 H5 界面修正虚假税务总局宣称，明确标注门店登记属性，提交按钮实现防抖控制，下载链接具备安全校验。
- [x] AC-04: 服务端实现严格状态机与开票金额校验：未支付订单禁止开票，已开票金额 + 本次申请不得超过实付减去累计退款金额。
- [x] AC-05: 微信 JSAPI 下单通道增加可配置的 `support_fapiao: true` 参数传递支持。
- [x] AC-06: 数据库通过 Flyway V050 引入 Token 哈希与时效字段，API 变更同步至 `docs/openapi.yaml`，并通过 Maven 打包验证。

### Open product questions

NONE（已通过交互式决策与用户明确普通商户安全闭环方案与全量修复范围）。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 完成 H5 顾客端界面 HTML 原型设计、视觉截图、评审与设计门禁（UI Gate Plan）。
- [x] T02 编写 Flyway 数据库迁移脚本 `V050__invoice_token_auth_and_audit.sql` 并同步扩展实体 `OrderInvoice`。
- [x] T03 核心业务与安全重构：实现 Token 高熵生成与 SHA-256 校验、日志与前端脱敏、状态机流转控制与累计开票余额校验。
- [x] T04 控制器与接口加固：重构 `PublicInvoiceController` 与 `AdminOrderController`，拒绝未授权访问，同步 `docs/openapi.yaml`。
- [x] T05 微信 JSAPI 支付通道增强：在 `WechatJsapiChannel` 中增加 `support_fapiao` 可配置参数构造。
- [x] T06 生产 H5 界面更新：落地 `invoice-apply.html`（及镜像文件）文案修正、脱敏渲染与提交防抖。
- [x] T07 编写自动化集成测试套件验证修复效果，并执行 Maven 打包生成可运行 JAR。

## Verification Evidence

Link: `TEST_REPORT.md` / `SECURITY_AUDIT.md`

## Review

PASS

## Acceptance Decision

ACCEPTED

## Consumer Handoffs

NONE（前端 H5 页面在同 Work Item 中同步完成改造交付）。

## Integration / Release

INTEGRATED / NOT_RELEASED

## Related IDs

Workstream: WECHATPAY-INVOICE-REPAIR

UI: UI-INVOICE-APPLY-001

Capability: CASHIER-INVOICE

Commits: PENDING

## Business Invariants

- 只有已支付且具备可开票余额的订单可以申请发票。
- 订单累计有效开票金额（排除已作废/冲红发票）不得超过实际支付金额扣除累计退款金额。
- 公开开票链接必须携带与订单、申请单号和门店绑定的高熵 Token，并在服务端通过常数时间哈希比对防篡改与防遍历。
- 查无开票申请记录时，公开查询与提交接口必须返回 404/403，绝对禁止自动初始化生成数据库持久记录。
- 敏感隐私数据（税号、联系方式）必须实行服务端日志脱敏与客户端展示掩码。
- 普通商户不得直接调用普通服务商专属微信接口。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-074/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-074/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: none

## Completion Level

ACCEPTED
