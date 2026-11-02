# WORK ITEM — WI-073

## Request

使用微信支付开发技能，审计收银端电子发票模块是否具备完整功能并能在普通微信支付商户场景正常使用。

## Type

MAINTENANCE

## State

AUDIT_PENDING

## Requirement Contract

### Goal

基于微信支付官方文档和仓库证据，对普通商户收银端开票全链路进行只读审计，识别阻断正常使用的缺口，并给出可执行整改范围。

### Current behavior

仓库已存在发票二维码、公开抬头采集、后台状态查询及人工登记开票结果等代码，但尚未证明其符合普通商户权限边界，也未证明真实开票、回调、退款和冲红闭环可用。

### Target behavior

形成逐项 PASS / ISSUE / UNVERIFIED / N/A 的审计结论，覆盖普通商户能力边界、支付入口、抬头采集、开具交付、状态机、退款冲红、鉴权隐私、门店隔离、幂等及测试证据；不在本 Work Item 修改业务代码或调用真实微信接口。

### Must preserve

- 不调用真实微信支付或真实开票接口。
- 不改动生产业务代码、接口契约或数据库结构。
- 不泄露商户密钥、证书、用户抬头、税号、手机号或邮箱。
- 审计结论必须绑定到官方文档及仓库文件行号。

### Acceptance criteria

- [x] 明确普通商户 `support_fapiao` 能力与服务商电子发票 API 的适用边界。
- [x] 覆盖支付下单、抬头采集、开具交付、状态回调、退款冲红、权限隐私、门店隔离及测试证据。
- [x] 每项结论分类为 PASS、ISSUE、UNVERIFIED 或 N/A，并提供文件行号或官方文档证据。
- [x] 形成明确的上线判定和按优先级排序的整改建议。
- [x] 审计过程不修改生产代码且不发起真实微信支付/开票请求。

### Open product questions

- 商户最终选择“微信支付普通商户支付后开票入口 + 自建/第三方税控平台”，还是由已授权服务商承接完整微信电子发票能力。
- 是否授权运行现有的本地 JUnit/Mockito 定向测试；未授权前测试结果保持 UNVERIFIED。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 同步并检索微信支付官方知识库，确认产品边界。
- [x] T02 审计支付下单与微信发票 API 调用。
- [x] T03 审计公开抬头采集、状态机、数据与安全。
- [x] T04 审计退款、冲红、测试和上线证据。
- [x] T05 输出审计报告并完成独立复核。

## Verification Evidence

见 `INVOICE_AUDIT_REPORT.md`、`SECURITY_AUDIT.md`、`TEST_REPORT.md` 与 `COMPLETION_EVIDENCE.md`。

## Review

PASS（审计交付）；产品判定 BLOCKED。

## Acceptance Decision

ACCEPTED

## Consumer Handoffs

NONE（本 Work Item 不修改接口）。

## Integration / Release

INTEGRATED / NOT_RELEASED

## Related IDs

Workstream: WECHATPAY-INVOICE-AUDIT

UI: NONE

Capability: CASHIER-INVOICE

Commits: PENDING

## Business Invariants

- 只有已支付且具备可开票余额的订单可以开票。
- 同一订单累计有效开票金额不得超过扣除成功退款后的可开票金额。
- 发票“成功”必须来自真实税控/开票平台结果或受控人工凭证，不得仅凭客户端输入伪造。
- 公开开票链接必须具备不可猜测、可过期、强绑定的授权凭证，且不得跨订单、跨门店访问或修改。
- 微信服务商电子发票 API 不得使用普通商户身份冒充调用。
- 已开票后的退款必须触发冲红或明确的人工异常流程，状态可追溯。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-073/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-073/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 0

## Implementation Ready

- Status: YES
- Blockers: none for read-only audit; production remediation remains out of scope.

## Completion Level

ACCEPTED
