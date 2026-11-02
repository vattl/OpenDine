# KDS 美团业务流程对齐说明

参考 `美团KDS（厨房显示系统）产品原理&全流程逻辑说明书.md`，本后端在保持既有 `/kds/workflow/*` 契约的前提下，补齐批次 FCFS、撤销、等叫与看板增强。

## 部署迁移

按顺序执行（若尚未执行）：

1. `docs/db_migration_kds_ticket_prep_cooked_quantity.sql` — 工单 `prep_quantity` / `cooked_quantity`
2. `docs/db_migration_kds_flow_batch.sql` — 流转批次表 `t_kds_flow_batch`
3. `docs/db_migration_kds_merge_meituan.sql` — 门店合并配置 `merge_same_dish` / `pack_inline_merge` / `combo_merge`

## 核心模型


| 概念        | 实现                                                                                                    |
| --------- | ----------------------------------------------------------------------------------------------------- |
| 原始明细不物理合并 | `t_kds_flow_batch` 按 `detail_id` + `ticket_id` 拆批次                                                    |
| FCFS 配菜   | `pending_prep` 按 `order_time` 升序核销                                                                    |
| FCFS 制作   | `pending_cook` 按 `prep_at`（配菜完成时刻）升序                                                                  |
| FCFS 传菜   | `ready_serve` 按 `cooked_at` 升序                                                                        |
| 工单聚合量     | `KdsFlowBatchService.syncTicketAggregates` 回写 `prep_quantity` / `cooked_quantity` / `served_quantity` |
| 历史工单兼容    | `ensureInitialized` 从聚合量迁移为批次                                                                         |


## 队列与 skewer_gate

- `**skewer_gate=1**`：创单时 `skewer_picked=0`，待配菜队列有工作；配菜推进后进入待制作。
- `**skewer_gate=0**`：创单即 `skewer_picked=1`，仍可有 `pending_prep` 工作（数量化配菜）；`queue_counts.pending_prep` **始终统计**，不再因 gate 关闭而置 0。

## 接口（新增）


| 方法   | 路径                      | 说明                                                                          |
| ---- | ----------------------- | --------------------------------------------------------------------------- |
| POST | `/kds/workflow/revoke`  | 撤销划菜（`ready_serve`→`pending_cook`）或撤销配菜（`pending_cook`→`pending_prep`），LIFO |
| POST | `/kds/workflow/hold`    | 等叫：`order_rece=mis_order`                                                   |
| POST | `/kds/workflow/release` | 起菜：`order_rece=rec_order`                                                   |


既有 `**advance` / `lack` / `refund` / `board`** 路径与请求体不变；推进逻辑改为走批次服务。

## 看板增强

- `**dining_breakdown`**：`{dine_in, pack, takeout}` 当前队列份数
- `**dining_breakdown_text**`：如「堂10｜打包5」
- `**flow_batches**`：行级批次列表（调试与细粒度展示）

## 合并展示（完全美团模式，v1.2.127）

门店配置 `**t_kds_shop_config**`（迁移 `**docs/db_migration_kds_merge_meituan.sql**`）：


| 字段                  | 默认  | 说明                           |
| ------------------- | --- | ---------------------------- |
| `merge_same_dish`   | 1   | 同屏跨订单/跨桌合并相同菜品；0=按明细一行（一桌一行） |
| `pack_inline_merge` | 1   | 堂食+打包内嵌同一行；0=按堂/打包/外卖拆行      |
| `combo_merge`       | 1   | 套餐子菜与散点同菜合并；0=套餐独立成行         |


- **全队列继承**：`pending_prep` / `pending_cook` / `ready_serve` / `done` 均使用同一套门店合并配置
- **四要素**：菜名 + `spec_norm` + `taste_norm` +（拆行模式下）就餐渠道
- **标签**：催/超/等/加打在 `lines[]` 上，**不**拆散合并组（与美团一致）
- **临时覆盖**：`GET /kds/workflow/board?merge_rules=none` 或 `split_pack_takeout=1` 仍可覆盖门店配置
- 运营维护：`GET|POST /admin/kds/config/`*

## 订单状态

`KdsOrderStatusAggregator` 在存在数量进度时按 **已传份数 / 明细总份数** 计算 `WAITING` / `COOKING` / `PARTIAL` / `ALL_DONE`；无数量字段时回退 `item_status` 行数统计（兼容旧数据）。

## 退菜 / 取消 / 减量

- 整单退菜：`voidByDetailIds` 同步作废批次
- 整单取消：`voidByOrderId`
- 改数量：`clampAfterDetailChange` 按 FIFO 收敛批次

## 与美团说明书的差异（已知）

- 打包/外卖黄底高亮、渠道置顶排序：由前端根据 `pack_flag`/`takeout_flag` 渲染
- 叫号屏 / 打印联动：沿用现有飞鹅与 WS 推送，未新增独立叫号 API

