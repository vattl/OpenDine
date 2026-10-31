# KDS 工作流统一看板重构方案

> 目标：将当前“按屏型分页面”的 KDS，重构为“登录选择工作流程，多流程统一看板”的模式。

## 1. 目标业务模型

### 1.1 登录选择工作流程

登录页不再只选择单一屏型，而是选择当前工作区负责的流程，支持多选：


| 流程  | 说明                   | 典型工作区 |
| --- | -------------------- | ----- |
| 配菜  | 小程序下单后进入待配菜，点击后进入待制作 | 后厨配菜区 |
| 制作  | 师傅制作，点击后进入待传菜        | 后厨制作区 |
| 传菜  | 服务员传菜，可输入传菜数量        | 前厅传菜区 |


示例：

- 后厨只选「制作」：首页只显示「待制作 / 已完成」
- 前厅只选「传菜」：首页只显示「待传菜 / 已完成」
- 管理/总览可多选「配菜 + 制作 + 传菜」：显示完整流程

### 1.2 统一首页 UI

登录后统一进入现有出餐屏样式的 `BoardPage`：

- 顶部 Tab 根据登录时选择的流程动态显示
- 支持菜品维度 / 订单维度切换
- 支持搜索、筛选、排序
- 支持 WebSocket 实时刷新

### 1.3 目标状态流转

```mermaid
flowchart LR
  A[客户小程序下单] --> B[待配菜]
  B -->|点击菜品/整单配菜| C[待制作]
  C -->|点击菜品/整单制作| D[待传菜]
  D -->|输入传菜数量| E[已完成]
```



## 2. 当前系统现状

当前 Flutter 工程是按屏型分页面：


| 当前屏型     | 页面           | 接口                                              |
| -------- | ------------ | ----------------------------------------------- |
| 抓串屏      | `SkewerPage` | `/kds/skewer/summary`、`/kds/skewer/picked`      |
| 荤/素/海鲜烤屏 | `GrillPage`  | `/kds/grill/board`、`/kds/item/status`           |
| 出餐屏      | `BoardPage`  | `/kds/expedition/board`、`/kds/expedition/serve` |
| 收银总览屏    | `BoardPage`  | `/kds/overview/board`                           |


当前 OpenAPI 的核心状态：


| 字段                  | 含义      |
| ------------------- | ------- |
| `item_status=0`     | 待制作     |
| `item_status=1`     | 制作中     |
| `item_status=2`     | 已完成/待出餐 |
| `archived=1`        | 已传菜归档   |
| `skewer_picked=0/1` | 抓串闸门    |


当前缺口：

- 没有统一的「待配菜」状态字段
- 没有统一的「流程多选」登录/设备能力字段
- 没有统一推进接口，如 `POST /kds/workflow/advance`
- 订单维度还缺少完整的分轮次展示、整单推进、已传菜灰色横线等 UI

## 3. 推荐后端契约调整

### 3.1 新增流程枚举

建议新增 KDS 工作流枚举：

```yaml
KdsWorkflow:
  type: string
  enum:
    - prep       # 配菜
    - cook       # 制作
    - serve      # 传菜
```

### 3.2 新增统一队列枚举

建议新增统一看板队列：

```yaml
KdsBoardQueue:
  type: string
  enum:
    - pending_prep     # 待配菜
    - pending_cook     # 待制作
    - ready_serve      # 待传菜
    - done             # 已完成
```

如果要保留「制作中」，也可以扩展：

```yaml
    - cooking
```

但用户当前描述是“一点进入下一个环节”，不强调制作中停留，因此第一版可以只保留待制作。

### 3.3 登录接口扩展

当前：

```json
{
  "shop_id": 1,
  "device_code": "KDS-EXP-01",
  "screen_tag": "expedition"
}
```

建议扩展：

```json
{
  "shop_id": 1,
  "device_code": "KDS-WORK-01",
  "screen_tag": "workflow_board",
  "workflows": ["prep", "cook", "serve"]
}
```

响应设备信息也需要返回：

```json
{
  "device": {
    "id": 1,
    "shop_id": 1,
    "screen_tag": "workflow_board",
    "workflows": ["prep", "cook", "serve"],
    "device_token": "..."
  }
}
```

### 3.4 新增统一看板接口

建议新增：

```http
GET /kds/workflow/board
```

查询参数：


| 参数        | 示例                                            | 说明          |
| --------- | --------------------------------------------- | ----------- |
| `queue`   | `pending_cook`                                | 当前 Tab      |
| `view`    | `dish` / `order`                              | 菜品维度 / 订单维度 |
| `dining`  | `all` / `dine_in` / `pack` / `takeout`        | 就餐过滤        |
| `extra`   | `overdue,rush,add_dish,hold`                  | 状态筛选        |
| `keyword` | `鸡翅`                                          | 菜名/桌号/流水号搜索 |
| `sort`    | `order_time` / `overdue_first` / `rush_first` | 排序          |


响应建议：

```json
{
  "queue": "pending_cook",
  "view": "dish",
  "summary": {
    "dish_quantity": 88,
    "order_count": 12,
    "rush_count": 3,
    "overdue_count": 5,
    "add_dish_count": 2,
    "hold_count": 1,
    "pending_prep_count": 8,
    "pending_cook_count": 24,
    "ready_serve_count": 16,
    "pack_count": 3,
    "takeout_count": 2
  },
  "queue_counts": {
    "pending_prep": 8,
    "pending_cook": 24,
    "ready_serve": 16,
    "done": 77
  },
  "extra_counts": {
    "overdue": 5,
    "rush": 3,
    "add_dish": 2,
    "hold": 1
  },
  "dining_counts": {
    "pack": 3,
    "takeout": 2
  },
  "dish_groups": [],
  "order_cards": []
}
```

### 3.5 新增统一推进接口

单品推进：

```http
POST /kds/workflow/advance
```

```json
{
  "detail_id": 123,
  "from_queue": "pending_cook",
  "quantity": 1
}
```

整单推进：

```http
POST /kds/workflow/advance-order
```

```json
{
  "order_id": 456,
  "from_queue": "pending_cook"
}
```

传菜需要支持数量：

```json
{
  "detail_id": 123,
  "from_queue": "ready_serve",
  "quantity": 2
}
```

### 3.6 数据字段建议

订单维度需要以下字段：


| 字段                           | 说明                |
| ---------------------------- | ----------------- |
| `order_id`                   | 订单 ID             |
| `order_no`                   | 流水号，支持搜索          |
| `table_number`               | 桌号，支持搜索           |
| `order_round`                | 下单轮次，显示 `#1`、`#2` |
| `items[].workflow_queue`     | 当前流程队列            |
| `items[].served_quantity`    | 已传数量              |
| `items[].remaining_quantity` | 未传数量              |
| `items[].rush_flag`          | 催                 |
| `items[].overdue_flag`       | 超                 |
| `items[].add_dish_flag`      | 加                 |
| `items[].hold_flag`          | 等                 |
| `items[].combo_flag`         | 套                 |
| `items[].dineInOrTakeOut`    | 外/打               |


## 4. 前端重构方案

### 4.1 核心抽象改造

新增：

```dart
enum KdsWorkflow { prep, cook, serve }

enum WorkflowQueue {
  pendingPrep,
  pendingCook,
  readyServe,
  done,
}
```

映射关系：


| 登录流程 | 首页 Tab              |
| ---- | ------------------- |
| 配菜   | 待配菜 / 已完成           |
| 制作   | 待制作 / 已完成           |
| 传菜   | 待传菜 / 已完成           |
| 多选   | 对应流程 Tab 合并显示 + 已完成 |


### 4.2 登录页

将单选屏型改为：

- 工作区类型 / 设备码保留
- 流程多选：配菜、制作、传菜
- 可选兼容字段：仍传 `screen_tag=workflow_board`

本地 session 需保存 `workflows`。

### 4.3 路由

所有新流程设备统一进入：

```dart
HomeGate -> BoardPage
```

旧的 `GrillPage` / `SkewerPage` 可作为兼容模式保留，待后端稳定后逐步删除。

### 4.4 BoardShell

`BoardShell` 顶部 Tab 不再遍历 `BoardQueue.values`，改为传入：

```dart
final List<WorkflowQueue> visibleQueues;
```

并展示小红点：

```dart
KdsMainTab(
  label: queue.label,
  badge: counts[queue],
)
```

筛选条也增加小红点：

- 超时
- 催菜
- 加菜
- 等叫
- 打包
- 外卖

### 4.5 菜品维度

继续沿用现有 `KdsDishCard`，优化标签：


| 标签  | 文案  | 颜色  |
| --- | --- | --- |
| 催菜  | 催   | 红色  |
| 超时  | 超   | 红色  |
| 加菜  | 加   | 蓝色  |
| 套餐  | 套   | 黄色  |
| 外卖  | 外   | 绿色  |
| 打包  | 打   | 墨绿色 |
| 等叫  | 等   | 紫色  |


卡片头部颜色优先级建议：

1. 超时 / 催菜：红色
2. 等叫：紫色
3. 加菜：蓝色
4. 套餐：黄色
5. 外卖：绿色
6. 打包：墨绿色
7. 普通：堂食默认色

### 4.6 订单维度

重写 `BoardOrderCard`：

- 订单头部显示：桌号 / 流水号 / 下单时间 / 总数量 / 状态标签
- 按 `order_round` 分组显示 `#1`、`#2`
- 未传菜 / 未完成的菜品显示在上方
- 已传菜的菜品显示在下方，灰色 + 删除线
- 每个菜品行显示状态标签：催/超/加/等/套/外/打
- 底部提供整单操作按钮：
  - 整单配菜
  - 整单制作
  - 整单传菜

### 4.7 点击推进逻辑


| 当前 Tab | 菜品点击行为       |
| ------ | ------------ |
| 待配菜    | 直接推进到待制作     |
| 待制作    | 直接推进到待传菜     |
| 待传菜    | 弹数量键盘，提交传菜数量 |
| 已完成    | 只读           |


订单维度整单按钮同理。

### 4.8 搜索

搜索关键词支持：

- 菜品名：`name`
- 桌号：`table_number`
- 流水号：`order_no`

建议搜索下沉到后端 `keyword` 参数，前端保留本地兜底过滤。

## 5. 分阶段实施计划

### Phase 1：前端工作流抽象与登录多选

- 新增 `KdsWorkflow`、`WorkflowQueue`
- 登录页改多选流程
- Session 保存 workflows
- `BoardShell` 支持动态 Tab
- 首页统一进入 `BoardPage`

> 需要后端登录接口支持 `workflows`，或前端先本地保存作临时方案。

### Phase 2：统一看板接口对接

- 新增 `KdsApi.fetchWorkflowBoard`
- `BoardController` 改用 workflow board
- `BoardMapper` 支持新的 `summary/counts`
- Tab / 筛选 / 就餐 / 视图徽标展示

### Phase 3：统一推进动作

- 新增 `KdsApi.advanceWorkflowItem`
- 新增 `KdsApi.advanceWorkflowOrder`
- 菜品点击按 Tab 推进
- 待传菜保留数量键盘
- 整单按钮接入

### Phase 4：订单维度重构

- 重写 `BoardOrderCardData`
- 重写 `BoardOrderCard`
- 支持轮次 `#1/#2`
- 已传菜灰色删除线
- 订单内菜品状态标签

### Phase 5：标签、排序、搜索、统计完善

- 标签颜色和头部颜色优先级
- 按下单时间 / 超时优先 / 催菜优先排序
- 搜索菜品 / 桌号 / 流水号
- 所有红点统计联调

### Phase 6：兼容清理

- 保留旧六屏路由一段时间
- 后端验证稳定后移除/隐藏旧 `GrillPage`、`SkewerPage`
- 更新联调文档和模拟器脚本

## 6. 当前无法仅靠前端完成的点

以下需求必须后端配合，否则前端只能模拟 UI，无法保证真实业务流转：

1. 「待配菜」状态字段
2. 统一看板接口 `/kds/workflow/board`
3. 单品推进接口 `/kds/workflow/advance`
4. 整单推进接口 `/kds/workflow/advance-order`
5. 登录接口保存/返回 `workflows`
6. 队列/标签/就餐/订单维度红点统计
7. 订单轮次 `order_round`
8. 已传菜与未传菜在订单维度下的结构化数据

## 7. 建议后端兼容策略

为了不一次性推翻现有 KDS，建议后端先兼容映射：


| 新流程 | 旧字段暂时映射                             |
| --- | ----------------------------------- |
| 待配菜 | `skewer_picked=0`                   |
| 待制作 | `item_status=0` 且 `skewer_picked=1` |
| 待传菜 | `item_status=2` 且 `archived=0`      |
| 已完成 | `archived=1`                        |


但长期建议新增明确的 `workflow_queue` / `workflow_status`，否则“配菜”和“抓串”会语义混淆。

## 8. 验收用例

1. 登录选择「制作」：首页只显示「待制作 / 已完成」
2. 登录选择「传菜」：首页只显示「待传菜 / 已完成」
3. 登录选择「配菜 + 制作 + 传菜」：首页显示「待配菜 / 待制作 / 待传菜 / 已完成」
4. 菜品维度：相同菜品合并展示
5. 订单维度：按订单展示所有菜品，未完成在上，已完成灰色删除线在下
6. 点击待配菜菜品：进入待制作
7. 点击待制作菜品：进入待传菜
8. 点击待传菜菜品：输入数量后进入已完成
9. 订单维度整单操作可推进全部可推进菜品
10. 催/超/加/等/套/外/打标签显示正确
11. 各 Tab、筛选、就餐方式红点数量正确
12. 搜索可按菜名、桌号、流水号命中
13. 多设备登录不同流程，WebSocket 后状态同步

