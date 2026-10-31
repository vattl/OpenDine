# Scenario Matrix — WI-006

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 当班人工充值 | 成功 admin 充值且有当前操作员活动班次 | 记录班次归属；current/交班报告显示本金、赠送、合计、笔数 | INV-RECHARGE-001/002, INV-SHIFT-001 | 单元测试 | PASS |
| S02 | 无活动班次人工充值 | 成功 admin 充值但无活动班次 | 充值成功并进入日结，不进入任何个人班次 | INV-SHIFT-001 | 单元测试 | PASS |
| S03 | 微信充值 | 门店成功微信充值，无员工班次归属 | 进入营业日日结，不进入个人班次 | INV-SHIFT-001 | 单元测试 | PASS |
| S04 | 本金与赠送 | 本金 10000 分、赠送 1000 分 | 总收款只增加 10000；会员入账合计 11000；销售额不变 | INV-RECHARGE-002, INV-SALES-001 | 日结服务测试 | PASS |
| S05 | 状态与空时间 | pending/cancelled 或 success 但 pay_time 为空 | 不计入任何汇总 | INV-RECHARGE-001 | 汇总服务测试 | PASS |
| S06 | 时间边界 | pay_time=start、pay_time=end | start 计入，end 不计入 | INV-RECHARGE-001 | 查询条件断言 | PASS |
| S07 | 预检并发充值 | 预检后同店新增充值流水 | settle 返回 409 WATERMARK_CHANGED | INV-CLOSE-001 | 日结服务测试 | PASS |
| S08 | 已关账历史 | 快照已固化后源充值表变化 | Z 报表仍读取快照充值值和截止水位 | INV-CLOSE-001 | 日结服务测试 | PASS |

## Acceptance rule

S01-S08 全部 PASS；任何 NOT_VERIFIED 阻断 ACCEPT。

## Verification Evidence

- `AdminMemberRechargeShiftAttributionTest`：1/1 通过（后台充值归属写入）。
- `MemberRechargeServiceTest`：2/2 通过（窗口/钱箱汇总口径）。
- `DailyCloseServiceTest`：14/14 通过（预览、快照、Z 报表、水位变化 S04/S05/S06/S07/S08）。
- `DrawerSessionServiceTest`：12/12 通过（current/交班报告充值汇总 S01/S02；其中 getWorkbench 用例修正 mock：getOne(wrapper,false) 在 MP 3.3.2 走 selectList 而非 selectOne）。
- `CashierShiftControllerTest`：5/5 通过。
- 全量打包 `mvn clean package -DskipTests` BUILD SUCCESS（2026-10-09）。
