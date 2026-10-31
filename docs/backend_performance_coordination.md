# KDS 厨显端性能优化 — 后端配合说明

> **面向**：后端开发 / 后端 AI 改造  
> **对应前端工程**：`kds_app/`（Flutter 厨显 Android）  
> **文档版本**：2026-06-08  
> **关联前端进度**：`docs/kds_performance_progress.md`

---

## 1. 背景与目标

前端已完成看板性能优化（缓存、局部更新、WS 防抖、isolate 解析、虚拟列表等）。**多数能力不依赖后端改动即可生效**，但若后端按本文约定补齐字段与事件，可达到：

| 指标 | 优化前（典型） | 目标 |
|------|----------------|------|
| 单次看板 HTTP | 4–6 次 | **≤ 1 次**（多数场景） |
| Tab 角标 | 每 Tab 单独 count（N+1） | **主响应 `queue_counts` 一次给出** |
| 催/等/超等标志变更 | 全量刷新看板 | **WS 局部 patch，跳过 load** |
| 大 JSON 解析 | 主线程卡顿 | 前端 isolate（后端减小 payload 仍最有效） |

---

## 2. 改造优先级（给 AI 的执行顺序）

### P0 — 必须做（否则 Tab 角标可能不准或仍有多次 HTTP）

1. `GET /kds/workflow/board` 响应中 **始终返回 `queue_counts`**，且覆盖设备可见的全部非「已完成」队列。
2. 确保 **`/kds/workflow/board` 已部署且权限正确**（勿长期 404/403 导致前端降级 overview）。
3. **`view=dish` 响应携带 `order_cards`**（至少备注字段），或 **`dish_groups` 带完整 `lines`**，避免前端为备注/重建再请求一次。

### P1 — 强烈建议（消灭隐形第 2、3 次 board 请求）

4. `view=order` 时响应携带完整 **`order_cards`**；若为空则保证 **`dish_groups` 可聚合为整单**。
5. WebSocket：标志类变更发 **`dish_flags_changed`**（带 `detail_id`），与催菜/等叫等操作一致。
6. 操作 API 成功后，**DB 状态与 WS 推送一致**，避免乐观更新后被旧数据覆盖。

### P2 — 可选（进一步减请求 / 减体积）

7. 在 `workflow/board` 响应中 **合并 `stats`**（同 `/kds/stats/today`），省一条 stats 请求。
8. 高峰单量时 **裁剪字段 / 分页**（前端已有虚拟列表与 isolate，但小 payload 更优）。

---

## 3. 核心接口：`GET /kds/workflow/board`

### 3.1 请求参数（前端实际传参）

| 参数 | 说明 | 示例 |
|------|------|------|
| `queue` | 当前队列 | `pending_prep` / `pending_cook` / `ready_serve` / `done` |
| `dining` | 堂食筛选 | 与 OpenAPI `BoardDining` 一致 |
| `view` | 视图 | `dish`（菜品卡）或 `order`（整单卡） |
| `sort` | 排序 | 前端 `BoardSortMode.apiValue` |
| `merge_rules` | 合并规则 | 可选 |
| `split_pack_takeout` | 拆打包外卖 | `1` 时拆分 |
| `extra` | 附加筛选 | 逗号分隔，如催菜等 |
| `keyword` | 搜索关键词 | workflow 看板服务端过滤；非 workflow 前端本地过滤 |

### 3.2 响应必须字段（workflow 模式）

```json
{
  "screen_tag": "workflow_board",
  "queue_counts": {
    "pending_prep": 12,
    "pending_cook": 45,
    "ready_serve": 8
  },
  "visible_queues": [
    "pending_prep",
    "pending_cook",
    "ready_serve",
    "done"
  ],
  "summary": {
    "ticket_count": 0,
    "order_count": 0,
    "dish_quantity": 0,
    "rush_count": 0,
    "overdue_count": 0,
    "add_dish_count": 0,
    "hold_count": 0,
    "pending_prep_count": 0,
    "pending_cook_count": 0,
    "ready_serve_count": 0,
    "done_count": 0,
    "dine_in_count": 0,
    "pack_count": 0,
    "takeout_count": 0
  },
  "dining_counts": {
    "dine_in": 0,
    "pack": 0,
    "takeout": 0
  },
  "workflows": ["prep", "cook", "serve"],
  "kds_mode": "kds_only",
  "skewer_gate": 0,
  "merge_rules": [],
  "dish_groups": [],
  "order_cards": []
}
```

### 3.3 `queue_counts` 规则（P0 重点）

**用途**：前端用其填充 **非当前 Tab** 的角标数字，从而去掉「每个 Tab 单独 count」的 N+1 请求。

| 键名（必须） | 队列含义 |
|--------------|----------|
| `pending_prep` | 待配菜 |
| `pending_cook` | 待制作 |
| `ready_serve` | 待传菜 |
| `done` | 已完成（角标通常不展示，可省略） |

**计数口径**：

- 与当前请求的 `dining`、`extra`、设备 `workflows`、门店 `skewer_gate` 等筛选 **一致**。
- 数字应等于：用户切换到该 Tab 且相同筛选条件下 **可见条目总数**（不是当前页 partial）。
- **当前 Tab** 的数量前端会用列表长度覆盖 `queue_counts` 中对应项，但其它 Tab **完全依赖 `queue_counts`**。

**前端自检（无需后端工具）**：厨显 **设置 → 诊断 → queue_counts**  
- 正常：`完整覆盖 N/N Tab`  
- 异常：`后端未返回 queue_counts` 或 `部分覆盖（缺: pending_cook, ...）`

**判定 workflow 看板**：响应含 `screen_tag == "workflow_board"` **或** 存在 `queue_counts` 字段。

---

## 4. 数据结构：`dish_groups`（菜品视图）

### 4.1 为何重要

- `view=dish` 时主数据来自 `dish_groups`。
- 若 `dish_groups` **缺少 `lines` 或台号**，前端会再拉 `order_cards` 并可能 **再请求一次 board** 重建分组。

### 4.2 单组建议结构

```json
{
  "dish_name": "牛肉",
  "quantity": 2,
  "unit": "份",
  "remaining_quantity": 2,
  "spec_norm": "大份",
  "lines": [
    {
      "detail_id": 10001,
      "order_id": 500,
      "order_no": "A20250608001",
      "table_number": "8",
      "dineInOrTakeOut": "堂食",
      "dish_name": "牛肉",
      "quantity": 2,
      "line_quantity": 2,
      "remaining_quantity": 2,
      "cooked_quantity": 0,
      "prep_quantity": 0,
      "rush_flag": 0,
      "hold_flag": 0,
      "overdue_flag": 0,
      "add_dish_flag": 0,
      "combo_flag": 0,
      "pack_flag": 0,
      "takeout_flag": 0,
      "remark": "",
      "spec_norm": "大份",
      "selectedSpicy": null,
      "fifo_seq": 1,
      "first_order_time": "2026-06-08T12:00:00+08:00"
    }
  ]
}
```

**标志位**：支持 `0/1`、`true/false`、字符串 `"1"`（前端 `parseKdsFlag` 已兼容）。

---

## 5. 数据结构：`order_cards`（整单视图 & 备注补全）

### 5.1 用途

- `view=order` 时主列表来自 `order_cards`。
- `view=dish` 时若响应 **无 `order_cards`**，前端会 **额外请求 `view=order`** 仅为了整单备注（`remark` / `order_remark` 等）。

### 5.2 单条建议结构

```json
{
  "order_id": 500,
  "order_no": "A20250608001",
  "table_number": "8",
  "dineInOrTakeOut": "堂食",
  "orderNumber": 101,
  "remark": "少辣",
  "order_time": "2026-06-08T12:00:00+08:00",
  "rush_flag": 0,
  "items": [
    {
      "detail_id": 10001,
      "dish_name": "牛肉",
      "quantity": 2,
      "remaining_quantity": 2,
      "status": 0,
      "rush_flag": 0,
      "hold_flag": 0
    }
  ]
}
```

**备注字段**（任一有值即可）：`remark`、`merchant_remark`、`order_remark`、`memo`、`note`。

### 5.3 消灭第二次 HTTP 的推荐策略（二选一或并存）

| 策略 | 说明 |
|------|------|
| A | `view=dish` 响应 **附带精简 `order_cards`**（`order_id`、`order_no`、`remark` 即可） |
| B | `dish_groups[].lines` **已含完整展示字段**，不依赖 order 视图补备注 |

---

## 6. 降级接口（非 workflow 设备）

### 6.1 `GET /kds/overview/board`

- 参数 `queue` 使用 **legacy**：`pending`（待配菜/待制作）、`ready_serve`、`done`。
- **可不返回 `queue_counts`**（前端诊断会显示「非 workflow 看板」）。
- 仍建议 `dish_groups` / `order_cards` 完整，减少补拉。

### 6.2 `GET /kds/expedition/board`

- 传菜专用屏；逻辑类似 overview，队列常为 `ready_serve`。

---

## 7. WebSocket 事件

### 7.1 `dish_flags_changed`（P1 — 标志局部更新）

**门店级事件**（可不绑 `screen_tag`）；前端在菜品视图尝试 patch，**成功则跳过全量 board load**。

**推荐 payload：**

```json
{
  "type": "dish_flags_changed",
  "tickets": [
    {
      "detail_id": 10001,
      "order_id": 500,
      "rush_flag": 1,
      "hold_flag": 0,
      "overdue_flag": 0,
      "add_dish_flag": 0
    }
  ]
}
```

**兼容的列表字段名**：`tickets`、`details`、`items`、`changes`（数组）；或 **扁平单条** 直接带 `detail_id` + 标志位。

**标志字段**（有变更则带上）：`rush_flag`、`hold_flag`、`overdue_flag`、`add_dish_flag`。

**何时发**：

- 催菜、等叫、起菜、改标志等 **仅影响标志位** 时 → 发 `dish_flags_changed`。
- 新单、划菜、改数量、删单等 **结构/数量变化** → 发 `new_order` / `update_order`（前端会后台全量或准全量刷新）。

### 7.2 其它常见事件（保持现有行为即可）

| 事件 | 前端行为 |
|------|----------|
| `new_order` | 后台刷新 board（已合并并发 + WS 防抖） |
| `update_order` | 同上；跨屏规则见 `kds_ws_event_filter.dart` |
| `skewer_released` | 烤台/相关屏刷新 |

### 7.3 Stats

- 前端对 WS 触发的 stats 拉取有 **45s 节流**。
- 若 board 响应合并 stats（P2），可进一步减少 `/kds/stats/today` 调用。

---

## 8. 操作 API 与乐观更新一致性

前端已对以下操作做 **先改 UI、后调 API、失败回滚**：

- 催菜、等叫、起菜、缺货、退菜、撤销等

**后端要求**：

1. 成功时返回与 WS / 下次 board 查询 **一致** 的状态。
2. 失败返回 **4xx + 可读 `message`**（前端展示并回滚）。
3. 标志类成功：**优先推 `dish_flags_changed`**，避免无必要的 `update_order` 导致全量刷新。

**相关路径（示例，以实际 OpenAPI 为准）**：

- `POST /kds/workflow/rush`
- `POST /kds/workflow/hold`
- `POST /kds/workflow/release`
- 缺货/退菜等工作流接口

---

## 9. 可选增强：P3-04 board 合并 stats

在 `GET /kds/workflow/board` 响应增加：

```json
{
  "stats": {
    "today_orders": 0,
    "today_tickets": 0,
    "badge_label": "..."
  }
}
```

结构与 `GET /kds/stats/today` 的 `stats` 对象 **一致**（前端 `KdsStatsToday.fromJson`）。

---

## 10. 验收与联调步骤

### 10.1 抓包 / 日志检查

1. 多流程设备登录，切换 Tab，确认 **每次切换最多 1 次** `workflow/board`（缓存 30s 内可能 0 次）。
2. 首次进入看板，确认 **无连续 2 次** 相同 `queue` 的 board 请求（备注补拉、groups 重建）。
3. `workflow/board` 响应 JSON 根级含 **`queue_counts`**，且键覆盖 `visible_queues` 中除 `done` 外的 Tab。

### 10.2 厨显端诊断页（设置 → 诊断）

| 项 | 期望 |
|----|------|
| queue_counts | `完整覆盖 x/x Tab` |
| JSON 解析 | 大高峰时 `isolate · 权重 >150` |
| 看板刷新 P50 | 多次刷新后有稳定 P50 |

### 10.3 WS 测试

1. 催菜一次 → 应收到 `dish_flags_changed` 且带 `detail_id`。
2. 菜品视图下卡片「催」标 **即时出现**，且短时间内 **无全量 board HTTP**（可与抓包对比）。

---

## 11. 前端行为摘要（供后端理解「为何这样设计」）

| 前端能力 | 依赖后端 |
|----------|----------|
| Tab 角标不 N+1 | **`queue_counts` 完整** |
| 单次 board HTTP | **一次响应含 groups + order_cards（备注）** |
| WS 不全量 load | **`dish_flags_changed` + detail_id** |
| 冷启动 / Tab 缓存 | 不依赖后端（本地 L2）；后台刷新仍靠 board API |
| isolate 大 JSON 解析 | 不依赖后端；**减小 payload 更好** |

---

## 12. 给后端 AI 的改造任务模板（可直接复制）

```text
任务：按 docs/backend_performance_coordination.md 改造 KDS workflow board 与 WS。

P0：
1. GET /kds/workflow/board 响应增加 queue_counts，键：pending_prep, pending_cook, ready_serve（计数与 dining/extra/workflows 筛选一致）。
2. 确保接口可访问（非 404/403）。
3. view=dish 时响应包含 order_cards（至少 order_id, order_no, remark）或 dish_groups 每条带完整 lines。

P1：
4. view=order 时 order_cards 非空；标志变更发 dish_flags_changed（含 detail_id）。
5. 操作 API 与 WS、board 查询数据一致。

P2（可选）：
6. board 响应合并 stats 对象。
7. 评估高峰 payload 体积与分页。

验收：queue_counts 完整覆盖；view=dish 无第二次 board 请求；催菜后 dish_flags_changed 可局部更新。
```

---

## 13. 参考：前端源码索引

| 主题 | 路径 |
|------|------|
| board 加载与 queue_counts | `kds_app/lib/features/board/board_provider.dart` |
| queue_counts 覆盖率自检 | `kds_app/lib/features/board/board_queue_counts_coverage.dart` |
| WS 标志 patch | `kds_app/lib/features/board/board_ws_flag_patch.dart` |
| API 定义 | `kds_app/lib/core/api/kds_api.dart` |
| WS 过滤 | `kds_app/lib/core/ws/kds_ws_event_filter.dart` |
| 队列枚举 | `kds_app/lib/core/config/kds_screen_tag.dart`（`BoardQueue`） |

---

*文档维护：前端性能优化迭代时同步更新本文 P0/P1 验收项。*
