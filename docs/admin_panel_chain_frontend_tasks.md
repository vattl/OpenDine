# 运营前端（admin_panel）连锁改造任务清单（对齐当前后端）

> 目标：确保前端与后端在「登录态、数据范围、门店上下文、错误码」上完全一致。  
> 基线：后端已支持 `scope=HQ|REGION|SHOP`、`/admin/me/permissions`、`/admin/me/shops`、门店越权码 `4001/4003`。

---

## 1. 契约对齐（必须先做）

- 登录返回：`token`、`permissions`、`adminId`、`userName`、`scope`、`shops`、`regionIds`
- 刷新恢复：`GET /admin/me/permissions`
- 门店分页：`GET /admin/me/shops?page=&pageSize=&keyword=`
- 需门店请求：带 `X-Shop-Id`（优先）或 `X-Shop-Code`
- 业务错误码：
  - `4001`：缺少门店上下文
  - `4003`：门店越权
  - `401`：登录过期

---

## 2. 前端状态模型（store / localStorage）

- **auth.token**：JWT
- **auth.permissions**：权限码数组
- **auth.scope**：`HQ|REGION|SHOP`
- **auth.regionIds**：区域 ID 数组
- **auth.accessibleShops**：`[{id, code, name}]`
- **context.currentShopId**：当前选中门店
- **context.currentShopCode**：可选（展示用）

验收：
- 登录后刷新页面，状态可恢复。
- 退出登录后上述状态被清理。

---

## 3. 登录与恢复流程任务

### ADM-FE-01 登录持久化
- 页面：`src/page/login/login.vue`
- 动作：
  - 保存 `token/scope/shops/regionIds/permissions`
  - 若 `shops.length===1` 自动设置 `currentShopId`

### ADM-FE-02 刷新恢复
- 启动时（如 `main.js` 或根布局）调用 `/admin/me/permissions`
- 用服务端返回值覆盖本地 `permissions/scope/shops/regionIds`
- 若本地 `currentShopId` 不在 `shops` 中，清空并提示重选

验收：
- 手动清空 `permissions` 后刷新，能自动恢复。

---

## 4. 门店选择器与懒加载任务

### ADM-FE-10 顶栏门店选择器
- 页面：`src/page/index/index.vue`
- 行为：
  - `SHOP` 且仅一店：默认选中并可隐藏选择器
  - `REGION` / `HQ`：显示选择器

### ADM-FE-11 大门店量分页加载
- 接口：`GET /admin/me/shops`
- 行为：
  - 首次加载 `page=1&pageSize=20`
  - 支持关键字搜索
  - 滚动或“加载更多”分页

### ADM-FE-12 当前门店一致性
- 切店后写入 `currentShopId`
- 所有需门店请求自动携带 `X-Shop-Id`

验收：
- 切换门店后，订单/桌台/报表类请求中的 `X-Shop-Id` 与 UI 一致。

---

## 5. 网络层与错误处理任务

### ADM-FE-20 Axios 请求拦截
- 文件：`api/header.js`
- 动作：
  - 自动附加 `Authorization`
  - 自动附加 `X-Shop-Id`（有当前门店时）

### ADM-FE-21 统一业务码处理
- `code=401`：跳登录并清理会话
- `code=4001`：提示“请先选择门店”
- `code=4003`：提示“当前账号无该门店权限”，可引导重选门店

验收：
- 模拟 4001/4003 返回，UI 提示文案与行为正确。

---

## 6. 页面改造清单（按优先级）

- P0：`订单管理`、`桌台管理`、`日结/收银扩展` 页面
  - 强制依赖 `currentShopId`
  - 无门店时禁用查询与操作按钮
- P1：`菜品/分类/物料` 页面
  - 与后端白名单保持一致
- P2：`统计报表` 页面
  - HQ 可允许“未选店看汇总”；REGION/SHOP 默认需选店

---

## 7. 与后端一致性约束（开发守则）

- 仅使用后端返回的 `shops` 渲染可选门店，不允许前端拼接/硬编码。
- 请求门店上下文以 `X-Shop-Id` 为准，不混用多个来源。
- `scope` 仅用于 UI 行为，不替代后端鉴权。
- 所有字段命名严格按 OpenAPI：`shop_id`、`shop_code`、`regionIds`、`scope`。

---

## 8. 缺失 API 补充与文档状态

当前已补齐并可用于前端：
- `GET /admin/me/shops`（分页门店懒加载）
- OpenAPI 已同步 `scope=HQ|REGION|SHOP` 与 `AdminMeShopsData`

若后续需要可补：
- `PUT /admin/me/current-shop`（服务端持久化默认门店，跨设备同步）

---

## 9. 联调验收用例

- 用例 A（SHOP 单店）：登录后自动选店，所有请求带该 `X-Shop-Id`。
- 用例 B（REGION 多店）：选择器可切店；越权门店返回 4003。
- 用例 C（HQ 大门店）：通过 `/admin/me/shops` 分页检索并选择门店。
- 用例 D（会话过期）：任意接口返回 401 后自动回登录。

---

**完成标准**：以上任务完成后，前端的门店上下文、数据范围与后端权限模型保持一致，联调不再出现“前端可见但后端拒绝”或“前端可伪造门店”的不一致问题。
