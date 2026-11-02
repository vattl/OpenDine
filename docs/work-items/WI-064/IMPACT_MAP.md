# Impact Map — WI-064

## Authoritative Owners
- 订单业务 revision：`t_order.revision`，云端 MySQL 唯一权威。
- 版本校验与单调递增：新增共享 `OrderRevisionService`。
- 加菜业务事务：`OrderController.addDishes`。
- 收银退菜/改价/优惠：`CashierOrderController` 及既有领域服务。
- KDS：只消费云端已提交 revision；不得形成第二权威。

## Change Propagation
```text
client expectedVersion (optional compatibility)
→ lock authoritative order
→ compare expected/current before authorization and mutation
→ execute existing business mutation
→ CAS revision = current + 1 in same transaction
→ return revision / publish committed KDS projection
```

## Layer Coverage
| Layer | Classification | Evidence / obligation |
|---|---|---|
| UI | VERIFIED_UNAFFECTED | 本仓库无生产 UI |
| Flutter/mini program | AFFECTED | 保存响应 revision；写入携带 expectedVersion；409 后刷新 |
| API contract | AFFECTED_COMPATIBLE | 新增可选请求字段、成功字段与 409 结构 |
| Controllers | AFFECTED | 五个入口接入同一守卫 |
| Domain/service | AFFECTED | 新增 revision 唯一编排服务 |
| Persistence | AFFECTED_NO_SCHEMA | V008 已存在 NOT NULL DEFAULT 0 revision；使用事务内 CAS |
| Approval | VERIFIED_PRESERVED | 冲突校验必须早于 token 消耗 |
| Pricing/table/stock | VERIFIED_PRESERVED | 冲突零副作用，成功仍走原业务路径 |
| KDS | AFFECTED_COMPATIBLE | POS 加菜避免重复递增；云端权威和命令账本不变 |
| Idempotency | DEFERRED_EXPLICIT | 头字段统一与 PENDING 语义属于 WI-065 |

## Consumers
| Consumer | Status | Obligation |
|---|---|---|
| Flutter cashier/admin | HANDOFF | 缓存最新 revision，写请求携带 expectedVersion，409 刷新 |
| Mini program | HANDOFF | 加菜同上；兼容期可不传 |
| KDS v2 | DIRECT_CHANGE | POS 加菜不得二次增加 t_order revision |

## Material Unknowns
0
