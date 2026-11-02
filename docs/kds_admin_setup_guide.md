# KDS 运营后台配置指南

面向 **admin_panel** 与运营人员：说明厨显（KDS）在后台要配什么、调哪些 B 端接口、与厨显端如何分工。

契约以 `**server/docs/openapi.yaml`** 为准（标签 **KDS-Admin** / **KDS-Client**）。权限见 `**docs/权限设计.md`**、SQL `**docs/patch_kds_api_permission.sql`**。

---

## 1. 角色分工


| 端                      | 职责                      | 鉴权                                            |
| ---------------------- | ----------------------- | --------------------------------------------- |
| **运营后台** `admin_panel` | 档口、绑屏、门店模式、设备、补推工单；菜品上架 | JWT + `**X-Shop-Id`** + `**kds:config`**      |
| **厨显设备** App / 浏览器演示   | 看单、抓串、制作、完成、缺货          | `**X-Kds-Device-Token`**（`/kds/device/login`） |
| **菜品管理**（非 KDS 菜单）     | 门店挂菜、上下架、库存             | 现有 `/admin/dish/`*                            |


**制作动作不在运营端完成**，由厨显调用 `/kds/item/status`、`/kds/grill/start-cooking` 等。

---

## 2. 上线前准备（一次性）

按门店执行：

1. `**docs/db_migration_kds.sql`** — KDS 核心表
2. `**docs/db_migration_kds_skewer_gate.sql`** — 抓串闸门字段（`skewer_gate`、`skewer_picked`）
3. `**docs/patch_kds_api_permission.sql`**（或 `init_api_permission.sql` 内 KDS 段）— 接口权限映射

---

## 3. 推荐配置顺序（新店启用）

```text
init-five → dish-screen/bind →（可选）category/bind → config/save → device/bind
→ 菜品门店上架 → 测试下单 →（可选）ticket/repush
```


| 步骤  | 接口                                      | 说明                                     |
| --- | --------------------------------------- | -------------------------------------- |
| 1   | `POST /admin/kds/station/init-five`     | 创建六屏档口（含收银总览 `boss_overview`）          |
| 2   | `POST /admin/kds/dish-screen/bind`      | **必做**：菜品绑到 `meat_grill` 等（中间固定位 + 路由） |
| 3   | `POST /admin/kds/station/category/bind` | 未单独绑屏的菜按分类兜底                           |
| 4   | `POST /admin/kds/config/save`           | `kds_mode` 改为 `kds_only` 或 `both`      |
| 5   | `POST /admin/kds/device/bind`           | 可选；屏上也可 `POST /kds/device/login`       |
| 6   | `POST /admin/dish/updateOnSale` 等       | 绑屏菜在门店**上架**                           |
| 7   | 堂食下单验证                                  | 看 `kds_ticket`、厨显 WS                   |
| 8   | `POST /admin/kds/ticket/repush`         | 补历史单工单                                 |


---

## 4. 屏型说明（`screen_tag`）


| screen_tag         | 名称    | 生成工单 | 厨显 UI 要点                                     |
| ------------------ | ----- | ---- | -------------------------------------------- |
| `skewer_aggregate` | 抓串汇总  | 否    | 按菜名聚合，`/kds/skewer/summary` + **已抓齐**        |
| `meat_grill`       | 荤菜烤制  | 是    | 三栏：桌号队列 / 菜品固定位 / 制作中                        |
| `veg_grill`        | 素菜烤制  | 是    | 同上                                           |
| `seafood_special`  | 海鲜特色  | 是    | 同上                                           |
| `expedition`       | 总出餐核对 | 否    | 已出餐核对列表                                      |
| `boss_overview`    | 收银总览  | 否    | `**GET /kds/overview/board`**：跨岗筛选，默认按菜合并；只读 |


---

## 5. 运营后台页面 ↔ 接口对照（admin_panel 建议）

### 5.1 KDS 总设置


| 页面字段     | 表/逻辑                         | 接口                              |
| -------- | ---------------------------- | ------------------------------- |
| 启用模式     | `t_kds_shop_config.kds_mode` | `GET/POST /admin/kds/config/get |
| 抓串闸门     | `skewer_gate` 0/1            | 同上                              |
| 划菜回写收银   | `sync_legacy_rece`           | 同上                              |
| 下单自动推单   | `auto_push_on_create`        | 同上                              |
| 默认烤制屏    | `default_screen_tag`         | 同上                              |
| 待做超时(分钟) | `sla_minutes`                | 同上                              |
| 归档小时     | `archive_hours`              | 同上                              |
| 缺货联动售罄   | `lack_sets_sold_out`         | 同上                              |


`**kds_mode` 取值：**

- `print_only` — 仅打印，无厨显（默认）  
- `kds_only` — 仅厨显，跳过飞鹅厨房/前台打印  
- `both` — 打印 + 厨显

### 5.2 档口 / 五屏


| 页面   | 接口                                  |
| ---- | ----------------------------------- |
| 档口列表 | `GET /admin/kds/station/list`       |
| 编辑档口 | `POST /admin/kds/station/save`      |
| 删除档口 | `GET /admin/kds/station/delete?id=` |
| 一键五屏 | `POST /admin/kds/station/init-five` |


### 5.3 分类绑档口（兜底路由）


| 页面      | 接口                                                |
| ------- | ------------------------------------------------- |
| 某档口已绑分类 | `GET /admin/kds/station/category/list?stationId=` |
| 保存绑定    | `POST /admin/kds/station/category/bind`           |


路由优先级：**菜品绑屏 > 分类绑档口 > `default_screen_tag`**。

### 5.4 菜品绑屏（烤制中间栏必配）


| 页面      | 接口                                                     |
| ------- | ------------------------------------------------------ |
| 按屏查看已绑菜 | `GET /admin/kds/dish-screen/list?screenTag=meat_grill` |
| 批量绑到某屏  | `POST /admin/kds/dish-screen/bind`                     |


**中间栏 `product_slots` 规则：**

- 只展示 **本屏 `t_kds_dish_screen` 绑定** 且 **门店 `t_dish_shop` 已挂店** 且 **上架** 的菜品  
- 顺序：`t_dish.sorting`  
- `quantity=0` 仍显示格位（灰显、不可点合并制作）

**上架不在 KDS 接口**，走菜品管理（`onsale` / `onsale_override`）。

### 5.5 厨显设备


| 页面     | 接口                              |
| ------ | ------------------------------- |
| 设备列表   | `GET /admin/kds/device/list`    |
| 绑定设备到屏 | `POST /admin/kds/device/bind`   |
| 解绑     | `POST /admin/kds/device/unbind` |


### 5.6 运维


| 页面      | 接口                              |
| ------- | ------------------------------- |
| 按订单重推工单 | `POST /admin/kds/ticket/repush` |


---

## 6. 接口清单（`/admin/kds/`*）

统一请求头：

```http
Authorization: Bearer <JWT>
X-Shop-Id: 1
Content-Type: application/json
```

权限码：`**kds:config**`（店长/管理员/超管，见权限设计）。


| 方法   | 路径                                 | 摘要         |
| ---- | ---------------------------------- | ---------- |
| GET  | `/admin/kds/station/list`          | 档口列表       |
| POST | `/admin/kds/station/save`          | 保存档口       |
| GET  | `/admin/kds/station/delete`        | 删除档口       |
| POST | `/admin/kds/station/init-five`     | 初始化五屏      |
| POST | `/admin/kds/station/category/bind` | 分类绑档口      |
| GET  | `/admin/kds/station/category/list` | 档口分类列表     |
| POST | `/admin/kds/dish-screen/bind`      | 菜品绑屏       |
| GET  | `/admin/kds/dish-screen/list`      | 绑屏列表       |
| GET  | `/admin/kds/config/get`            | 读门店 KDS 配置 |
| POST | `/admin/kds/config/save`           | 存门店 KDS 配置 |
| GET  | `/admin/kds/device/list`           | 设备列表       |
| POST | `/admin/kds/device/bind`           | 绑设备        |
| POST | `/admin/kds/device/unbind`         | 解绑设备       |
| POST | `/admin/kds/ticket/repush`         | 订单重推工单     |


---

## 7. Postman / curl 示例

环境变量建议：`BASE=http://127.0.0.1:8080`、`JWT=...`、`SHOP_ID=1`。

### 7.1 登录后初始化五屏

```bash
curl -s -X POST "%BASE%/admin/kds/station/init-five" \
  -H "Authorization: Bearer %JWT%" \
  -H "X-Shop-Id: %SHOP_ID%"
```

### 7.2 荤烤屏绑定菜品（中间固定位）

```bash
curl -s -X POST "%BASE%/admin/kds/dish-screen/bind" \
  -H "Authorization: Bearer %JWT%" \
  -H "X-Shop-Id: %SHOP_ID%" \
  -H "Content-Type: application/json" \
  -d "{\"screen_tag\":\"meat_grill\",\"dish_ids\":[17,18,19,20,21]}"
```

支持 camelCase：`screenTag`、`dishIds`。

### 7.3 启用厨显 + 抓串闸门

```bash
curl -s -X POST "%BASE%/admin/kds/config/save" \
  -H "Authorization: Bearer %JWT%" \
  -H "X-Shop-Id: %SHOP_ID%" \
  -H "Content-Type: application/json" \
  -d "{
    \"kds_mode\": \"both\",
    \"skewer_gate\": 1,
    \"sync_legacy_rece\": 1,
    \"auto_push_on_create\": 1,
    \"sla_minutes\": 10,
    \"archive_hours\": 2,
    \"lack_sets_sold_out\": 0,
    \"default_screen_tag\": \"meat_grill\"
  }"
```

### 7.4 预绑荤烤设备

```bash
curl -s -X POST "%BASE%/admin/kds/device/bind" \
  -H "Authorization: Bearer %JWT%" \
  -H "X-Shop-Id: %SHOP_ID%" \
  -H "Content-Type: application/json" \
  -d "{\"device_code\":\"KDS-MEAT-01\",\"screen_tag\":\"meat_grill\",\"device_name\":\"荤烤1号\"}"
```

响应 `device.device_token` 可写入厨显端配置。

### 7.5 补推订单工单

```bash
curl -s -X POST "%BASE%/admin/kds/ticket/repush" \
  -H "Authorization: Bearer %JWT%" \
  -H "X-Shop-Id: %SHOP_ID%" \
  -H "Content-Type: application/json" \
  -d "{\"order_id\": 9626}"
```

### 7.6 分类绑档口（示例）

先 `GET /admin/kds/station/list` 取 `meat_grill` 对应 `station.id`，再：

```bash
curl -s -X POST "%BASE%/admin/kds/station/category/bind" \
  -H "Authorization: Bearer %JWT%" \
  -H "X-Shop-Id: %SHOP_ID%" \
  -H "Content-Type: application/json" \
  -d "{\"station_id\": 2, \"cid_list\": [\"烧烤\", \"荤菜\"]}"
```

`cid_list` 须与 `t_category.cid` 一致。

---

## 8. 厨显端（给联调对照，非运营配置）


| 能力     | 接口                              |
| ------ | ------------------------------- |
| 设备登录   | `POST /kds/device/login`        |
| 烤制三栏   | `GET /kds/grill/board`          |
| 按菜合并制作 | `POST /kds/grill/start-cooking` |
| 单明细状态  | `POST /kds/item/status`         |
| 抓串汇总   | `GET /kds/skewer/summary`       |
| 已抓齐    | `POST /kds/skewer/picked`       |
| 实时推送   | WebSocket `/ws/kds`             |


本地演示页：`http://127.0.0.1:8080/kds-demo.html`（静态资源 `kds-demo.html`）。

---

## 9. 常见问题


| 现象               | 原因                           | 处理                                 |
| ---------------- | ---------------------------- | ---------------------------------- |
| 烤制屏中间「无绑屏上架菜品」   | `t_kds_dish_screen` 无记录或菜未上架 | `dish-screen/bind` + 菜品上架          |
| 有单但烤制屏为空（抓串开）    | 未点「已抓齐」                      | 抓串屏 `skewer/picked`                |
| 下单无 `kds_ticket` | `kds_mode=print_only`        | `config/save` 改为 `both`/`kds_only` |
| 菜去了错误屏           | 绑屏/分类/默认屏                    | 检查 `dish-screen`、category bind     |
| 历史单无工单           | 启用前下单                        | `ticket/repush`                    |
| 运营接口 403         | 无 `kds:config`               | 角色授权 + 执行权限 SQL                    |


**自检 SQL（门店 1、荤烤屏）：**

```sql
SELECT * FROM t_kds_dish_screen WHERE shop_id = 1 AND screen_tag = 'meat_grill';
SELECT d.id, d.name, d.onsale, dsh.onsale_override
FROM t_kds_dish_screen ds
JOIN t_dish d ON d.id = ds.dish_id
LEFT JOIN t_dish_shop dsh ON dsh.dish_id = ds.dish_id AND dsh.shop_id = ds.shop_id
WHERE ds.shop_id = 1 AND ds.screen_tag = 'meat_grill';
```

---

## 10. 相关文档


| 文档                                      | 内容             |
| --------------------------------------- | -------------- |
| `openapi.yaml`                          | 完整请求/响应 Schema |
| `B端接口与权限码汇总.md`                         | 权限码速查          |
| `kds_module_functional_requirements.md` | 业务流程、状态机       |
| `kds_module_development_plan.md`        | 分期能力           |
| `db_migration_kds.sql`                  | 表结构            |


---

## 11. admin_panel 模块建议（产品）

1. **KDS 设置** — config get/save（模式、抓串闸门、SLA）
2. **档口管理** — station list/save/init-five
3. **菜品绑屏** — 按 `screen_tag` 多选菜品树，调用 dish-screen/bind + list
4. **分类绑档口** — 档口详情内 cid 多选
5. **设备管理** — device list/bind/unbind
6. **工单补推** — 订单详情页按钮 → ticket/repush（需 `order_id`）

菜品上下架仍在 **菜品管理** 模块，与 KDS 绑屏页可做跳转提示。