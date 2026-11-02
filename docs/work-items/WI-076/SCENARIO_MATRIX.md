# Scenario Matrix — WI-076

## Scenarios

| Scenario ID | Category | Description | Preconditions | Inputs / Trigger | Expected Output / State |
|---|---|---|---|---|---|
| SC-01 | 正向外卖出餐 | 外卖订单所有菜品划菜出餐完成 | 外卖订单，配送状态为初始态 | `KdsOrderStatusChangedEvent(ALL_DONE)` | 触发 `dispatchToZsq(orderId, false)`，向真省钱请求叫骑手，状态进入 pending/dispatched |
| SC-02 | 堂食过滤 | 堂食订单所有菜品出餐完成 | `dine_in_or_take_out="堂食"` | `KdsOrderStatusChangedEvent(ALL_DONE)` | 忽略叫骑手逻辑，不调用真省钱配送接口 |
| SC-03 | 自提打包过滤 | 打包自提订单所有菜品出餐完成 | `dine_in_or_take_out="打包"` | `KdsOrderStatusChangedEvent(ALL_DONE)` | 忽略叫骑手逻辑，仅触发客户取餐通知 |
| SC-04 | 部分出餐状态 | 订单部分菜品划菜完成，整单仍在制作中 | 外卖订单，状态流转至 `COOKING` / `COOKED` | `KdsOrderStatusChangedEvent(COOKED)` | `toStatus != ALL_DONE`，绝不触发叫骑手 |
| SC-05 | 幂等防重（已派送） | 外卖订单已由收银或商家接单提早发过配送 | 外卖订单，`zsq_dispatch_status="dispatched"` | `KdsOrderStatusChangedEvent(ALL_DONE)` | 幂等拦截，跳过调用，不重复发单 |
| SC-06 | 幂等防重（派送中） | 外卖订单正在向配送平台发起中 | 外卖订单，`zsq_dispatch_status="pending"` | `KdsOrderStatusChangedEvent(ALL_DONE)` | 幂等拦截，跳过调用，不重复发单 |
| SC-07 | 异常容错 | 呼叫骑手时第三方真省钱接口超时或报错 | 外卖订单，第三方网络异常 | `KdsOrderStatusChangedEvent(ALL_DONE)` | 异常被内部 catch 并记录 WARN 日志，KDS 整单出餐流程正常完成，不抛出任何异常 |
