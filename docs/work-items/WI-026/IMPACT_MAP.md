# Impact Map — WI-026

## Authoritative Owner

- 比对规则与异常分类：`OrderLedgerConsistencyService`。
- 日结阻断响应组装：`DailyCloseServiceImpl`。
- API 契约：`docs/openapi.yaml`、`docs/API.md`。

## Change Propagation Path

```text
日结预检请求
→ DailyCloseServiceImpl
→ 成功非挂账订单集合
→ OrderLedgerConsistencyService
→ 只读查询成功资金流水
→ 异常原因/渠道差额
→ blockers 响应
→ 收银或财务人员定位异常
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 收银/管理端日结页 | 读取预检 blockers | AFFECTED | OPTIONAL | 新字段为兼容增加，旧字段保留 |
| 日结执行 | 依赖预检令牌 | VERIFIED_UNAFFECTED | NO | 差异仍不签发令牌 |
| 财务对账 | 使用同一资金事实 | VERIFIED_UNAFFECTED | NO | 不修改流水或对账数据 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 当前仓库无 UI 生产代码 |
| Interaction | NOT_APPLICABLE | 仅服务端响应增强 |
| Frontend State | NOT_APPLICABLE | 消费端可渐进采用新字段 |
| API Client | AFFECTED | 可展示新增解释字段，无破坏性变更 |
| Request Contract | VERIFIED_UNAFFECTED | 路径和请求参数不变 |
| Backend/Domain | AFFECTED | 新增异常分类、差额和汇总 |
| Persistence | VERIFIED_UNAFFECTED | 只读现有订单与流水表 |
| Response Contract | AFFECTED | blockers 明细兼容增加字段 |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | 无事件或外部渠道变更 |
| Config/Security | VERIFIED_UNAFFECTED | 门店权限和范围不变 |
| Runtime/NFR | VERIFIED_UNAFFECTED | 复用已批量加载的数据，不增加查询次数 |
| Tests | AFFECTED | 单元测试覆盖原因分类与日结响应 |

Material UNKNOWN count: 0

## Duplicate Logic / Patch Smells

原因推导只放在 `Issue` 构造逻辑中；日结服务仅聚合原因码，不重复计算金额差异。

## Contract Delta Summary

`ORDER_LEDGER_MISMATCH` 的 `details[]` 兼容新增原因、总额、差额和渠道差异字段；阻断项新增 `reason_summary`。

## UI Semantic Impact

无生产 UI 修改。消费端可直接展示服务端中文原因，不需要自行推算。

## Risks

- 差额符号误读：通过字段文档和测试固定为 `ledger - order projection`。
- 一个订单存在多个原因：使用稳定数组，不以单一原因覆盖其他异常。
- 明细过大：维持最多 50 笔，汇总覆盖全部异常。
