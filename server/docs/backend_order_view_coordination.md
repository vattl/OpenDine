# KDS 订单维度（按单/按桌）— 后端配合说明

> **面向**：后端开发 / 后端 AI 改造  
> **对应前端工程**：`kds_app/`（Flutter 厨显 Android）  
> **文档版本**：2026-06-08  
> **关联 OpenAPI**：`docs/openapi.yaml`（`KdsWorkflowLine.done_line`、`KdsOverviewLine` 数量字段）  
> **关联性能联调**：`docs/backend_performance_coordination.md`

---

## 1. 背景与产品诉求

前端已实现 **订单维度看板**（`view=order`）：一桌/一单一张卡片，列出该单全部菜品；**未划菜在上方可点击**，**本队列已划菜在下方带删除线**。

当前联调问题：

1. **整单其它菜不全**：`order_cards.items` 只返回当前队列仍可操作的明细，同单其它菜缺失。
2. **划菜后消失**：`POST /kds/workflow/advance-item` 成功后，下一次 `GET /kds/workflow/board` 或 WS 触发的刷新 **不再返回已划明细**（缺 `done_line` / 已推进份数字段），前端被迫用合并兜底，体验仍不稳定。

**目标**：后端一次返回「整单全量明细 + 本队列已划/未划状态」，前端无需二次猜测或长期依赖本地合并。

---

## 2. 改造优先级

### P0 — 必须（否则订单维度不可用）

1. `view=order` 时，`order_cards[].items[]` 包含 **该订单在当前 Tab 队列下的全部明细行**（含已划与未划），按 `detail_id` 唯一。
2. 每条 `KdsWorkflowLine` / `KdsOverviewLine` 带 **完整数量三元组**（见 §4），且 `done_line` 与数量一致。
3. `advance-item` / `advance-order` 成功后，**下一次 board 查询与 WS 推送** 的数据与 DB 一致（已划行仍出现在 `items` 中，且 `done_line=1` 或已推进份数增加）。

### P1 — 强烈建议

1. `view=dish` 时附带精简 `order_cards`（备注）+ `dish_groups.lines` 带 `order_id`/`detail_id`，便于前端合并补全。
2. 推进成功后发 WS（`board_changed` 或细粒度事件），且 board 响应中已划行字段已更新。
3. `order_cards` 支持 `rounds[]` 分组（`order_round` / `label`），与 OpenAPI `KdsWorkflowOrderRound` 一致。

### P2 — 可选

1. `order_cards` 级 `served_quantity` / `remaining_quantity` 与行级汇总一致（待传菜 Tab）。
2. 高峰时控制 `order_cards` 体积（按可见订单裁剪，但 **单内 items 仍须完整**）。

---

## 3. 核心接口

### 3.1 `GET /kds/workflow/board`


| 参数                             | 订单维度要求                                                                   |
| ------------------------------ | ------------------------------------------------------------------------ |
| `view`                         | **必须为 `order`**（前端按单视图时传此值）                                              |
| `queue`                        | `pending_prep` / `pending_cook` / `ready_serve`                          |
| `dining` / `extra` / `keyword` | 与现有筛选一致；**order_cards 内 items 仍须为该单全量菜**（筛选作用于「订单是否出现在列表」，而非「订单内只返回部分菜」） |


**响应**：在 workflow 标准字段基础上，`order_cards` 非空（当前队列有单的场景）。

### 3.2 `POST /kds/workflow/advance-item`


| 字段           | 说明                  |
| ------------ | ------------------- |
| `detail_id`  | `t_order_detail.id` |
| `from_queue` | 当前队列                |
| `quantity`   | 本步推进份数（支持部分推进）      |


**成功后**：对应明细的 `prep_quantity` / `cooked_quantity` / `served_quantity` 增加，`prep_remaining` / `cook_remaining` / `remaining_quantity` 减少；若本队列下该行已全部推进，则 `done_line=1`。

### 3.3 `POST /kds/workflow/advance-order`

整单推进：同单所有 **当前队列仍可操作** 的明细推进；**order_cards 仍返回全量 items**（已划行 `done_line=1`）。

---

## 4. `order_cards[].items[]` 字段契约（P0 重点）

每条明细对齐 OpenAPI：`KdsWorkflowLine` = `KdsOverviewLine` + `done_line` / `action_label` / `next_queue`。

### 4.1 必填（订单维度展示）


| 字段                      | 类型      | 说明                                           |
| ----------------------- | ------- | -------------------------------------------- |
| `detail_id`             | int     | 划菜 API 用；**唯一键**                             |
| `name`                  | string  | 菜名                                           |
| `quantity`              | int     | **当前队列展示量**（本 Tab 下仍可操作的份数；与 remaining 字段一致） |
| `line_quantity`         | int     | **明细行总份数**（下单份数，不因部分划菜而变）                    |
| `unit`                  | string  | 单位，如「串」「份」                                   |
| `order_id` / `order_no` |         | 归属订单                                         |
| `table_number`          | string? | 桌号                                           |
| `order_round`           | int     | 下单轮次（#1/#2 分组）                               |
| `done_line`             | 0/1     | **本队列视角**是否已全部划完：1=已划完，前端置底+删除线              |


### 4.2 本队列数量（按 `queue` 参数含义填充）


| 当前 `queue`     | 待推进（remaining）       | 已推进（completed）    |
| -------------- | -------------------- | ----------------- |
| `pending_prep` | `prep_remaining`     | `prep_quantity`   |
| `pending_cook` | `cook_remaining`     | `cooked_quantity` |
| `ready_serve`  | `remaining_quantity` | `served_quantity` |


**一致性规则**（验收用）：

```text
line_quantity = prep_quantity + prep_remaining        // pending_prep Tab
line_quantity = cooked_quantity + cook_remaining      // pending_cook Tab
line_quantity = served_quantity + remaining_quantity  // ready_serve Tab（同一明细行）

若本队列已全部划完：done_line=1，且对应 remaining=0，completed=line_quantity
若仍有未划：done_line=0，且 remaining>0
```

### 4.3 标签与状态（行级，非整单级）

`rush_flag` / `overdue_flag` / `add_dish_flag` / `hold_flag` / `pack_flag` / `takeout_flag` 打在 **items[]** 上（v1.2.123 约定），订单卡本身不要整单级催/超标。

### 4.4 可选但推荐


| 字段               | 说明                   |
| ---------------- | -------------------- |
| `action_label`   | 当前队列操作文案，如「制作完成」「传菜」 |
| `wait_seconds`   | 等待秒数                 |
| `workflow_queue` | 明细当前工作流队列            |
| `fifo_seq`       | 排序用                  |


---

## 5. 响应样例（`queue=pending_cook`, `view=order`）

订单 A1：油边 3、鸡翅 2；油边已制作 1，剩余 2 待制作；鸡翅未制作。

```json
{
  "screen_tag": "workflow_board",
  "queue": "pending_cook",
  "view": "order",
  "queue_counts": { "pending_prep": 0, "pending_cook": 1, "ready_serve": 0 },
  "order_cards": [
    {
      "order_id": 1001,
      "order_no": "O20260608001",
      "table_number": "A1",
      "remark": "不要辣",
      "items": [
        {
          "detail_id": 501,
          "name": "油边",
          "line_quantity": 3,
          "quantity": 2,
          "cook_remaining": 2,
          "cooked_quantity": 1,
          "unit": "串",
          "order_round": 1,
          "done_line": 0,
          "action_label": "制作完成",
          "wait_seconds": 320
        },
        {
          "detail_id": 502,
          "name": "鸡翅",
          "line_quantity": 2,
          "quantity": 2,
          "cook_remaining": 2,
          "cooked_quantity": 0,
          "unit": "串",
          "order_round": 1,
          "done_line": 0,
          "action_label": "制作完成",
          "wait_seconds": 180
        }
      ]
    }
  ]
}
```

油边再制作 2 份后（本队列全部完成）：

```json
{
  "detail_id": 501,
  "name": "油边",
  "line_quantity": 3,
  "quantity": 3,
  "cook_remaining": 0,
  "cooked_quantity": 3,
  "done_line": 1,
  ...
}
```

**注意**：`done_line=1` 的行 **仍须出现在 items[]**，前端显示在卡片下方（删除线），直到该订单在当前 Tab 无未划菜后整单从列表移除。

---

## 6. 三队列统一要求


| Tab | 订单卡应展示      | `done_line=1` 含义 |
| --- | ----------- | ---------------- |
| 待配菜 | 该单 **全部菜品** | 本行配菜已完成          |
| 待制作 | 该单 **全部菜品** | 本行制作已完成          |
| 待传菜 | 该单 **全部菜品** | 本行传菜已完成          |


**不要**只在 items 里返回「当前还能划的那几道菜」；未进入本队列的菜（例如仍在待配菜）若产品要求也展示，需与产品确认——最低要求：**同一订单在 items 中出现的每一行都带 `line_quantity` 与 done/remaining 字段**。

---

## 7. 与 WS / 刷新的配合（避免划菜后消失）


| 场景                      | 后端应保证                                                                  |
| ----------------------- | ---------------------------------------------------------------------- |
| `advance-item` 成功       | DB 更新后，下一次 `GET board` 该行 `cooked_quantity+1` 或 `done_line=1`，**行不删除** |
| WS `board_changed` / 刷新 | 响应与 DB 一致，**不要用「仅可操作明细」子集覆盖全量 items**                                  |
| 部分推进                    | `line_quantity` 不变；`quantity`/`cook_remaining` 减；`cooked_quantity` 增   |
| 整单最后一行划完                | 订单从当前 `queue` 列表消失（无 `isActiveLine`），但 **划菜瞬间到消失前** 仍应看到已划行在下方         |


前端已对「API 缺已划行」做 `mergeOrderCards` 兜底；**后端按契约返回后可去掉依赖，体验更稳定**。

---

## 8. 验收清单

### 8.1 `view=order` + `pending_cook`

- A1 单有油边+鸡翅，`items` 长度为 2
- 油边部分制作后：`cooked_quantity`/`cook_remaining`/`done_line` 符合 §4.2
- 油边全部制作后：`done_line=1`，行仍在 `items` 中
- 再请求 board，数据与划菜结果一致（不丢已划行）

### 8.2 `pending_prep` / `ready_serve`

- 同上逻辑，字段换为 `prep_`* / `served_`* / `remaining_quantity`

### 8.3 `advance-item` + 立即 board

- 连续划菜 3 次，每次 board 数量单调正确，无回退

### 8.4 与 `view=dish` 并存

- `view=dish` 可不带完整 `order_cards`，但 `dish_groups.lines` 含 `order_id`+`detail_id`
- `view=order` 不依赖前端从 dish_groups 二次拼整单

---

## 9. 前端对接摘要（供理解）


| 前端逻辑      | 依赖后端                                                         |
| --------- | ------------------------------------------------------------ |
| 整单全量菜品    | `items[]` 含该单全部明细                                            |
| 上未划 / 下已划 | `done_line` + `line_quantity` + `*_quantity` / `*_remaining` |
| 划菜后不移除行   | 已划行仍在 `items`，`done_line=1` 或 completed>0                    |
| 合并兜底      | `mergeOrderCards`（API 不全时）；**契约满足后应不再需要**                    |


前端源码：`board_mapper.dart`（`splitOrderLineForDisplay`、`mergeOrderCards`）、`workflow_order_card.dart`、`board_provider.dart`。

---

## 10. 给后端 AI 的改造任务模板（可直接复制）

```text
任务：按 docs/backend_order_view_coordination.md 改造 KDS 订单维度（view=order）数据契约。

背景：厨显 Flutter 端订单视图需要「一桌一单、列出全单所有菜；未划在上、已划在下带删除线」。当前问题：order_cards 缺其它菜、划菜后 refresh 丢已划行。

P0（必须）：
1. GET /kds/workflow/board?view=order&queue=* 时，order_cards[].items[] 返回该订单在当前 Tab 下的全部明细（detail_id 唯一），不要只返回仍可操作的行。
2. 每条 KdsWorkflowLine 必填：detail_id, name, line_quantity, quantity, unit, order_round, done_line；并按 queue 填充：
   - pending_prep: prep_remaining + prep_quantity
   - pending_cook: cook_remaining + cooked_quantity
   - ready_serve: remaining_quantity + served_quantity
3. 满足：line_quantity = completed + remaining（见文档 §4.2）；done_line=1 时 remaining=0 且 completed=line_quantity。
4. POST /kds/workflow/advance-item（及 advance-order）成功后，下一次 board 查询 items 与 DB 一致：已划行仍返回，done_line/已推进份数正确更新，禁止「划完即从 items 删除」导致前端已划菜消失。

P1（强烈建议）：
5. order_cards 支持 rounds[] 分组（order_round / label / items）。
6. view=dish 时 dish_groups.lines 带 order_id、detail_id，便于备注与合并。
7. 推进成功后的 WS/board 刷新与 advance API 同事务一致。

P2（可选）：
8. ready_serve 订单卡级 served_quantity / remaining_quantity 与行级汇总一致。

验收：
- A1 油边3+鸡翅2，pending_cook 下 items 两条；油边制作1份后 cooked_quantity=1、cook_remaining=2、done_line=0；全部制作后 done_line=1 且行仍在 items。
- advance-item 后连续 GET board 不丢已划数据。
- 前端订单视图无需依赖 dish_groups 拼整单即可展示全单菜品。

参考 OpenAPI：KdsOverviewLine、KdsWorkflowLine.done_line、GET /kds/workflow/board view=order。
关联文档：docs/backend_performance_coordination.md、docs/openapi.yaml。
```

---

## 11. 参考索引


| 主题      | 路径                                                    |
| ------- | ----------------------------------------------------- |
| 订单卡 UI  | `kds_app/lib/shared/widgets/workflow_order_card.dart` |
| 明细拆分/合并 | `kds_app/lib/features/board/board_mapper.dart`        |
| 看板加载    | `kds_app/lib/features/board/board_provider.dart`      |
| 数量解析    | `kds_app/lib/core/board/kds_line_quantity.dart`       |
| 推进 API  | `kds_app/lib/core/api/kds_api.dart`                   |
| OpenAPI | `docs/openapi.yaml`                                   |


