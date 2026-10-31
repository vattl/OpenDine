# Implementation Design — WI-006

## Root Fix / Owner

以 `IMemberRechargeService` 作为充值汇总口径唯一 owner；当班和日结只消费统一汇总，不把充值伪装成订单或支付台账。

## Why this location

充值与点餐订单刻意解耦，写入伪订单/伪支付台账会破坏既有架构。充值事实表已经具备本金、赠送、状态、门店和支付时间，适合直接聚合。

## End-to-End Change

### Backend

- 增加成功充值汇总值对象/Map：笔数、本金分、赠送分、入账合计分。
- 后台充值若存在当前操作员活动班次，写入 `operator_id`、`drawer_session_id`。
- 当前班次与关闭班次按显式 `drawer_session_id` 聚合；日结按 shop + success + `[window_start, window_end)` 聚合。

### Frontend

本仓库不改前端；新增字段可选消费，旧客户端忽略即可。

### UI / Interaction

无交互变化，不触发 UI Design Track。

### Data / Persistence

- `t_member_recharge` 新增可空 `operator_id`、`drawer_session_id` 及索引。
- `t_daily_close_snapshot` 新增 `cutoff_recharge_id`、`member_recharge_gift_fen`、`member_recharge_count`；沿用 `member_recharge_fen` 表示本金。
- 迁移仅 additive；旧记录/旧快照以空归属或零值兼容。

### Interfaces / Contracts

- 当班 current/report/handover：新增 `member_recharge_summary`。
- 日结 preview/snapshot/z-report/z-reports：新增充值汇总与 `total_collections_fen`。
- `watermarks` 新增 `member_recharge_id`。

### Jobs / Events / Integrations

微信支付回调行为不变；成功后已有 `status=success/pay_time` 即可被日结聚合。

## Preserve / Compatibility

- `total_amount` / `net_sales_fen` / `order_count` 不含充值。
- 新 `total_collections_fen = net_sales_fen + member_recharge_principal_fen`。
- `credited_total_fen = principal_fen + gift_fen` 仅表示会员余额入账，不表示现金收款。

## API Consumer Migration / Handoff

增量兼容。文档中明确前端展示口径；无需同步阻断旧消费者。

## Failure / Boundary Behavior

- 无门店、非 success、`pay_time` 为空、窗口边界外：不计入。
- 左闭右开窗口，截止点充值进入下一窗口。
- 无活动员工班次的后台充值和所有无归属旧记录：只进日结，不进个人班次。
- 预检后充值最大 ID 变化：`WATERMARK_CHANGED`。

## Runtime / Performance / Reliability

以复合索引覆盖日结查询，以 `drawer_session_id/status` 索引覆盖班次查询；金额用 `BigDecimal` 转分并 `HALF_UP`，避免浮点误差。

## Security / Permissions

沿用现有门店作用域与端点权限；不接受客户端传入 operator/drawer 归属。

## UI Design Track

N/A。

## Vertical Slice Plan

1. RED：汇总与归属测试；GREEN：迁移、实体、统一汇总与后台写入。
2. RED：当班 current/closed report 测试；GREEN：响应增量。
3. RED：日结 preview/snapshot/watermark/Z 测试；GREEN：完整关账链路。
4. 同步文档、运行定向测试、全量测试/打包、审查与验收。

## Verification Strategy

- Mockito 单测验证查询边界与输出金额。
- 日结服务测试验证快照、Z 报表、水位变化。
- 数据库迁移静态测试验证列和索引。
- OpenAPI YAML 解析/项目既有测试。
- 强制 Maven 完整打包。

## Rollback / Recovery

代码和响应字段可回退；数据库新增列保留不影响旧代码。快照一旦生成不回写或删除。
