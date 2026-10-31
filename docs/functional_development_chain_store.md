# 连锁门店与点餐系统 — 功能开发文档

> **版本**：1.0（2026-04-03）  
> **关联契约**：`docs/openapi.yaml`、`docs/backend_chain_store_api.md`（三端任务包）、`docs/db_diancan.sql` + `docs/db_diancan_chain_store_patch.sql`；运营后台**连锁权限架构**见 **`docs/admin_chain_permission_architecture.md`**。  
> **用途**：作为**产品—研发—AI 辅助编码**的统一定义；任务拆解时按「模块 → 端 → 接口 → 验收」执行。

---

## 1. 文档目标与范围

| 项目 | 说明 |
|------|------|
| **目标** | 在微信小程序 + 运营后台 + **共用后端**架构下，完成**多门店选店、上下文一致、数据可入账**，并与现有单店/全局菜单、订单、支付、券、库存、智能点餐能力兼容。 |
| **范围内** | 门店主数据、C 端选店、订单/桌台挂 `shop_id`（按迭代）、券门店范围、菜单按店扩展（P2）、OpenAPI 契约、AI 点餐已有接口的配置约定。 |
| **范围外（除非另立项）** | 独立收银 APP 全量重做、外卖平台对接细节、多品牌租户 SaaS。 |

---

## 2. 三端架构

| 端 | 目录 | 说明 |
|----|------|------|
| **小程序** | `miniprogram/` | 用户点餐、支付、券、智能点餐对话；**无 B 端 JWT**。 |
| **运营后台** | `admin_panel/` | 门店/菜品/订单运维、券模板、报表；**JWT + 权限码**。 |
| **后端** | `server/` | **唯一业务与数据**来源；REST + WebSocket + 微信支付回调。 |

**调用关系**：小程序与后台**只**调用本后端 HTTP API；禁止小程序直连后台内网接口。

---

## 3. 功能模块总表（前后端分工）

表中「OpenAPI」列为路径摘要，**字段级以 `docs/openapi.yaml` 为准**。

| 模块 | 用户价值 | 小程序 | 运营后台 | 后端要点 | 主要接口（OpenAPI） |
|------|----------|--------|----------|----------|---------------------|
| **登录与身份** | 识别用户 | `code` 换 openid、用户信息 | 管理员登录 JWT | 校验微信、签发 JWT | `/order/getOpenid`、`/order/getUserInfo`、`/adminLogin` |
| **门店（连锁）** | 选店、就近门店 | 门店列表、本地存储 `shop_id`；请求带 `X-Shop-Id` | 门店 CRUD、订单/报表按店筛选 | 营业门店列表公开；订单落库 `shop_id`（迭代） | `GET /shop/list`、**`GET /admin/shop/list`**、`POST /admin/shop/save` |
| **菜单** | 浏览可售菜品 | 分类+菜品列表、WS 刷新 | 菜品/分类 CRUD、上下架 | 库存扣减规则、可扩展 `t_dish_shop` | `GET /dish/listAll`、`/admin/dish/*`、`/ws/menu` |
| **下单与加菜** | 生成订单 | 购物车、创建订单、加菜 | 订单查询/运维 | 明细强校验、库存事务 | `POST /order/create`、`POST /order/addDishes` |
| **支付** | 微信付 | 拉 prepay、调起支付、关单 | 对账/退款运维（如有） | 商户号与订单一致、回调验签 | `POST /order/getPrepayId`、`POST /order/closePay`、回调路径见 openapi |
| **取消订单** | 未支付取消 | 取消入口 | 后台取消（若开放） | 回退 `t_dish.stock` | `POST /order/cancel` |
| **订单查询** | 查单、历史 | 桌号/单号/历史列表 | 后台列表与详情 | 连锁按 `shop_id` 过滤（迭代） | `GET /order/get`、`GET /order/getOrder`、`POST /order/history` |
| **优惠券** | 拉新促活 | 领券、下单选券 | 券模板管理 | `apply_dish_ids`、`apply_shop_ids`、核销 | `/coupon/*`、`/admin/coupon/*` |
| **营业/桌台** | 堂食流程 | 扫码、营业状态 | 桌台管理 | 桌台与门店绑定（迭代） | `/order/ChangeBusiness`、桌台相关见 openapi |
| **智能点餐（AI）** | 自然语言推荐 | 对话 UI、工具编排 | 配置依赖后端 `application.yml` | 方舟/OpenAI 兼容调用 | `POST /order/ai/chatSuggest`、`GET /order/ai/tools`、`POST /order/ai/tools/execute` |
| **日结/报表** | 经营分析 | 一般不展示 | 日结、报表 | 已有 `shop_id` 参数 | `/admin/daily/*`、`/admin/report/*` |

---

## 4. 连锁门店专项说明

### 4.1 门店上下文

- **HTTP 头**：`X-Shop-Id: <整数>`（推荐，见 openapi `components.parameters.XShopId`）。  
- **Body/Query**：`shop_id`（与 Header 同用时须一致）。  
- **`merchantId`**：保留为支付/历史语义，**不可替代** `shop_id`（详见 `backend_chain_store_api.md`）。

### 4.2 数据库（必须对齐）

- 基线：`docs/db_diancan.sql`  
- 连锁增量：`docs/db_diancan_chain_store_patch.sql`  
- 设计说明：`docs/db_chain_store_design.md`  

**注意**：为 `t_shop` 增加 `latitude`、`sort_order` 等列后，`Shop` 实体才完整映射；未执行补丁前，新列在 JSON 中为 `null`。

### 4.3 接口落地状态（便于排期）

| 能力 | OpenAPI 1.2.5 | 后端实现状态 |
|------|----------------|--------------|
| C 端营业门店列表 | `GET /shop/list` | **已实现**（`ShopController`） |
| 订单/历史携带 `shop_id`、`X-Shop-Id` | 已补充 schema/description | **已实现**（`OrderController`：`create`/`addDishes`/`cancel`/`history`；需库表 **`t_order.shop_id`**） |
| 菜单按店 | `GET /dish/listAll` 已挂参数 | **参数已接**；按店价/库存待 **`t_dish_shop`** |
| 券适用门店 | `Coupon.apply_shop_ids` | **已实现校验**（`validateCoupon`）；需库表 **`t_coupon.apply_shop_ids`** |

（实现完成后应将上表更新为「已完成」，避免文档漂移。）

---

## 5. 智能点餐（AI）与配置

### 5.1 能力说明

- **对话**：`POST /order/ai/chatSuggest` — 自然语言生成点餐方案（依赖后端大模型 HTTP）。  
- **工具定义**：`GET /order/ai/tools` — 供前端或中台拼装 function calling。  
- **工具执行**：`POST /order/ai/tools/execute` — 后端执行 `create_order` 等（与真实下单逻辑对齐）。

### 5.2 配置（`server/src/main/resources/application.yml`）

- `ai.api.url`、`ai.api.key`：**强烈建议使用环境变量**（如 `ARK_API_KEY`），**勿将密钥提交 Git、勿粘贴到即时通讯**。  
- `ai.model`：方舟 **接入点 ID**（`ep-` 开头），非展示用模型名。  
- 连锁场景下，建议在请求中带 **`shop_id` / `X-Shop-Id`**（OpenAPI 已补充 chatSuggest），以便模型与落单限定在正确门店（需业务代码逐步消费）。

---

## 6. WebSocket

- **路径**：`ws(s)://<host>/ws/menu`  
- **消息类型**：`dish_catalog_changed`、`business_changed`、`auto_accept_changed`（见 `openapi.yaml` 顶层说明）。  
- **小程序**：配置 socket 合法域名；连锁下若后端按店广播，连接参数与实现保持一致。

---

## 7. 验收标准（迭代通用）

每条功能交付应满足：

1. **契约**：`docs/openapi.yaml` 中路径、方法、主要字段与实现一致；版本号递增并写 commit/PR 说明。  
2. **三端**：小程序或后台至少一方可端到端验证；后端有日志可追溯（`order_no`、`shop_id`、openid/adminId）。  
3. **错误**：`code != 0` 时 `msg` 可读；连锁冲突（跨店）有明确提示。  
4. **回归**：下单、加菜、取消、库存、支付任一改动须跑通**最小回归**（创建未支付单 → 取消或支付闭环）。

---

## 8. 里程碑建议

| 阶段 | 目标 | 交付 |
|------|------|------|
| **M1** | 可选门店 + 公开列表 | `GET /shop/list`、小程序选店、请求头带店 |
| **M2** | 订单归属门店 | `t_order.shop_id`、创建/查询校验 |
| **M3** | 券与活动按店 | `apply_shop_ids`、核销校验 |
| **M4** | 菜单按店价/库存 | `t_dish_shop`、`/dish/listAll` 行为升级 |

---

## 9. 文档与产物索引

| 文件 | 用途 |
|------|------|
| `docs/openapi.yaml` | **唯一 HTTP 契约** |
| `docs/backend_chain_store_api.md` | 三端任务包、联调顺序 |
| `docs/db_diancan_chain_store_patch.sql` | 连锁库表增量 |
| `docs/db_chain_store_design.md` | 表关系与索引说明 |
| `docs/functional_development_chain_store.md` | **本文**：功能级开发总览 |
| `docs/ai-tools.json` | 由 OpenAPI 生成的 AI 工具列表（若流水线有生成步骤则随 openapi 更新） |

---

**文档结束。**
