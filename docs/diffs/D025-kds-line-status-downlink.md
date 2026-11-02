# D025 — KDS 明细制作状态云端下行（方案 B）

> 状态：
>
> **方案待确认**
>
> （未动代码）
> 分支：
>
> `codex/audit-remediation`
>
> 　范围：
>
> `server`
>
>  子项目
> 关联：D021-D024 已提交；上一轮已完成 KDS 表审计与投影链路审计

## 1. 背景与目标

### 1.1 背景



* 云端 → 收银端的投影链路（`t_kds_projection_intent → t_kds_delivery_event → events(afterCursor)`）已存在，但 payload 的 `lines` 是**订单明细快照**（数量 / 剩余 / 工作流队列 / 行状态），**不包含**云端 `t_kds_ticket` 的制作状态（`item_status`、`prep/cooked/served_quantity`、`rush_flag`、`overdue_flag`、`add_dish_flag`、`archived`）。

* 制作状态目前**只有收银端 → 云端**方向（`/admin/kds/replication/events` 复制 + `KdsSyncService` 离线回写），**没有云端 → 收银端**的明细状态下行通道。

* 云端侧状态权威变化（设备走云端 API 推进、云端 SLA 定时催菜 / 超时）无法增量通知收银端本地 KDS。

### 1.2 目标

新增下行事件类型 `ORDER_LINE_STATUS_CHANGED`：云端状态写路径在事务内发布**明细级增量状态**，复用现有 `t_kds_delivery_event` + cursor + ack 通道，收银端按 `detailId` 应用本地工单状态。

### 1.3 非目标（明确不做）



* 不动收银端 → 云端复制链路（`/admin/kds/replication/events`、`KdsReplicationService`、`KdsSyncService`）。

* 不动订单级投影语义（`ORDER_ACCEPTED / ORDER_UPDATED / ORDER_CANCELLED / ORDER_CLOSED`）。

* 不新增 / 修改任何数据库表（**无 DDL**）。

* 不解决云端 `t_kds_ticket` 停更问题（前置项，见 §7 风险）。

## 2. 现状（Current State）

### 2.1 云端 → 收银端投递链路（已审计确认）



```
触发：KdsOrderHook.afterOrderCommitted（接单/加菜/付款/手动）

&#x20; → publishAfterCommit(orderId, eventType, channel, deviceCode, changedDetailIds)

&#x20; → INSERT t\_kds\_projection\_intent(order\_id, event\_type, changed\_detail\_ids\_json)

&#x20; → afterCommit → CashierKdsProjectionPublishRetry.submit → processIntent(id)

&#x20; → publish(orderId, eventType, ...)

&#x20;     loadOrder(t\_order) → projectionState(VOIDED/CLOSED/READY)

&#x20;     → loadLines(t\_order\_detail 全量明细快照)

&#x20;     → sha256(payload) 与 t\_kds\_order\_projection.payload\_hash 比对（相同跳过）

&#x20;     → INSERT t\_kds\_delivery\_event(...payload\_json...)

&#x20;     → UPDATE t\_kds\_order\_projection(projection\_version, payload\_hash, last\_event\_cursor)

&#x20;     → wakeHub.broadcastWake(shopId, cursor)

消费：收银端 events(afterCursor) 拉增量 → ack(cursor) → t\_kds\_delivery\_consumer
```

### 2.2 云端 t\_kds\_ticket 状态写路径（埋点候选全景）



| # | 写路径                                                              | 入口                                                                  | 触发方             | 现有推屏                                                           |
| - | ---------------------------------------------------------------- | ------------------------------------------------------------------- | --------------- | -------------------------------------------------------------- |
| 1 | `KdsWorkflowService.advanceDetail → advancePrep/Cook/Serve`      | `/kds/workflow/*`、`/kds/item/status/update`                         | KDS 屏设备（云端 API） | `pushWorkflowQuantity`（KDS 屏）                                  |
| 2 | `KdsTicketService.updateItemStatus`（0-3 直切）                      | `/kds/item/status`；**也被&#x20;**`KdsSyncService.syncAll`**&#x20;复用** | 设备；收银端离线回写      | `pushService.updateOrder/cancelItem`                           |
| 3 | `KdsTicketFlagService.rushOrder`（催菜）                             | 管理端 / 定时                                                            | 云端权威            | 推屏（toFlagPayload）                                              |
| 4 | `KdsTicketFlagService.refreshOverdueForShop`（超时）                 | `KdsTicketSlaScheduler` 定时                                          | 云端权威            | —                                                              |
| 5 | `KdsOrderHook.afterRefundDetails / afterOrderCancelled`（退菜 / 取消） | 订单 API                                                              | 云端权威            | **已有投影** ORDER\_UPDATED（lines 含 REFUNDED/CANCELLED）→ 已覆盖，不重复埋点 |
| 6 | `KdsOrderStatusAggregator.aggregateAndSave(orderClosed=true)`    | `KdsOrderHook.afterOrderCancelled`                                  | 云端权威            | 已覆盖（投影 VOIDED/CLOSED）                                          |

### 2.3 回声风险（必须处理）



* `KdsSyncService.syncAll`（收银端离线回写）内部复用 `updateItemStatus`；`KdsReplicationService` 直写 jdbc。

* 若埋点在 `updateItemStatus` 或复制链路，会把 "收银端自己上报的状态" 再下行回收银端 → **回声**。

* 结论：**埋点不放在&#x20;**`updateItemStatus`；复制链路天然不触发（不经过埋点方法）。

## 3. 目标（Target State）

### 3.1 新增



* **事件类型常量**：`CashierKdsProjectionService` 增加 `ORDER_LINE_STATUS_CHANGED = "ORDER_LINE_STATUS_CHANGED"`；`normalizeEventType` 透传该类型（不被折叠为 ORDER\_UPDATED）。

* **载荷模型** `LineStatusDelta`（内部静态类或 Map 组装）：



```
detailId            int

itemStatus          int     （0/1/2/3，复用 KdsItemStatus）

prepQuantity        int

cookedQuantity      int

servedQuantity      int

rushFlag            int

overdueFlag         int

addDishFlag         int

archived            int

updatedAtMs         long    （ticket.updated\_at 时间戳，收银端据此做新旧裁决）
```



* **方法**：



```
// CashierKdsProjectionService

public void publishLineStatus(int shopId, int orderId,

&#x20;                             Collection\<LineStatusDelta> deltas);
```

行为：组装 `{eventType:"ORDER_LINE_STATUS_CHANGED", orderId, orderNo, shopId, lines:[delta...]}` → `INSERT INTO t_kds_delivery_event(...)` → `wakeHub.broadcastWake(shopId, cursor)`。



* **同事务**：在调用方事务内执行（写库 1 行，成本极低）。

* **失败不阻断**：捕获异常仅记录 `[cashier-kds-delivery] line-status publish failed ...` + 指标计数；主业务（划菜 / 催菜 / 超时）不回滚。辅助同步降级为收银端 bootstrap / 营业日快照兜底。

* **不碰** `t_kds_order_projection`（订单级投影幂等独立；line status 事件不污染订单快照 hash）。

### 3.2 修改（第一批埋点，3 处）



1. `KdsWorkflowService.advanceDetail`（含 `advanceFifo` 间接路径）尾部：组装 `{detailId, itemStatus, prep/cooked/servedQuantity, rush/overdue/addDishFlag, archived, updatedAtMs}` → `publishLineStatus`。

* 取 `advanceResult` 后的 `findActiveTicket(shopId, detailId, toQueue)` / 事务内最新 ticket 快照。

* 覆盖场景：云端设备推进（配菜→制作→传菜），本地收银端 / 其他屏同步。

1. `KdsTicketFlagService.rushOrder` 成功尾部：`rushFlag=1, rush_at` → `publishLineStatus`（单明细或整单明细）。

2. `KdsTicketFlagService.refreshOverdueForShop` 中对每张新超时 ticket：`overdueFlag=1, overdue_at` → `publishLineStatus`（仅状态翻转的行，避免批量全量下发）。

### 3.3 明确不改



* `KdsTicketService.updateItemStatus`（回声风险，见 §2.3）。

* `KdsOrderHook`（退菜 / 取消已由订单投影覆盖）。

* `KdsReplicationService` / `KdsSyncService`（收银端→云端方向不动）。

* 数据库表结构（无 DDL）。

* `t_kds_order_projection` 写入逻辑。

### 3.4 收银端契约（对外）



* `events(afterCursor)` 返回中可能出现 `eventType="ORDER_LINE_STATUS_CHANGED"`：


  * `changedDetailIds` = 本次变更明细列表（与 `projection.lines[*].detailId` 一致）。

  * `projection` 结构：`{eventType, orderId, orderNo, shopId, lines:[{detailId,itemStatus,prepQuantity,cookedQuantity,servedQuantity,rushFlag,overdueFlag,addDishFlag,archived,updatedAtMs}]}`。

  * **应用规则**：按 `detailId` 定位本地工单；`updatedAtMs` 新于本地 `updated_at` 才应用，否则忽略（防过期状态回退）。

  * **兼容**：不识别该类型的旧收银端直接跳过该事件即可（事件按 `id` 递增，跳过不影响后续）。

## 4. Structural Diff 分类



| 元素                                           | 操作        | 说明                                                                                                   |
| -------------------------------------------- | --------- | ---------------------------------------------------------------------------------------------------- |
| `CashierKdsProjectionService`                | ADD       | `publishLineStatus` + `LineStatusDelta` + `ORDER_LINE_STATUS_CHANGED` 常量 + `normalizeEventType` 透传分支 |
| `KdsWorkflowService.advanceDetail`           | MODIFY    | 尾部追加 line-status 发布（失败仅日志）                                                                           |
| `KdsTicketFlagService.rushOrder`             | MODIFY    | 尾部追加 line-status 发布                                                                                  |
| `KdsTicketFlagService.refreshOverdueForShop` | MODIFY    | 状态翻转行追加 line-status 发布                                                                               |
| `KdsTicketService.updateItemStatus`          | UNCHANGED | 回声风险，不埋点                                                                                             |
| `KdsOrderHook`                               | UNCHANGED | 退菜 / 取消已由订单投影覆盖                                                                                      |
| `KdsReplicationService` / `KdsSyncService`   | UNCHANGED | 收银端→云端方向不动                                                                                           |
| `t_kds_delivery_event` 等表                    | UNCHANGED | 无 DDL                                                                                                |
| `docs/API.md`、`docs/openapi.yaml`、收银端调用指南    | MODIFY    | 补充新事件类型契约                                                                                            |
| 测试                                           | ADD       | 见 §6                                                                                                 |

## 5. 影响分析



| 维度   | 影响                                                                                |
| ---- | --------------------------------------------------------------------------------- |
| 影响面  | `CashierKdsProjectionService`、`KdsWorkflowService`、`KdsTicketFlagService`、契约文档、测试 |
| 不涉及  | 复制协议、订单 API、小程序 / 管理端接口、数据库结构                                                     |
| 向后兼容 | 旧收银端跳过未知 event\_type，无破坏                                                          |
| 性能   | 每次推进 / 催菜 / 超时翻转 +1 条 INSERT（高频但单行、无索引变更）；`refreshOverdueForShop` 只发翻转行           |
| 一致性  | 收银端按 `updatedAtMs` 新旧裁决；发布失败仅日志（辅助同步，快照兜底）                                        |
| 可观测  | 新增 `[cashier-kds-delivery] line-status published/failed` 日志 + 计数                  |

## 6. 任务拆分（Tasks + DoD + 负向验收）



| #  | 任务                                                                         | Diff   | DoD（正向验收）                                                                                                  | 负向验收                                       |
| -- | -------------------------------------------------------------------------- | ------ | ---------------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| T1 | `CashierKdsProjectionService` 新增 `publishLineStatus`/`LineStatusDelta`/ 常量 | ADD    | 编译通过；单测：payload 结构正确、正常写入 `t_kds_delivery_event`、异常被捕获不抛出                                                  | 事件不写 `t_kds_order_projection`（hash / 版本不变） |
| T2 | `KdsWorkflowService.advanceDetail` 尾部埋点                                    | MODIFY | 云端推进后 1s 内 `delivery_event` 出现 `ORDER_LINE_STATUS_CHANGED`，payload 与 ticket 列一致（itemStatus / 数量 /archived） | 推进主事务不因发布失败回滚                              |
| T3 | `KdsTicketFlagService.rushOrder` 埋点                                        | MODIFY | 催菜后下行 `rushFlag=1`                                                                                         | 未催菜不产生该事件                                  |
| T4 | `KdsTicketFlagService.refreshOverdueForShop` 埋点                            | MODIFY | 超时翻转后下行 `overdueFlag=1`（仅翻转行）                                                                              | 无翻转时不产生事件                                  |
| T5 | 回声防护验证                                                                     | —      | 模拟 `KdsSyncService.syncAll` 回写后，`delivery_event` 无新增 line-status 事件                                        | —                                          |
| T6 | 契约与文档同步                                                                    | MODIFY | `docs/API.md`、`docs/openapi.yaml`、收银端调用指南含新事件类型与应用规则                                                       | 文档不含已删除 / 过时描述                             |
| T7 | 测试 + 构建 + 提交                                                               | —      | 现有测试全绿；`mvn clean package -DskipTests` 成功；按任务范围提交                                                          | 无越界文件入提交                                   |

## 7. 风险与回退



1. **云端停更前置**（已知）：若 `t_kds_ticket` 仍停更（上一轮问题未解决），下行状态可能是旧值 → 由收银端 `updatedAtMs` 新旧裁决兜底（本地新则忽略）。本方案不依赖停更修复，但建议先修。

2. **事件膨胀**：高频推进场景事件量大。第一批不做窗口合并，先以日志 / 指标观察；如超预期再按 `orderId+detailId` 做 1s 合并窗口（第二期）。

3. **回退**：埋点均为尾部追加、失败不阻断 → 去掉埋点即回退；事件类型独立，旧收银端天然兼容。

4. **整单完成（ALL\_DONE=40）下行**：第一批不做（与订单投影 `ORDER_CLOSED` 语义需对齐后二期做），避免状态机重叠。

## 8. 执行顺序

T1 → T2/T3/T4 → T5（负向验证）→ T6（文档）→ T7（全量测试 / 构建 / 提交）。

## 9. 验收总览（用户可检查）



* [ ] 云端划菜 / 队列推进后，`t_kds_delivery_event` 出现 `ORDER_LINE_STATUS_CHANGED`，payload 携带 detailId + 制作状态。

* [ ] 云端催菜、SLA 超时后，对应 flag 随事件下行。

* [ ] 收银端离线回写（`KdsSyncService` / 复制上报）不产生回声下行。

* [ ] 收银端按新契约应用后本地工单状态与云端一致（`updatedAtMs` 新者优先）。

* [ ] 现有测试通过 + `mvn clean package -DskipTests` 构建成功 + openapi/API 文档同步。