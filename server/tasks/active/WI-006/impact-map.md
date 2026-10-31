# Impact Map — WI-006

## Authoritative Owner

- 充值事实：`t_member_recharge` / `IMemberRechargeService`
- 员工班次事实：`t_shift.drawer_session_id` / `t_drawer_session`
- 日结事实：`DailyCloseServiceImpl` / `t_daily_close_snapshot`

## Change Propagation Path

```text
后台人工充值 / 微信充值成功
→ t_member_recharge（门店、状态、支付时间、可选班次归属）
→ 当班窗口或营业日窗口聚合
→ current / shift report / daily preview
→ 日结充值水位校验
→ 不可变 daily close snapshot
→ X/Z report 与历史列表
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 收银端当前班次 | 读取 `/cashier/shift/current` | AFFECTED | 可选展示新增汇总 | 现接口只返回订单金额 |
| 收银端交班报告 | 读取 handover/report/reports | AFFECTED | 可选展示新增汇总 | 报告只聚合支付台账 |
| 日结预检页 | 读取 `/admin/daily/pre-check` | AFFECTED | 可选展示新增汇总 | preview 当前无充值 |
| 日结执行页 | 读取 `/admin/daily/settle` | AFFECTED | 可选展示快照字段 | snapshot 当前充值为 0 |
| Z 报表/历史 | 读取 z-report/z-reports | AFFECTED | 可选展示新增汇总 | 当前无充值输出 |
| 旧客户端 | 忽略未知 JSON 字段 | VERIFIED_UNAFFECTED | 否 | 所有变更均为响应增量 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 当前仓库为服务端；无生产 UI 修改 |
| Interaction | VERIFIED_UNAFFECTED | 请求参数及操作流程不变 |
| Frontend State | NOT_APPLICABLE | 前端仓库不在当前工作区 |
| API Client | AFFECTED | 可消费新增字段，旧客户端兼容 |
| Request Contract | VERIFIED_UNAFFECTED | 不新增必填请求字段 |
| Backend/Domain | AFFECTED | 充值归属、汇总、日结水位与快照 |
| Persistence | AFFECTED | 充值归属列、日结快照汇总/水位列 |
| Response Contract | AFFECTED | 当班、日结、Z 报表新增字段 |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | 微信回调仍只更新成功状态；汇总读取事实表 |
| Config/Security | VERIFIED_UNAFFECTED | 路由权限与门店作用域不变 |
| Runtime/NFR | AFFECTED | 新增按 shop/status/time 或 drawer session 查询；补索引 |
| Tests | AFFECTED | service/controller/migration contract tests |

## Duplicate Logic / Patch Smells

当班与日结不得各自手写金额口径；由 `IMemberRechargeService` 提供统一成功充值汇总。日结不可只改显示层，必须同时纳入水位和快照。

## Contract Delta Summary

向后兼容新增：`member_recharge_summary`、`total_collections_fen`，快照新增充值赠送/笔数/截止水位字段；既有销售字段保持不变。

## UI Semantic Impact

NONE（服务端契约增量，无结构 UI 生产修改，UI Design Track 不适用）。

## Risks

- 重复计算赠送额为收入：用独立字段和测试锁定。
- 并发充值穿透预检：新增充值水位。
- 多钱箱重复归属：仅按显式 `drawer_session_id` 纳入个人班次。
- 旧数据无归属：不回填猜测，日结按门店时间窗仍可汇总。
- WI-005 文档/报表文件重叠：仅追加本 Work Item 内容，保留现有改动。
