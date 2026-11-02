# 收银端协调：dish_availability.stock「不限量」哨兵（-1）兼容

> **背景问题**：收银端上报 `kds_state_changed` 事件时，`dish_availability[].stock` 直接外发了本地库存值。
> 本地「不限量」菜品在 `t_dish_shop.stock` 中以 **-1** 表示，导致云端校验报
> `stock must be a non-negative integer`，事件进入死信队列（error_code 4091），
> 同一订单聚合的后续事件全部阻塞，云同步表现为「待发送积压 + 死信」。

## 1. 云端已实施的兼容（本次变更）

云端已改为**宽容接收**，收银端不做任何改动即可恢复同步：

| 位置 | 变更 |
|---|---|
| `KdsReplicationService` 载荷校验 | `dish_availability[].stock` 允许 `-1`；`< -1` 仍拒绝（4000） |
| `KdsReplicationService` 快照应用 | 同上，`-1` 透传到门店库存快照 |
| `KdsDishAvailabilityService.applySnapshot` | `-1` → `sold_out=0`（不限量不可能售罄）且 `stock_enabled=0`（不启用库存扣减跟踪）；`0` → 售罄；`>0` → 可售 |
| `docs/openapi.yaml` | `stock: { type: integer, minimum: -1, nullable: true }` |

云端部署后，收银端在「死信审计」中对积压事件点**立即重试**即可消化历史死信，无需改代码。

## 1.5 补丁式 kds_state_changed（patches 格式）兼容

收银端新版事件驱动同步发送的 `kds_state_changed` 使用补丁式载荷
（`patches[]` + `command_id` + `event_seq` + `queue_counts` + `actor_device_code`，无 `orders/lines/dish_availability/device_code`），
旧版云端会因找不到 `order_id` 返回 4000 死信。云端已兼容：

- **识别规则**：payload 含 `patches` 且无 `lines` 数组时按补丁格式处理；
- **聚合归属**：订单号取自 `patches[0].order_id`，所有补丁行的 `order_id/order_revision` 必须一致；
- **行校验**：补丁行字段与 `KdsV2LinePatch` 对齐（数量单调性、退量 ≤ 行量、fulfillment_bucket、标志位等校验与旧版一致）；
- **部分集合**：补丁只含变更行，云端不再要求完整覆盖订单全部明细，并按需逐行建立正式 ID 映射；订单/明细尚未创建时事件挂起（pending），等待 `order_created` 到达后自动收敛；
- **鉴权**：补丁格式无 `payload.device_code`，发布者身份仅校验 `X-Cashier-Device-Code` 请求头；`command_id` 作为操作幂等键（等价旧版 `operation_id`）；
- **退菜库存**：`refund_item` 补丁仍按 `refunded_quantity` 累计差值回退库存，与旧版语义一致。

收银端无需任何改动；契约见 `docs/openapi.yaml` 的 `KdsReplicationStateChangedPatchPayload`。

## 1.6 按《KDS 复制上行协同对接文档》（2026-08-19 事故复盘）落实的云端契约

KDS 三端权威边界现统一以 `admin_panel_flutter/docs/KDS_CLOUD_AUTHORITY_PROXY_ARCHITECTURE.md` 为准；库存哨兵只保留迁移期兼容职责：

- **§4.1【已落实】** 补丁模式下 `aggregate_key`/`payload.order_id` 为云端已存在的正式订单 id 时直接受理（按 `t_order` 存在性判定并自动建立映射）；`4090` 仅保留给「本地出生订单的 `order_created` 未到达」场景。
- **§4.2【已落实】** 已知正式订单下携带 `local_detail_id` 的未映射行：按快照语义创建云端正式明细（价格取门店覆盖价兜底总部价；已退/已移除行直接物化为 refunded 终态，且**不做库存回退**——云端从未为其扣减），建立 `local_detail_id ↔ cloud_detail_id` 映射（幂等，重复事件复用既有映射），ACK `data.detail_mappings` 返回全量映射对供收银端回写。
- **§4.4【已落实】** `4090` 响应 `data` 附带 `missing_aggregate` 与 `reason`。
- **§4.3** 维持现状（按 shop_id+aggregate_key 独立计数，batch 内跨 aggregate 不互相阻塞）。
- **§6 遗留**：事故期间旧版收银端发出的「本地 id 作为正式 id」事件（如 `order:59`，云端不存在该订单）无法自动归一化，需在死信审计页人工丢弃或替换。

## 2. 收银端建议整改（不紧急，但应排期）

内部哨兵值不应外发。建议收银端在上报 `dish_availability` 时按下表转换：

| 本地状态 | 建议上报 | 云端也接受（兼容） |
|---|---|---|
| 不限量（stock = -1） | **省略 `stock` 字段或置 `null`** | `-1` |
| 有限库存（stock ≥ 0） | 原样上报 | 原样 |
| 已售罄 | `sold_out: true`（stock 可省略） | 同左 |

注意语义差异：上报 `stock: null`（或省略）时云端**保持现有库存值不变**，仅更新 `sold_out`；
上报 `-1` 会把云端库存**重置为不限量**。如果本意只是标记售罄/恢复可售，不要误发 `-1`。

## 3. 发布顺序

1. **先发布云端**（本次变更），死信即可重试消化；
2. 收银端整改可在任意后续版本进行，无耦合窗口期；
3. 若云端先收到旧版收银端的 `-1`，行为：库存置为不限量、清除售罄标记、停止该菜的库存扣减跟踪——与本地语义一致。

## 4. 验证清单

- [ ] 云端部署后，收银端「死信审计」对 `stock must be a non-negative integer` 死信执行「立即重试」，结果应为成功；
- [ ] 不限量菜品在云端 `t_dish_shop` 中 `stock=-1`、`stock_enabled=0`、`sold_out=0`；
- [ ] 有限库存菜品售罄/退菜回库的云同步不受影响（stock=0 → sold_out=1；退菜回补 → sold_out=0）。
