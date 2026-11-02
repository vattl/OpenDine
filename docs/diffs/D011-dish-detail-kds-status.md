# D011 菜品明细加入 KDS 制作状态进度（审计与方案）

- 日期：2026-09-08
- 状态：IMPLEMENTED（2026-09-08 按方案 A 落地：新增 KdsDetailStatusResolver + OrderDetail 非表字段 + 四接口联查，compile 通过；openapi v1.2.222 同步）
- 风险等级：ADDITIVE（仅新增返回字段，不改主链路写路径）
- 关联：`/change` 审计菜品明细是否能加入厨房 KDS 制作状态进度

## 1. SYMPTOM（现状缺口）

- 主库菜品明细 `t_order_detail` **无任何 KDS 制作状态字段**（仅有 `line_status` normal/refunded 退款态、`refunded_quantity`）。
- 收银端 `GET /cashier/order/search`、`GET /cashier/order/today`（返回 Order 分页）、运营端 `/admin/orderDetail/list`、C 端 `/order/history` 返回的订单明细**均不含**制作状态——收银/运营/小程序用户看不到"这道菜做到哪了"。
- KDS 厨显屏内部有完整明细进度（见 ROOT CAUSE），但**未对外暴露**。

## 2. ROOT CAUSE（根因）

KDS 制作状态**已经按明细粒度存在**，只是存在独立子系统的工单表，未回联主库明细、未在对外接口返回：

- `t_kds_ticket`（KDS 厨显工单）：一行 = 一条 `t_order_detail`（`detail_id` 关联），字段 `item_status`（0 待制作 / 1 制作中 / 2 已完成 / 3 已退菜）、分批数量 `prep_quantity`/`cooked_quantity`/`served_quantity`、催菜 `rush_flag`、超时 `overdue_flag`、加菜 `add_dish_flag`、抓串 `skewer_picked`、时间戳 `accepted_at`/`done_at`/`served_at`。
- 订单级 `kds_order_status`（10/20/30/40/90）由 `KdsOrderStatusAggregator` 从明细聚合，同步 `t_order.kds_order_status`（`KdsLegacySyncService.afterOrderKdsStatus`）+ `t_kds_order` + WS 广播 `order_status_changed`。
- 明细级变更实时广播：`KdsItemStatusChangedEvent` → `KdsEventListener.onItemStatusChanged` → WS `update_order`/`cancel_item`（厨显屏订阅）。
- 工单生成门禁：接单（`order_receiving` 已接）+ `kds_mode ∈ {kds_only, both}` 才建 `t_kds_ticket`（`KdsOrderHook` → `KdsTicketService.createTicketsForOrder`）。**print_only 门店不建工单**。
- 归档策略：`KdsArchiveJob` 仅将完成工单 `archived=1`（默认 2h），**不物理删除** → 历史明细可联查。

结论：**能加入，且 KDS 内部已具备明细级进度；缺的只是"对外接口层暴露"这一步。**

## 3. TARGET（目标口径）

在订单明细返回中携带 KDS 制作状态进度，覆盖收银/运营端（C 端小程序视产品需要决定是否展示）：

| 返回字段（明细行内） | 类型 | 语义 |
|---|---|---|
| `kds_item_status` | Integer/null | 0 待制作 / 1 制作中 / 2 已完成 / 3 已退菜；无工单（print_only、未接单、历史遗留）为 null |
| `kds_status_text` | String/null | 中文文案：待制作/制作中/已完成/已退菜 |
| `kds_served_quantity` | Integer | 已传菜确认数量（分批进度，可选） |

口径：状态以 `t_kds_ticket` 为**单一事实源**，主库明细不冗余（避免高频状态变更写主表、双写一致性问题）。

## 4. 方案对比

| 方案 | 做法 | 优点 | 缺点 | 结论 |
|---|---|---|---|---|
| **A 接口层联查**（推荐） | 订单详情/列表接口按 `detail_id` 集合批量 `IN` 查 `t_kds_ticket`，组装 `kds_item_status` 等字段返回 | 单一事实源、零双写、历史可查（ticket 不物理删）、改动集中 | 每次查询多一次批量联查（N+1 可控）；print_only/未接单返回 null | ✅ |
| B 主库冗余列 + 事件同步 | `t_order_detail` 加 `kds_item_status` 列，`KdsItemStatusChangedEvent` 消费时回写 | 查询零联查 | 高频状态双写主表（写放大）；主库/工单一致性问题；退款/加菜/归档路径都要同步 | ❌ |
| C 冗余列只做完结回写 | 明细加列，仅 DONE/VOID 时回写 | 查询简单、写频率低 | 实时性差（制作中状态看不到）；两态不同步的展示割裂 | 不推荐 |

## 5. FIX（方案 A 设计，待确认后实施）

### 5.1 新增服务方法（`KdsOrderListService` 或独立 `KdsDetailStatusResolver`）

```java
/** 按订单批量取制作状态，返回 Map<detail_id, KdsTicket>；无工单 detail 不在 map。 */
Map<Integer, KdsTicket> resolveByOrderIds(Collection<Integer> orderIds);
```

实现要点：
- 先按 `order_id IN (...)` 查（**复用现有索引 `idx_kds_ticket_order`**，避免为 detail_id 新建索引），再按 detail_id 折叠取最新一条（同一明细因重复加菜可能多条工单，取 `created_at` 最新）；
- 空集合直接返回空 Map，避免无效 SQL；
- 仅查询 `archived` 不设过滤（历史已归档工单也保留，保证历史订单明细仍可展示状态）。

### 5.2 接口组装（收银端优先）

- `GET /cashier/order/search`、`/cashier/order/today`：需要明细的收银查询接口（如详情/加菜回显）在返回 `goods_list` 时逐行补 `kds_item_status`/`kds_status_text`；
- `/admin/orderDetail/list`：运营端明细列表逐行补字段；
- C 端 `/order/history`：可选（小程序是否展示"制作中"由产品定）；
- 公共映射工具：`item_status → 文本`（0 待制作 / 1 制作中 / 2 已完成 / 3 已退菜），`null → null`（前端不展示）。

### 5.3 覆盖边界与缺省

- print_only 模式门店：无工单 → 明细 `kds_item_status=null`，前端不渲染该列/显示"—"；
- 未接单（`order_receiving != 已接`）：无工单 → null；
- 已退菜明细：工单 `item_status=3` 已退菜（若退款时工单未生成则 null，以 `line_status=refunded` 为准）；
- 订单取消：工单批量置 3（VOID）→ 明细显示"已退菜/已取消"。

## 6. REGRESSION（实施后验证项）

1. 单测：`resolveByOrderIds` 空集合/单订单/多订单/重复工单折叠/无工单返回空 Map。
2. 接口回归：收银建单 → KDS 接单 → 厨显推进状态（待制作→制作中→已完成）→ 收银 `/cashier/order/search` 明细 `kds_item_status` 实时同步；分批传菜 `kds_served_quantity` 正确。
3. print_only 门店：明细 `kds_item_status=null`，接口不报错。
4. 性能：按 `order_id` 批量查复用 `idx_kds_ticket_order`，无需新建索引；100 明细订单接口耗时增加 < 5ms。

## 7. 交付说明

- 本次为**审计交付**：确认 KDS 明细级状态已存在（`t_kds_ticket.item_status`），缺口仅为对外接口暴露；推荐方案 A（接口层联查，零表结构变更）。
- 未实施：等确认方案方向（A/B/C 或 C 端是否展示）后再落地代码、迁移与 openapi 同步。
- 关联现状：`t_order.kds_order_status`（订单级）已通过 `afterOrderKdsStatus` 同步主库；本次不动该机制。
