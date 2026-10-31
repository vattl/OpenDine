# Impact Map — WI-012

## Authoritative Owner

订单主表金额字段及 `OrderNetRevenue.netRevenueYuan(order)` 是订单实际净应付金额 owner；`AdminTableController.status` 只聚合当前桌订单，不再从明细重建金额。

## Change Propagation Path

```text
t_order 持久化金额
→ OrderNetRevenue
→ TableStatusAmountCalculator audit/result
→ GET /admin/table/status
→ tableList[].amount / amountAudit.payable_amount
```

## Consumer Coverage

| Consumer | Classification | Handling |
|---|---|---|
| 收银桌台状态 | AFFECTED | 改用订单实际净应付金额 |
| 合并桌台 | AFFECTED | 对订单净应付逐单求和 |
| 历史订单查询 | VERIFIED_UNAFFECTED | 保留不覆盖复用桌台金额保护 |
| 订单明细展示 | VERIFIED_UNAFFECTED | 仍返回 goods_list |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 不修改 UI；修正既有 API 数据 |
| API Client | VERIFIED_UNAFFECTED | 路径和字段保持兼容 |
| Request Contract | VERIFIED_UNAFFECTED | 查询参数不变 |
| Backend/Domain | AFFECTED | 桌台金额 owner 调整 |
| Persistence | VERIFIED_UNAFFECTED | 无 schema 变化 |
| Response Contract | AFFECTED | 金额语义与 calculation_source 修正 |
| Security | VERIFIED_UNAFFECTED | 权限和门店隔离不变 |
| Tests | AFFECTED | 新增回归并更新旧口径断言 |

## UI Semantic Impact

NONE；仅把错误金额纠正为订单实际金额。

## Risks

- 旧测试依赖明细重算口径，需要更新为订单权威口径。
- 必须保留优惠、退款和礼品支付扣减。
