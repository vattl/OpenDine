# Impact Map — WI-009

## Authoritative Owner

`OrderController.addDishes` 是小程序、收银端与 AI 加菜的共享业务入口，也是订单主表更新的权威实现。

## Change Propagation Path

```text
小程序 / 收银端 / AI 加菜
→ OrderController.addDishes
→ t_order 金额/轮次更新 + t_order_detail 新增
→ 账单、KDS、报表读取
```

## Consumer Coverage

| Consumer | Relationship | Classification | Needs Change | Evidence |
|---|---|---|---|---|
| 小程序 `/order/addDishes` | 直接入口 | AFFECTED | 自动生效 | `OrderController.addDishes` |
| 收银 `/cashier/order/addDishes` | 委托共享入口 | AFFECTED | 自动生效 | `CashierOrderController.addDishesInternal` |
| AI `add_dishes` | 委托共享入口 | AFFECTED | 自动生效 | `OrderController` AI tool dispatch |
| 账单/报表/KDS | 读取 `order_time` | AFFECTED | 无代码变更 | 修复后读取稳定首单时间 |

## Layer Coverage

| Layer | Classification | Reason / Evidence |
|---|---|---|
| UI | NOT_APPLICABLE | 无 UI 变化 |
| Interaction | VERIFIED_UNAFFECTED | 加菜交互与字段不变 |
| Frontend State | VERIFIED_UNAFFECTED | 响应结构不变 |
| API Client | VERIFIED_UNAFFECTED | 无调用方式变化 |
| Request Contract | VERIFIED_UNAFFECTED | 请求字段不变 |
| Backend/Domain | AFFECTED | 移除 `order_time` 重置 |
| Persistence | AFFECTED | `t_order.order_time` 保持原值 |
| Response Contract | VERIFIED_UNAFFECTED | 响应字段不变 |
| Jobs/Events/Integrations | VERIFIED_UNAFFECTED | 仍发布相同订单/KDS事件 |
| Config/Security | VERIFIED_UNAFFECTED | 权限与门店隔离不变 |
| Runtime/NFR | VERIFIED_UNAFFECTED | 减少一次无意义字段变更 |
| Tests | AFFECTED | 新增回归断言并运行全套 |

## Duplicate Logic / Patch Smells

未发现其他生产加菜实现会改写订单时间；各入口均委托共享方法，修复共享 owner 可覆盖全部路径。

## Contract Delta Summary

仅修正持久化语义：`order_time` 明确为首单创建时间，加菜不再刷新。请求/响应无变化。

## UI Semantic Impact

NONE。

## Risks

- 依赖错误“刷新下单时间”行为的排序会恢复为按首单时间排序，这是目标行为。
- 必须验证加菜金额、轮次、明细和 KDS 流程未受影响。
