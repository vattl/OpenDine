# KDS 工作流程与回归矩阵（P3 验收）

> **契约**：`server/docs/openapi.yaml`（**KDS-Client** / **KDS-Admin**）  
> **统一看板方案**：`kds_workflow_refactor_plan.md`  
> **代码入口**：`com.lanf.kds.KdsWorkflowQueue`、`com.lanf.kds.KdsWorkflow`、`com.lanf.kds.service.KdsWorkflowService`

---

## 1. 门店模式（`t_kds_shop_config.kds_mode`）


| 模式               | 堂食下单                | 飞鹅打印                                 | 厨显工单 / WS                  |
| ---------------- | ------------------- | ------------------------------------ | -------------------------- |
| `print_only`（默认） | 仅飞鹅厨房/前台小票          | ✅ `KdsConfigService.shouldFeiePrint` | ❌ `KdsOrderHook` 直接 return |
| `kds_only`       | 五屏 REST + `/ws/kds` | ❌ 不打飞鹅                               | ✅ 全链路                      |
| `both`           | 打印 + 厨显             | ✅                                    | ✅                          |


**启用步骤**（新店）：

```text
POST /admin/kds/station/init-five
  → POST /admin/kds/dish-screen/bind
  → POST /admin/kds/config/save（kds_mode=kds_only 或 both）
  → POST /kds/device/login（screen_tag=workflow_board 或六屏之一）
  → 厨显请求带 X-Kds-Device-Token 调 /kds/*
```

---

## 2. 统一工作流（推荐路径）

登录选择 `**workflows**`（可多选）：`prep` 配菜、`cook` 制作、`serve` 传菜。  
设备 `**screen_tag=workflow_board**` 时走 `**/kds/workflow/***`；旧六屏接口仍兼容。

### 2.1 状态流转

```mermaid
flowchart LR
  A[小程序下单] --> B[待配菜 pending_prep]
  B -->|advance| C[待制作 pending_cook]
  C -->|advance| D[待传菜 ready_serve]
  D -->|advance 数量| E[已完成 done]
```



### 2.2 队列与库表字段映射（第一版）


| 队列 `queue`     | 业务含义   | `t_kds_ticket` 条件                                  | 备注                                           |
| -------------- | ------ | -------------------------------------------------- | -------------------------------------------- |
| `pending_prep` | 待配菜/抓串 | `item_status=0` 且 `skewer_picked=0` 且 `archived=0` | 需 `skewer_gate=1`；否则创单时 `skewer_picked=1` 跳过 |
| `pending_cook` | 待制作    | `item_status=0` 且 `skewer_picked=1` 且 `archived=0` | 点击推进时内部 `0→1→2` 桥接                           |
| `ready_serve`  | 待传菜    | `item_status=2` 且 `archived=0`                     | 支持分批 `served_quantity`                       |
| `done`         | 已完成    | `archived=1`                                       | 活跃列表不展示；默认 2h 由 `KdsArchiveJob` 归档           |


实现类：`KdsWorkflowQueue.applyTicketFilter`。

### 2.3 统一 REST 路径


| 方法   | 路径                                 | 说明                                                                              |
| ---- | ---------------------------------- | ------------------------------------------------------------------------------- |
| POST | `/kds/device/login`                | `workflows: [prep,cook,serve]`，响应 `device.workflows`                            |
| GET  | `/kds/device/me`                   | 核对 token 与 workflows                                                            |
| GET  | `/kds/workflow/board`              | `queue` / `view` / `dining` / `extra` / `keyword` / `sort`；含 `**queue_counts**` |
| POST | `/kds/workflow/advance`            | 单品推进；传菜带 `quantity`                                                             |
| POST | `/kds/workflow/advance-order`      | 整单推进当前队列                                                                        |
| WS   | `/ws/kds?shop_id&screen_tag&token` | `new_order` / `update_order` / `cancel_item` / `cancel_order`                   |


### 2.4 设备可见 Tab


| 登录 workflows | 可见队列（含 `done`）        |
| ------------ | --------------------- |
| 仅 `prep`     | `pending_prep`、`done` |
| 仅 `cook`     | `pending_cook`、`done` |
| 仅 `serve`    | `ready_serve`、`done`  |
| 多选           | 对应队列 + `done`         |


逻辑：`KdsWorkflow.visibleQueues`；登录多选写入 `KdsDeviceService` 会话缓存。

---

## 3. 旧六屏兼容路径（仍支持回归）


| screen_tag                                     | 读                           | 写                                                                             |
| ---------------------------------------------- | --------------------------- | ----------------------------------------------------------------------------- |
| `skewer_aggregate`                             | `GET /kds/skewer/summary`   | `POST /kds/skewer/picked`                                                     |
| `meat_grill` / `veg_grill` / `seafood_special` | `GET /kds/grill/board`      | `POST /kds/grill/start-cooking`、`POST /kds/item/status`、`POST /kds/item/lack` |
| `expedition`                                   | `GET /kds/expedition/board` | `POST /kds/expedition/serve`                                                  |
| `boss_overview`                                | `GET /kds/overview/board`   | 只读                                                                            |


与统一队列映射关系见 §2.2；新前端优先 `**/kds/workflow/***`。

---

## 4. 订单侧入厨显路径（`KdsOrderHook`）


| 场景    | 触发                              | WS / 行为                  |
| ----- | ------------------------------- | ------------------------ |
| 堂食下单  | `OrderController` CREATE        | `new_order` → 抓串屏或烤制屏    |
| 加菜    | ADD_DISHES                      | `update_order`           |
| 支付成功  | `PaymentSuccessHandler` PAID    | 建工单 + 推送                 |
| 退菜    | `OrderDetailRefundService`      | `cancel_item` + VOID     |
| 取消整单  | `afterOrderCancelled`           | `cancel_order` + 批量 VOID |
| B 端补推 | `POST /admin/kds/ticket/repush` | MANUAL                   |


---

## 5. P3 回归矩阵


| 场景      | print_only | kds_only                                                    | both    |
| ------- | ---------- | ----------------------------------------------------------- | ------- |
| 堂食下单    | 仅飞鹅打印，无工单  | 五屏 WS + REST 工单                                             | 打印 + 厨显 |
| 加菜      | 原逻辑        | `update_order`                                              | 二者      |
| 抓串聚合    | —          | `GET /kds/skewer/summary` 或 workflow `pending_prep`         | —       |
| 缺货 lack | —          | 工单 void + 可选 sold_out（`POST /kds/item/lack`）                | —       |
| 退菜      | —          | `cancel_item`                                               | —       |
| 取消整单    | —          | `cancel_order` WS + 工单 void                                 | —       |
| 2h 归档   | —          | 已完成工单不出现在活跃列表（`archived=1`）                                 | —       |
| 设备鉴权    | —          | 无 token → 401；`/kds/device/login`、`heartbeat` 放行            | —       |
| 统一看板    | —          | `GET /kds/workflow/board` 返回 `queue_counts`；`advance` 按队列推进 | —       |


---

## 6. 联调检查清单

1. `config.save` 后 `kds_mode` 与预期一致；`print_only` 时 `t_kds_ticket` 无新行。
2. `skewer_gate=1`：`pending_prep` 有数据；`picked` / `advance` 后进入 `pending_cook`。
3. `skewer_gate=0`：创单即 `skewer_picked=1`，跳过配菜 Tab。
4. `advance` 从 `ready_serve` 带 `quantity`，部分传菜后仍留在 `ready_serve`，满量进 `done`。
5. 登录 `workflows: [cook]` 访问 `pending_prep` → **403**；`queue_counts` 仅统计烤制岗 ticket。
6. 归档任务运行后，`done` 仍可查，`pending_`* / `ready_serve` 列表不含已归档行。
7. 多设备不同 `device_code`，token 不互踢（同码同屏重复 login 保留 token）。

---

## 7. 小程序下单不推送到 KDS（排查）

WebSocket 已 **ONLINE** 只说明厨显连上了桶 `shop_id:screen_tag`；**推不到屏**通常是下面某一环断了。

### 7.1 推送链路

```text
POST /order/create（或外卖 /order/takeout/create）
  → KdsOrderHook.afterOrderCommitted(CREATE)
  → t_kds_shop_config.kds_mode 为 kds_only / both？
  → KdsRoutingService 菜品绑屏 → 插入 t_kds_ticket
  → KdsPushService.new_order → 事务提交后 WS 广播
  → 桶 key = {shopId}:workflow_board（及 skewer_aggregate / 烤制屏等）
```

### 7.2 最常见原因（按概率）

| # | 现象 / 原因 | 怎么确认 | 处理 |
|---|-------------|----------|------|
| 1 | **`kds_mode=print_only`**（默认） | `SELECT kds_mode FROM t_kds_shop_config WHERE shop_id=1` | `POST /admin/kds/config/save` 设为 `kds_only` 或 `both` |
| 2 | **未绑菜品到烤制屏** → 无工单 | 下单后 `SELECT * FROM t_kds_ticket ORDER BY id DESC LIMIT 5` 为空 | `POST /admin/kds/dish-screen/bind` + `init-five` |
| 3 | **订单门店 ≠ KDS 订阅门店** | 订单 `shop_id` 与 WS `shop_id=1` 不一致 | 小程序 `X-Shop-Id` / body `shop_id` 与厨显登录店一致 |
| 4 | **多机部署 WS 内存桶** | 日志有 `[kds] ws new_order ... subscribers=0` 但客户端明明在线 | 订单 HTTP 与 WS 打到不同实例；需粘性会话或集中推送 |
| 5 | **只有工单、没有 WS 订阅** | 日志 `[kds] 订单无可用工单，跳过 WS 推送` | 查路由：套餐子行、未上架、档口 disabled |
| 6 | **客户端未刷新** | 服务端 `subscribers=1` | 监听 `type=new_order` 且 `screen_tag=workflow_board`；收到后拉 `GET /kds/workflow/board` |

### 7.3 服务端日志关键字

下单后 grep：

- `[kds] skip hook: ... kds_mode=print_only` → 未开厨显  
- `[kds] hook shop_id=...` → 已进入建单  
- `[kds] 订单无可用工单，跳过 WS 推送` → 绑屏/路由问题  
- `[kds] ws new_order shop=1 screen=workflow_board subscribers=1` → 推送成功  
- `[kds] ws new_order ... (no subscriber)` → 该实例上无 WS 连接  

### 7.4 订单类型说明

| 类型 | KDS 触发时机 |
|------|----------------|
| 堂食首单 | 创建订单时 **CREATE**（未支付也会进厨显） |
| 堂食加菜 | **ADD_DISHES** |
| 外卖/打包 | 创建时 **CREATE**；支付成功且自动接单时再 **PAID**（幂等，工单已存在则只补推） |

---

## 8. 相关文档

- `kds_admin_setup_guide.md` — 运营配置  
- `kds_frontend_development_tasks.md` — 厨显前端任务  
- `kds_workflow_refactor_plan.md` — 前端 BoardPage 重构细则  
- `postman-kds.json` — 接口集合（若有）

