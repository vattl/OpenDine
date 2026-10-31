# Bug Report BUG006 — 同一桌台首单结账后续单覆盖上一单 KDS 工单缺陷审计与修复

## Status
- **Bug ID**: BUG006
- **Status**: FIXED
- **Severity**: CRITICAL
- **Found**: 2026-09-02
- **Root Cause**:
  `OrderController.java` 在创建堂食新单（`create`）更新桌台状态时，包含一段错误逻辑：通过 `table.getOrder_no()` 检索同桌上一张订单，并强制执行 `previousOrder.setOrder_receiving("off_order")`。当同一桌台第一单已完成结账（`transac_status='success'`）但在后厨 KDS 中仍在备餐/烤制/待传菜时，顾客或收银员在该桌再次下单（续单/加点），该逻辑会将第一单直接标记为已完成（`off_order`），导致 `CashierKdsProjectionService` 发送 `ORDER_CLOSED` 事件，KDS 厨显将第一单强行关闭移出看板，后厨与服务员无法获知第一单哪些菜品未上。

---

## 1. 现象与场景复现 (Symptom & Reproduction)

1. **场景流程**：
   - 顾客在 A08 桌扫码下单「第 1 单」（羊肉串 10 串），订单接单进入 KDS 处于制作中/待传菜状态；
   - 顾客采用现点现付或先行结账（`transac_status = 'success'`）；
   - 菜还没完全上齐，顾客在 A08 桌再次扫码下单「第 2 单」（烤鸡翅 2 串）；
   - 后厨 KDS 看板上的「第 1 单」瞬间消失或被标记完成，只剩下「第 2 单」，导致后厨不知道 A08 桌第 1 单的 10 串羊肉串还未制作/未上菜。

2. **代码缺陷定位**：
   - [`OrderController.java`](file:///g:/Mini%20Program/my_project_server/server/src/main/java/com/lanf/controller/OrderController.java) 第 1879-1894 行：
     ```java
     String previousOrderNo = table.getOrder_no();
     if (StringUtils.hasText(previousOrderNo) && !previousOrderNo.equals(orderEntity.getOrder_no())) {
         Order previousOrder = orderService.getOne(new QueryWrapper<Order>().eq("order_no", previousOrderNo).last("LIMIT 1"));
         if (previousOrder != null && !"off_order".equals(previousOrder.getOrder_receiving())) {
             previousOrder.setOrder_receiving("off_order"); // 错误：将第一单强行完结！
             ...
         }
     }
     ```
   - 当 `previousOrder.order_receiving` 被改成 `off_order` 后，`CashierKdsProjectionService` 判定 `projectionState` 为 `CLOSED` 并派发 `ORDER_CLOSED` 事件，KDS 看板将第 1 单视为已完结并归档移除。

---

## 2. 修复方案 (Fix Execution)

1. **彻底移除创建新单时强制修改上一单为 `off_order` 的逻辑**：
   - 订单的厨房生命周期由 KDS 流转（出餐/传菜/划单/整单完成）独立管控；
   - 桌台的就餐生命周期在收银端清台（`POST /cashier/table/clear`）时批量完结已结账订单；
   - 同一桌台追加新订单时，仅更新桌台的指针（`table.setOrder_no(newOrderNo)`）与状态（`table.setStatus(1)`），绝不篡改历史订单的 `order_receiving` 状态与 KDS 工单。
2. **回归测试验证**：
   - 新增单元测试 [`SameTableMultipleOrdersKdsAuditTest.java`](file:///g:/Mini%20Program/my_project_server/server/src/test/java/com/lanf/order/SameTableMultipleOrdersKdsAuditTest.java)：模拟同一桌台先下一单结账后再下一单，断言第一单的 `order_receiving` 保持 `rec_order` 且未被篡改，KDS 正常保留两单工单。
   - 全工程单元测试通过（621 个测试执行，0 failures，0 errors，1 skipped）。
   - 重新打包构建可运行 JAR 包。
