# 独立 KDS 厨房显示模块 — 开发计划

> **版本**：2.2（2026-05-25，P0～P4 后端交付完成）  
> **功能需求**：见 `**docs/kds_module_functional_requirements.md` v2.0**  
> **产品基准**：`**[KDS 厨房显示系统 PRD 商业版功能规格详解.md](./KDS%20厨房显示系统%20PRD%20商业版功能规格详解.md)`**  
> **约定**：仅改 `server/`；REST 变更同步 `openapi.yaml`；不修改小程序/收银/后台前端（除非另行要求）。

---

## 0. 工作进度记录（持续更新）


| 日期         | 阶段       | 状态    | 说明                                                      | OpenAPI     |
| ---------- | -------- | ----- | ------------------------------------------------------- | ----------- |
| 2026-05-25 | **P0**   | ✅ 已完成 | 迁移 SQL、实体/Mapper、Admin 配置 API、权限、`ApiPermissionMapping` | **v1.2.72** |
| 2026-05-25 | **P1**   | ✅ 已完成 | legacy sync、单测、WS 推送挂钩                                  | **v1.2.73** |
| 2026-05-25 | **P1.5** | ✅ 已完成 | skewer/summary、picked；expedition 用 order/list           | **v1.2.74** |
| 2026-05-25 | **P2**   | ✅ 已完成 | `/ws/kds`、`sync/all`、`sync/changes`、设备拦截器、WS ping       | **v1.2.74** |
| 2026-05-25 | **P3**   | ✅ 已完成 | lack、`kds_only` 跳过飞鹅、归档 Job、取消订单 WS                     | **v1.2.75** |
| 2026-05-25 | **P4**   | ✅ 已完成 | stats/today、订单列表 `kds_order_status`、Postman/权限文档        | **v1.2.75** |


**部署前置**：在目标库执行 `**docs/db_migration_kds.sql`**、`**docs/patch_kds_api_permission.sql`**（或 `init_api_permission.sql` 已含 KDS 段）。

**启用 KDS**：`POST /admin/kds/station/init-five` → 绑菜品/分类 → `POST /admin/kds/config/save` 设 `kds_mode=kds_only|both` → `POST /admin/kds/device/bind` 或 `POST /kds/device/login` 取 token。

---

## 1. 总览


| 项目  | v1.0 → v2.0 变化                                              |
| --- | ----------------------------------------------------------- |
| 状态机 | 由 MVP 三态改为 PRD **0/1/2/3 单品 + 10/20/30/40/90 整单**           |
| 分屏  | 由通用档口扩展为 **五屏 `screen_tag` + 抓串聚合 + 总出餐屏**                  |
| 接口  | 对齐 PRD：`/kds/item/status`、`/kds/sync/all`、`/kds/order/list` |
| 工期  | **约 5～6 周**（1 人全职后端）；原 3～4 周                                |


### 1.1 阶段划分


| 阶段       | 名称             | 交付物                                       | 预估    |
| -------- | -------------- | ----------------------------------------- | ----- |
| **P0**   | 数据与五屏配置        | 迁移 SQL v2、五屏种子、菜品/分类绑屏、权限                 | 5～6 天 |
| **P1**   | 工单与 PRD 状态机    | ticket + kds_order、item/status、order/list | 7～8 天 |
| **P1.5** | 抓串 + 总出餐       | skewer/summary、expedition 列表、finish-all   | 4～5 天 |
| **P2**   | WS + 离线同步      | `/ws/kds`、PRD 四类事件、sync/all、15s 心跳        | 5～6 天 |
| **P3**   | 缺货 + 打印协同 + 归档 | lack、sold_out 联动、both 模式、2h 归档任务          | 4～5 天 |
| **P4**   | 统计、三端透出、压测     | stats/today、legacy 同步、回归与 OpenAPI 收尾      | 3～4 天 |


### 1.2 里程碑（对齐 PRD 商用交付）


| 里程碑    | 内容                   | 发布建议              |
| ------ | -------------------- | ----------------- |
| **M1** | P0+P1：REST 划菜 + 三屏烤制 | 内测 1 店，`kds_only` |
| **M2** | P1.5：抓串汇总 + 总出餐      | 烧烤店全五屏试点          |
| **M3** | P2：WS + 离线 sync      | 安卓厨显联调            |
| **M4** | P3+P4：打印并行 + 上线验收    | 对照 PRD §8 验收表     |


---

## 2. 代码结构（v2）

```
server/src/main/java/com/lanf/
├── kds/
│   ├── controller/
│   │   ├── KdsOrderController.java       # GET /kds/order/list
│   │   ├── KdsItemController.java        # POST /kds/item/status, /lack
│   │   ├── KdsSkewerController.java      # summary, picked
│   │   ├── KdsSyncController.java          # sync/all, sync/changes
│   │   ├── KdsDeviceController.java
│   │   ├── KdsStatsController.java
│   │   └── admin/AdminKdsController.java
│   ├── service/
│   │   ├── KdsTicketService.java
│   │   ├── KdsOrderStatusAggregator.java
│   │   ├── KdsRoutingService.java          # dish_screen + cid → screen_tag
│   │   ├── KdsSkewerAggregateService.java
│   │   ├── KdsSyncService.java             # 幂等 batch
│   │   ├── KdsLackService.java
│   │   ├── KdsConfigService.java
│   │   ├── KdsPushService.java
│   │   ├── KdsArchiveJob.java              # 2h 归档 @Scheduled
│   │   └── KdsOrderHook.java
│   ├── entity/ + mapper/ + dto/
├── realtime/
│   ├── KdsWebSocketHandler.java
│   └── KdsWebSocketHub.java                # (shopId, screenTag) 分桶
└── config/WebSocketConfig.java             # /ws/kds
```

---

## 3. P0：数据与五屏配置

### 3.1 任务清单


| 任务 ID | 内容                                  | 产出                                             |
| ----- | ----------------------------------- | ---------------------------------------------- |
| P0-1  | `db_migration_kds.sql` v2           | 上表 §7 全部表；`item_status` TINYINT；种子五屏           |
| P0-2  | Entity/Mapper                       | 含 `KdsOrder`、`KdsDishScreen`                   |
| P0-3  | `POST /admin/kds/station/init-five` | 一键创建五 `screen_tag`                             |
| P0-4  | 菜品绑屏 CRUD                           | `POST /admin/kds/dish-screen/bind`（批量 dish_id） |
| P0-5  | cid 绑屏                              | `POST /admin/kds/station/category/bind`        |
| P0-6  | 门店 config                           | `sla_minutes=10`、`archive_hours=2`、`kds_mode`  |
| P0-7  | 权限                                  | `kds:view/operate/config` + SQL 映射             |
| P0-8  | OpenAPI Admin 段                     | version 补丁 + KDS tag                           |


### 3.2 五屏种子数据（单店示例）


| code   | screen_tag       | name   |
| ------ | ---------------- | ------ |
| SKEWER | skewer_aggregate | 抓串汇总屏  |
| MEAT   | meat_grill       | 荤菜烤制屏  |
| VEG    | veg_grill        | 素菜烤制屏  |
| SEA    | seafood_special  | 海鲜特色屏  |
| EXP    | expedition       | 总出餐核对屏 |


### 3.3 验收

- 五屏 station 可查询，`screen_tag` 唯一（同 shop）
- 菜品绑 `meat_grill` 后路由正确
- 默认 `kds_mode=print_only`

---

## 4. P1：工单引擎 + PRD 状态 API

### 4.1 任务清单


| 任务 ID | 内容                                                           |
| ----- | ------------------------------------------------------------ |
| P1-1  | `KdsRoutingService`：dish_screen > cid > default              |
| P1-2  | `KdsTicketService`：生成 ticket，`item_status=0`；幂等键             |
| P1-3  | `KdsOrder` 记录：`kds_order_status=10`                          |
| P1-4  | `KdsOrderHook` + `OrderController` 埋点（create/addDishes/paid） |
| P1-5  | `**POST /kds/item/status**`：0→1→2，校验 screen_tag；聚合整单         |
| P1-6  | `**GET /kds/order/list**`：screen_tag、status、分页、overdue_flag  |
| P1-7  | `**POST /kds/order/rush**`、`**POST /kds/order/finish-all**`  |
| P1-8  | 退菜 → `item_status=3` + void ticket                           |
| P1-9  | 套餐：combo 子行默认并头行（配置项保留）                                      |
| P1-10 | `sync_legacy_rece` 可选回写                                      |
| P1-11 | 单测：状态机、聚合 10/20/30/40                                        |


### 4.2 取消 v1「MVP 仅 pending/done」

首期即实现 **0/1/2/3**，`POST /kds/item/status` 为主入口；不再使用 `/kds/ticket/done` 作为主路径（可保留别名转发）。

### 4.3 验收

- 堂食下单 → 荤烤屏 `list` 可见，`item_status=0`
- 开始制作 → 1，整单 → 20
- 全部完成 → 2，整单 → 40
- 退菜 → 3，WS `cancel_item`

---

## 5. P1.5：抓串汇总 + 总出餐屏


| 任务 ID  | 内容                                                             |
| ------ | -------------------------------------------------------------- |
| P1.5-1 | `**GET /kds/skewer/summary`**：按 name 聚合 quantity               |
| P1.5-2 | `**POST /kds/skewer/picked`**：标记已抓齐，推进关联 ticket                |
| P1.5-3 | `**GET /kds/order/list?screen_tag=expedition`**：各岗 done 汇总按桌卡片 |
| P1.5-4 | 权限：skewer 仅 summary+picked；expedition 只读 done + finish-all     |
| P1.5-5 | OpenAPI + 聚合单测                                                 |


### 验收

- 油边 28 串 + 羊肉 36 串聚合正确（多样本订单）
- picked 后烤制屏收到 `update_order`
- 总出餐屏仅显示 done 明细

---

## 6. P2：WebSocket + 离线同步


| 任务 ID | 内容                                                         | PRD 对齐                |
| ----- | ---------------------------------------------------------- | --------------------- |
| P2-1  | `KdsWebSocketHub` 分桶                                       | (shop_id, screen_tag) |
| P2-2  | 注册 `**/ws/kds`**                                           | 文档注明 PRD `/kds/ws` 等价 |
| P2-3  | 事件：`new_order`、`update_order`、`cancel_item`、`cancel_order` | §6.1                  |
| P2-4  | `**POST /kds/sync/all`** + `t_kds_sync_dedup`              | §6.2、§4.8             |
| P2-5  | `**GET /kds/sync/changes?since=`**                         | 断线补偿                  |
| P2-6  | 心跳 15s + `POST /kds/device/heartbeat`                      | §4.8.1                |
| P2-7  | device/login 绑定 screen_tag                                 | §4.1.1                |
| P2-8  | Interceptor：/kds/** token                                  |                       |


### 验收

- 断网期间本地 10 条 status 变更，`sync/all` 后云端一致
- 重复 `client_id` 不重复执行
- 荤烤屏收不到素烤屏 `new_order`

---

## 7. P3：缺货、打印、归档


| 任务 ID | 内容                                               |
| ----- | ------------------------------------------------ |
| P3-1  | `**POST /kds/item/lack`**：记日志 + 配置项联动 `sold_out` |
| P3-2  | `kds_mode=both` 与 `doAutoAcceptAndPrint` 并行      |
| P3-3  | `kds_only` 跳过飞鹅（配置）                              |
| P3-4  | `**KdsArchiveJob`**：done 且超过 2h → archived       |
| P3-5  | `POST /admin/kds/ticket/repush`                  |
| P3-6  | 回归矩阵（五屏 × 三 mode）                                |


### 回归矩阵（必测）


| 场景      | print_only | kds_only     | both |
| ------- | ---------- | ------------ | ---- |
| 堂食下单    | 仅打印        | 五屏 WS+REST   | 打印+屏 |
| 加菜      | 原逻辑        | update_order | 二者   |
| 抓串聚合    | —          | summary 正确   | —    |
| 缺货 lack | —          | sold_out 可选  | —    |
| 退菜      | —          | cancel_item  | —    |
| 2h 归档   | —          | 列表不展示        | —    |


---

## 8. P4：统计、三端、文档


| 任务 ID | 内容                                             |
| ----- | ---------------------------------------------- |
| P4-1  | `**GET /kds/stats/today`**                     |
| P4-2  | `t_operation_log` module=kds                   |
| P4-3  | 可选：`admin/order/list` 增加 `kds_order_status` 透出 |
| P4-4  | `docs/postman-kds.json` 示例                     |
| P4-5  | 压测：100 并发 status 写 + WS 广播                     |
| P4-6  | 更新 `权限设计.md`、`B端接口与权限码汇总.md`                   |


---

## 9. 接口实现对照表（开发直连）


| PRD 接口                  | 实现 Controller               | 备注                    |
| ----------------------- | --------------------------- | --------------------- |
| `GET /kds/order/list`   | `KdsOrderController#list`   | 参数 screen_tag, status |
| `POST /kds/item/status` | `KdsItemController#status`  | item_id=detail_id     |
| `POST /kds/item/lack`   | `KdsItemController#lack`    |                       |
| `POST /kds/sync/all`    | `KdsSyncController#syncAll` |                       |
| WS 推送                   | `KdsPushService`            | 路径 `/ws/kds`          |
| —                       | `KdsSkewerController`       | PRD 抓串扩展              |
| —                       | `GET /kds/sync/changes`     | 断线补偿扩展                |


---

## 10. 订单埋点（不变，增强）


| 触发点         | Trigger    | 附加                       |
| ----------- | ---------- | ------------------------ |
| createOrder | CREATE     | new_order + kds_order=10 |
| addDishes   | ADD_DISHES | update_order             |
| 支付成功（打包/外卖） | PAID       |                          |
| delete_menu | REFUND     | cancel_item              |
| 取消订单        | CANCEL     | cancel_order             |
| repush      | MANUAL     |                          |


---

## 11. 已冻结决策（相对 v1 确认项）

依据 PRD 商用版，以下**不再待确认**：


| 项         | 决策                                  |
| --------- | ----------------------------------- |
| 单品状态      | **0/1/2/3** 首期全做                    |
| 整单状态      | **10/20/30/40/90** 由聚合器维护           |
| 五屏        | 默认烧烤五屏模板，可后台改映射                     |
| 抓串        | 独立聚合 API，不按桌                        |
| SLA       | 默认 **10** 分钟                        |
| 归档        | 已完成 **2** 小时                        |
| WS 心跳     | **15s**                             |
| 主操作 API   | `**POST /kds/item/status`**（PRD 原文） |
| legacy 同步 | 默认 **true**（便于收银/后台感知）              |
| 设备        | **必须** device_code + screen_tag 绑定  |


---

## 12. 任务勾选表

### P0

- P0-1～P0-8（见 §0 进度表）

### P1

- P1-1～P1-11（含 legacy、`KdsOrderStatusAggregatorTest`）

### P1.5

- P1.5-1～P1.5-5

### P2

- P2-1～P2-6
- P2-7 全局 `KdsDeviceAuthInterceptor`（`/kds/`**，排除 login）
- P2-8 WS 文本 `ping` → `{"type":"pong"}`

### P3

- P3-1 lack
- P3-2～P3-3 打印模式（`kds_only` 跳过飞鹅）
- P3-4 归档任务 `KdsArchiveJob`
- P3-5 repush（P1 已实现）
- P3-6 回归矩阵见 `**docs/kds_regression_matrix.md`**

### P4

- P4-1 stats/today
- P4-2 operation_log（lack 等）
- P4-3 admin/order/list `kds_order_status`
- P4-4 `docs/postman-kds.json`
- P4-5 压测（100 并发 status）— 联调阶段手工执行
- P4-6 权限文档更新

---

## 13. 前端协作说明（不写进本仓库，供厨显工程）


| PRD 要求              | 负责方               |
| ------------------- | ----------------- |
| 虚拟列表、禁动画            | 安卓/uni-app 厨显端    |
| 语音播报                | 客户端监听 `new_order` |
| 离线 IndexedDB/SQLite | 客户端；回写 `sync/all` |
| 横屏、常亮               | 客户端壳              |


后端需保证：**分页、增量 sync、幂等、分屏 WS**，详见功能需求 §6、§8。

---

## 14. 后续文档（建议下一迭代）

- `**kds_api_contract.md`**：入参/出参 JSON 示例（PRD 文末建议的接口详解）
- 厨显 uni-app 工程脚手架（独立立项）

