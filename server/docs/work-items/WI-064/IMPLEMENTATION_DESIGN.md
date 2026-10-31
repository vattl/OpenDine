# Implementation Design — WI-064

## Root Fix / Owner
新增 `OrderRevisionService` 作为非 KDS 订单业务写的版本边界。Controller 负责锁定并校验业务对象，服务只负责输入解析、陈旧版本拒绝、CAS 递增和最新摘要，避免每个入口各写一套冲突语义。

## Contract
- 请求体可选 `expectedVersion`，兼容别名 `expected_version`；必须为非负整数。
- 冲突抛出 `ApiException(409, ORDER_VERSION_CONFLICT, ...)`，`data` 返回 `orderNo/revision/transacStatus/settAmount/discountAmount/serviceFee`。
- 成功体增加 `revision`，现有字段不删除、不改类型。
- 兼容调用未携带版本时，以事务锁定时的当前 revision 为 CAS 基线，成功仍只增加 1。

## Transaction / Ordering
1. 按门店和订单锁定 `t_order`（`FOR UPDATE`）。
2. 解析并比较 expectedVersion；冲突立即抛出，不能进入审批或副作用。
3. 执行既有明细、库存、金额和桌台逻辑。
4. 以开始 revision 为条件执行 `revision = revision + 1`；0 行视为并发冲突并回滚事务。
5. 设置内存订单新 revision，再触发 KDS 提交后投影并返回响应。

## KDS Boundary
KDS-CA-1.3 保持不变：云端是唯一订单/revision 权威。KDS POS 加菜调用 `OrderController.addDishes` 后已经得到新的订单 revision，因此 KDS workflow 仅继续递增 ticket 与 kds-order 局部 revision，不再对该命令重复递增 `t_order.revision`。POS 退菜仍由 KDS workflow 自己完成订单 revision 递增，因为它不经过本次 HTTP Controller 路径。

## Compatibility / Rollback
- expectedVersion 在本项为可选，加法契约不破坏旧客户端。
- 回滚应用版本不会删除 revision 数据；版本值继续单调，旧程序可忽略。
- 不新增迁移；V008 是现有列真源，已应用迁移不可重写。

## Verification Strategy
先写 RED 单元/接线测试，再实现共享守卫与各入口；覆盖别名、非法值、冲突摘要、审批零消费、成功 +1、加菜投影顺序和 KDS 单次递增。最后执行相关订单/KDS回归、OpenAPI 解析、Work gate 和完整 Maven package。
