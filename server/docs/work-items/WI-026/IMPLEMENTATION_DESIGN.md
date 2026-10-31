# Implementation Design — WI-026

## Root Fix / Owner

由 `OrderLedgerConsistencyService.Issue` 基于同一份订单投影和流水净额生成结构化异常解释；`DailyCloseServiceImpl` 只负责把所有 Issue 的原因码聚合为日结阻断摘要。

## Why this location

一致性服务已经是订单/流水比对的唯一所有者。将原因分类放在这里能保证测试、日结及未来其他消费者使用完全相同的口径。

## End-to-End Change

### Backend

- Issue 保存订单标识、支付方式、渠道投影与渠道流水净额。
- 自动计算总额、总差额、原因码/中文原因和不一致渠道明细。
- 日结 blocker 汇总所有异常的原因码计数。

### Frontend

不在本仓库实施；新字段为兼容增加。

### UI / Interaction

N/A。

### Data / Persistence

无写入和迁移，沿用一次批量流水查询。

### Interfaces / Contracts

保留现有字段，新增 `order_id`、`shop_id`、`payment_method`、`reason_codes`、`reason`、`expected_total_fen`、`ledger_total_fen`、`difference_fen`、`channel_differences`，blocker 新增 `reason_summary`。

### Jobs / Events / Integrations

N/A。

## Preserve / Compatibility

旧客户端仍可读取原有渠道金额映射。原因码和差额字段只做增加，不改变 HTTP 状态、阻断码及预检令牌规则。

## API Consumer Migration / Handoff

消费端优先展示 `reason`；需要详细诊断时展开 `channel_differences`；`difference_fen < 0` 为流水不足，`> 0` 为流水超额。

## Failure / Boundary Behavior

- 完全缺少流水：`LEDGER_MISSING`。
- 流水存在订单未记录渠道：`UNEXPECTED_LEDGER_CHANNEL`。
- 渠道流水少/多：`CHANNEL_AMOUNT_SHORT` / `CHANNEL_AMOUNT_EXCESS`。
- 总流水少/多：`TOTAL_AMOUNT_SHORT` / `TOTAL_AMOUNT_EXCESS`。
- 一个订单可同时返回多个原因码；渠道明细只列差异渠道。

## Runtime / Performance / Reliability

原因计算为内存 O(渠道数)，不新增 SQL；仍对异常详情限制 50 笔。

## Security / Permissions

不增加敏感字段，不返回商户密钥或第三方凭据；保持门店范围隔离。

## UI Design Track

NOT_APPLICABLE：服务端仓库响应契约增强，无 UI 编辑。

## Vertical Slice Plan

1. RED：新增原因码、总差额、渠道差异和日结汇总断言。
2. GREEN：在一致性服务内实现解释模型，在日结服务内聚合。
3. VERIFY：API 文档、专项/全量测试、审查和 JAR 构建。

## Verification Strategy

使用 `OrderLedgerConsistencyServiceTest` 覆盖缺失流水、错渠道、金额超额及正常/挂账路径；使用 `DailyCloseServiceTest` 覆盖 blocker 的原因汇总和令牌阻断；最后运行完整 Maven 测试、OpenAPI 解析、差异检查和打包。

## Rollback / Recovery

代码回退仅移除兼容新增字段，不涉及数据回滚或迁移。
