# Layer Impact Matrix — WI-035

| Producer | Contract | Consumer | Required Change | Status |
|---|---|---|---|---|
| `OrderController.addDishes` | 更新订单后同步桌台金额 | 桌台列表/收银 UI | 后端按整桌未结订单汇总 | READY |
| `CashierOrderController.addDishes` | 委托公共加菜接口 | `OrderController` | 无额外客户端适配 | VERIFIED |
| `CashierTableOperationTransactionalService` | 并台后的整桌金额 | `t_table` | 已使用统一净额，无修改 | VERIFIED |
| `AdminTableController.status` | 实时桌台金额 | 收银 UI | 已按订单持久化净额重算，无修改 | VERIFIED |

## Handoff

无需消费者代码修改；API 文档记录语义修正。
