# WORK ITEM — WI-023

## Request

依据现有挂账审计，完成可商业化使用的挂账/应收账款系统，并与收银、订单、门店权限、日结和报表保持一致。

## Type

FEATURE

## State

ACCEPTED

## Requirement Contract

### Goal

建立真实的应收账款闭环，使合法授信客户可以将订单转为应收、跨营业日结转，并在后续进行部分或全部回款、核销、冲销和坏账处理。

### Current behavior

- `/cashier/order/hang` 仅回传订单号，不写入业务状态。
- `unsettled` 订单会阻断日结，不能作为正式应收跨日结转。
- 未注册“挂账”支付渠道，也没有客户授信、应收台账、回款或账龄模型。
- API 文档提到“挂账渠道”，但实现不存在。

### Target behavior

- 建立门店/商户隔离的应收客户账户，支持额度、账期、启停和软关闭。
- 收银员仅能把同店未结订单按服务端金额挂到账户；并发、重复请求不得重复占用额度。
- 挂账订单正常完成业务结账和履约，但不得伪造支付台账或计入当日实收。
- 支持部分/全部回款、回款渠道、幂等核销、无回款挂账撤销、剩余欠款坏账核销。
- 支持账户余额、应收单、不可变流水、账龄和逾期查询。
- 日结继续统计挂账销售额，但 `total_collections_fen` 仅统计真实支付、应收回款和充值本金。

### Must preserve

- 微信/支付宝/余额/现金等现有支付链路及支付权威不变量不变。
- 订单金额只能由服务端计算，客户端不能指定挂账金额。
- 所有应收读写严格绑定认证后的门店和商户范围。
- 已发生回款的应收单不得直接撤销；坏账不得伪装成收款。
- `/cashier/order/hang` 继续保持原“挂单”兼容语义，不改造成赊账接口。

### Acceptance criteria

- [x] 应收账户支持创建、修改、暂停、恢复、关闭以及额度/账期校验。
- [x] 同店订单可幂等挂账，超额度、跨店、非活动账户、非未结订单均被拒绝。
- [x] 挂账后订单可完成履约且不生成成功支付流水；日结不再被该订单阻断。
- [x] 支持部分/全部回款，账户余额和应收单余额原子更新且不可超收。
- [x] 支持零回款应收撤销和剩余欠款坏账核销，并保留不可变审计流水。
- [x] 支持分页列表、账户对账单、账龄汇总和逾期状态。
- [x] 日结/X-Z 报表区分销售、挂账新增、应收回款、坏账和实际收款。
- [x] API 文档、权限映射、数据库迁移、专项测试、全量测试和 JAR 打包完成。

### Open product questions

NONE。采用安全默认：账户默认门店级；只有显式 `MERCHANT` 范围账户才允许同商户跨门店使用。

## Impact Summary

Link: `IMPACT_MAP.md`

## Design Summary

Link: `IMPLEMENTATION_DESIGN.md`

## Tasks / Vertical Slices

- [x] T01 数据模型、权限、账户生命周期和查询。
- [x] T02 收银挂账、订单结账副作用与支付台账隔离。
- [x] T03 回款、撤销、坏账与不可变应收流水。
- [x] T04 账龄/对账单及日结实收口径。
- [x] T05 OpenAPI、消费者交接、全量验证和验收证据。

## Verification Evidence

`TEST_REPORT.md`, `SECURITY_AUDIT.md`, `SCENARIO_MATRIX.md`, `COMPLETION_EVIDENCE.md`。

## Review

PASS — `REVIEW_REPORT.md`。

## Acceptance Decision

ACCEPTED — 服务端范围；外部消费者仍为 PENDING。

## Consumer Handoffs

`API_CONSUMER_HANDOFF.md` — 收银和管理端需要新增应收账户、挂账、回款与账龄界面；本仓库只拥有服务端。

## Integration / Release

Backend implementation branch only；未部署、不代表 RELEASED。

## Related IDs

Workstream: receivables-system
UI: external consumers
Capability: accounts-receivable
Commits:

## Business Invariants

- INV-AR-001：应收增加、订单结账状态、账户占用余额和不可变流水必须在同一事务内原子提交。
- INV-AR-002：挂账金额只能来自服务端订单净应付，客户端不能覆盖。
- INV-AR-003：挂账不是收款，不得生成成功支付流水或计入当日实收。
- INV-AR-004：账户、应收单和流水必须按商户及门店范围隔离。
- INV-AR-005：任一时刻账户未清余额不得超过授信额度；回款不得超过应收未清余额。
- INV-AR-006：应收流水不可修改；更正只能追加撤销、回款或坏账流水。
- INV-AR-007：有回款的应收单不得撤销挂账；坏账只能核销剩余未清金额且必须记录原因和操作人。
- INV-AR-008：销售额、实际收款、应收新增和应收余额是不同财务口径，报表不得混用。

## Impact Map Authority

- Impact map path: `docs/work-items/WI-023/IMPACT_MAP.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `docs/work-items/WI-023/SCENARIO_MATRIX.md`
- Material NOT_VERIFIED count: 15

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

BACKEND_ACCEPTED
