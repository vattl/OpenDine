# WORK ITEM — WI-006

## Request

收银系统目前还没有把会员充值纳入当班、日结流程。

## Type

CHANGE / STANDARD / BACKEND / DATA / API

## State

ACCEPTED

## Requirement Contract

### Goal

把成功的会员充值纳入门店当班报告与日结关账，且明确区分实际收取的充值本金和非现金赠送额。

### Current behavior

- 充值仅写入 `t_member_recharge`，不写点餐订单与支付台账。
- 当班统计和交班报告只读取 `t_payment_ledger` / `t_payment`，遗漏会员充值。
- 日结快照预留 `member_recharge_fen`，但关账时固定写 `0`；预检、X/Z 报表和水位校验均未纳入充值。

### Target behavior

- 后台人工充值在有活动员工班次时记录操作员与钱箱会话归属；无活动班次仍可充值并进入日结，但不伪造当班归属。
- 当前班次和已交班报告返回独立的会员充值汇总：成功笔数、本金、赠送、入账合计；原订单营业额字段语义保持不变。
- 日结预览、关账快照、X/Z 报表与历史列表纳入同一营业窗口、同一门店的成功充值。
- 日结水位增加充值流水水位，防止预检后新增充值却仍按旧预览关账。

### Must preserve

- 充值本金属于实际收款；赠送额只增加会员权益，不得计入营业实收或现金盘点。
- 订单销售额、净销售额、订单数的既有语义不变，充值以独立字段展示。
- 仅统计 `status=success`、`pay_time` 落在左闭右开窗口且 `shop_id` 精确匹配当前门店的流水。
- 历史未带班次归属的充值不得猜测归属；仍按门店营业日进入日结。
- 盲盘交班不得因充值字段泄露 `expected_cash` 或长短款。
- 已生成的日结快照保持不可变；新增字段对旧快照以零值兼容。

### Acceptance criteria

- [x] 后台人工充值在存在当前操作员活动班次时写入 `operator_id` 与 `drawer_session_id`。
- [x] `GET /cashier/shift/current` 与已关闭班次报告提供会员充值汇总，且只纳入归属该班次的成功充值。
- [x] `GET /admin/daily/pre-check` 的 preview 提供充值本金、赠送、入账合计、笔数与总收款字段。
- [x] `POST /admin/daily/settle` 固化充值汇总与充值水位；预检后充值变化触发 `WATERMARK_CHANGED`。
- [x] X/Z 报表及 Z 报表历史列表返回快照一致的充值信息。
- [x] 纯赠送金额不增加营业实收或总收款；本金增加总收款但不增加订单销售额。
- [x] 相关数据库迁移、OpenAPI、API 文档和自动化测试同步完成。
- [x] 完整执行 `mvn clean package -DskipTests` 并生成可运行 JAR。

### Open product questions

无阻断问题。按现有 `member_recharge_fen` 字段注释与财务语义，将“纳入收款”解释为本金；赠送额单独披露，不计收入。C 端微信充值无员工班次归属，进入门店日结但不进入个人钱箱班次。

## Impact Summary

Link: `impact-map.md`

## Design Summary

Link: `implementation-design.md`

## Tasks / Vertical Slices

- [x] T01 充值归属字段、迁移与写入测试
- [x] T02 当班实时/交班报告充值汇总及测试
- [x] T03 日结预览、快照、水位、X/Z 报表及测试
- [x] T04 OpenAPI/API 文档同步、定向测试、完整打包与审查

## Verification Evidence

- 相关测试 50 用例全绿：`AdminMemberRechargeShiftAttributionTest`(1)、`MemberRechargeServiceTest`(2)、`DailyCloseServiceTest`(14)、`DrawerSessionServiceTest`(12)、`CashierShiftControllerTest`(5) 及 WI-005 相关 12 例。
- 修复测试缺陷一处：`DrawerSessionServiceTest.getWorkbench` 用例 mock `selectOne` 应为 `selectList`（MP 3.3.2 `getOne(wrapper,false)` 内部走 selectList）。
- 迁移 `V021__member_recharge_shift_and_daily_close.sql`（幂等 additive）+ `db_migration_member_recharge.sql` 同步。
- `docs/openapi.yaml` / `docs/API.md` 已同步充值汇总、水位与 Z 报表契约。
- 全量打包 `mvn clean package -DskipTests` BUILD SUCCESS。

## Review

- 设计复核：充值汇总口径唯一 owner 为 `IMemberRechargeService`；当班按显式 `drawer_session_id`、日结按门店左闭右开营业窗口聚合，符合 IMPACT_MAP/IMPLEMENTATION_DESIGN。
- 不变量：INV-RECHARGE-001/002、INV-SALES-001、INV-CLOSE-001、INV-SHIFT-001 均有对应测试覆盖（见 scenario-matrix S01-S08）。

## Acceptance Decision

ACCEPTED（2026-10-09）：验收标准 8/8 满足，S01-S08 全部 PASS。集成/发布按 Work Item 约定另行执行。

## Consumer Handoffs

响应新增字段为向后兼容增量；文档同步后由现有收银前端按需展示，不要求旧客户端立即升级。

## Integration / Release

当前工作树存在 WI-005 未提交变更；本 Work Item 不创建或切换分支，不提交用户既有修改。最终仅声明 ACCEPTED，集成/发布另行执行。

## Related IDs

Workstream: WI-006

## Business Invariants

- `INV-RECHARGE-001`：只有成功充值可进入当班/日结。
- `INV-RECHARGE-002`：充值本金是实际收款，赠送额不是营业实收。
- `INV-SALES-001`：会员充值不改变订单销售额、净销售额或订单数。
- `INV-CLOSE-001`：日结预检到关账之间任何财务源水位变化必须使预检凭据失效。
- `INV-SHIFT-001`：个人班次只接收有明确班次归属的充值，不猜测历史归属。

## Impact Map Authority

- Impact map path: `tasks/active/WI-006/impact-map.md`
- Material UNKNOWN count: 0

## Scenario Matrix

- Scenario matrix path: `tasks/active/WI-006/scenario-matrix.md`
- Material NOT_VERIFIED count: 0（S01-S08 全部 PASS）

## Implementation Ready

- Status: `YES`
- Blockers: NONE

## Completion Level

`ACCEPTED`（集成/发布另行执行）
