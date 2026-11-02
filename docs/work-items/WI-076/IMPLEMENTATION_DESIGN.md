# Implementation Design — WI-076

## Root Fix / Owner

- 核心业务主管服务：`TakeoutZsqIntegrationServiceImpl`（负责订单类型判定、配送记录防重校验、真省钱呼叫骑手请求组装与异常降级）。
- 厨显事件监听层：`KdsEventListener`
  - 在 `onOrderStatusChanged` 中捕获 `KdsOrderStatusChangedEvent(ALL_DONE)`。
  - 在事务提交后（`AFTER_COMMIT`）调用 `takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(e.getOrderId())`。

## 架构与设计原则

- **事件驱动与副作用解耦**：
  KDS 划菜出餐更新 Ticket 与 FlowBatch，并在整单全部完成时在事务内计算并发布 `KdsOrderStatusChangedEvent(ALL_DONE)`。
  `KdsEventListener` 在 `TransactionPhase.AFTER_COMMIT` 阶段捕获该事件，此时出餐状态已强一致持久化。外卖自动叫骑手作为出餐后的外部履约协同副作用在此处触发，确保即便第三方网络抖动，出餐与划菜动作绝对安全。

- **三层幂等防重机制**：
  1. **订单类型校验**：仅当 `order.getDineInOrTakeOut()` 为 `"外卖"` 时继续，堂食/自提直接退出。
  2. **配送单存在性**：外卖订单创建时均已初始化 `t_takeout_delivery` 记录；若无记录或已处于终态直接退出。
  3. **状态机防重**：
     - 若 `zsq_dispatch_status` 处于 `"dispatched"` 或 `"completed"`，说明已经呼叫过骑手，退出；
     - 若 `zsq_dispatch_status` 处于 `"pending"`，说明正在向配送平台发起，退出；
     - 若 `dispatch_status` 已处于 `"delivering"` 或 `"completed"`，说明骑手已接单或配送中，退出；
     - 仅当配送状态为尚未叫骑手或可重试状态时，执行 `dispatchToZsq(orderId, false)`。

- **异常兜底与可观测性**：
  使用独立的 try-catch 块包裹调度逻辑，记录带有 `shopId`、`orderId`、`orderNo` 的明确日志。第三方调用失败只打印 WARN 日志，由运营后台配送单列表的异常标识及重发入口承接人工处理。

## 接口与方法签名设计

```java
// ITakeoutZsqIntegrationService.java
/**
 * KDS 厨显整单出餐完成（KdsOrderStatus.ALL_DONE）后尝试自动发真省钱叫骑手配送。
 * 具备订单类型检查、状态幂等保护及异常隔离。
 *
 * @param orderId 订单ID
 */
void tryAutoDispatchOnKdsCompleted(Integer orderId);
```

```java
// KdsEventListener.java
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT, fallbackExecution = true)
public void onOrderStatusChanged(KdsOrderStatusChangedEvent e) {
    ...
    if (e.getToStatus() == KdsOrderStatus.ALL_DONE) {
        // 1. 触发通知客户取餐（堂食/打包自提）
        if (customerPickupNoticeService != null) { ... }
        // 2. 触发外卖自动叫骑手
        if (takeoutZsqIntegrationService != null) {
            try {
                takeoutZsqIntegrationService.tryAutoDispatchOnKdsCompleted(e.getOrderId());
            } catch (Exception ex) {
                log.warn("[kds] 全部菜品完成自动叫骑手异常 order={}: {}", e.getOrderId(), ex.getMessage());
            }
        }
    }
}
```

## Verification Strategy

1. **单元测试与分流断言**：
   编写 `KdsTakeoutAutoDispatchTest`，覆盖：
   - 非外卖订单（堂食/打包自提）整单完成不触发叫骑手；
   - 外卖订单未整单完成（部分出餐）不触发叫骑手；
   - 外卖订单整单完成首次触发自动叫骑手；
   - 处于 `dispatched`/`pending`/`delivering`/`completed` 状态的订单幂等跳过；
   - 模拟真省钱接口异常，断言异常被安全吞吐并记录日志，主流程不中断。
2. **文档与打包验证**：
   - 同步更新 `docs/openapi.yaml` 与 `docs/API.md`。
   - 执行 `.\mvnw.cmd clean package -DskipTests` 生成完整 runnable JAR 产物。
