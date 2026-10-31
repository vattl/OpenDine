# 连锁模式 — 运营后台权限架构（总部 / 区域 / 门店 / 业务）

> **读者**：运营后台（`admin_panel`）与共用后端；与 **`docs/权限设计.md`**（RBAC 权限码）、**`docs/backend_chain_store_api.md`**（门店上下文）、**`docs/db_chain_store_design.md`**（`t_shop`、`t_admin_shop`）配套。  
> **目标**：在连锁场景下，建立**可落地的四级优先级**数据范围 + **业务权限码**体系；每个门店以**独立 `code`** 供前后端与集成系统识别，**`id` 仍为库内主键**。

---

## 1. 设计原则

| 原则 | 说明 |
|------|------|
| **双键门店** | **`t_shop.id`**：库内关联、JWT 内省、性能最优；**`t_shop.code`**：对外稳定标识（打印、对账、第三方、人工沟通），**全局唯一**（现有 `uk_code`）。 |
| **先范围后能力** | 先判定「能看/改哪些店的数据」，再判定「有没有 `order:view` 等业务权限」。无业务权限 → 403；有业务权限但无门店范围 → 403 或 4001（缺门店上下文），见下文。 |
| **显式门店上下文** | 除「总部全量」账号外，列表/写接口应带 **`X-Shop-Id`** 或 **`X-Shop-Code`**（二选一，后端统一解析为 `shop_id`），避免隐式默认店造成串店。 |
| **前端不信任展示** | 菜单/路由仅隐藏无权限入口；**最终以服务端校验为准**。 |

---

## 2. 四级优先级（决议顺序）

对任意管理员、任意请求，按**从高到低**合并**数据范围**；再与 **RBAC 权限码**做 AND。

```
① 总部（HQ）范围
        ↓ 若未覆盖则继续
② 区域（Region）范围 → 解析为若干 shop_id
        ↓ 若未覆盖则继续
③ 门店（Shop）范围 → 明确 shop_id 列表（如 t_admin_shop）
        ↓
④ 业务权限（Permission）→ order:view、dish:manage 等
```

### 2.1 ① 总部（最高优先级）

- **语义**：可管理**全部门店**（或品牌下全部门店，若未来引入 `brand_id`）。  
- **实现建议**（与现有表兼容）：  
  - **角色级**：如 `super_admin` 或独立角色 `hq_operator`，**不依赖** `t_admin_shop` 行即可视为全店；或  
  - **显式标记**：`t_admin.scope_type = 'HQ'`（需迁移，见 §6）。  
- **行为**：数据查询**不按** `t_admin_shop` 过滤（或仅当用户主动选店时加 `shop_id` 条件做「聚焦」）；写操作仍须校验业务权限码。

### 2.2 ② 区域（次优先级）

- **语义**：管理「大区 / 省区 / 营运片区」下**多店**，非全集团。  
- **解析**：区域 → **`shop_id` 集合**（由 `t_shop.region_id` 或关联表算出）。  
- **与 ③ 的关系**：  
  - 若同时配置区域与门店绑定，推荐 **取交集**：`allowed_shop_ids = shops(区域) ∩ t_admin_shop`，避免区域放大权限。  
  - 若产品要求 **取并集**，须在需求中明确并写死后端策略（默认不推荐）。

### 2.3 ③ 门店（基础数据范围）

- **语义**：店长、店员等**仅指定门店**。  
- **现有表**：**`t_admin_shop(admin_id, shop_id)`**（`docs/db_diancan_chain_store_patch.sql`）。  
- **空表语义**：非总部账号且未配置区域时，若无 `t_admin_shop` 行 → **无门店范围**，禁止操作依赖门店的数据接口。

### 2.4 ④ 业务权限（与现有文档一致）

- **来源**：`t_admin_role` → `t_role_permission` → `permission_code`。  
- **详见**：**`docs/权限设计.md`** §2～§5。  
- **校验顺序建议**：`JWT 有效` → `permission_code` 满足映射 → **`shop_id` 在允许范围内**（若该接口需要门店上下文）。

---

## 3. 门店 `code`：身份识别与 HTTP 约定

### 3.1 为什么需要 `code`

- `id` 自增在**多环境迁移、合并数据**时可能变化；`code` 可由运营制定（如 `SH001`、`HZ-WEST`），适合 **日志、打印小票、开放 API、收银机配置**。

### 3.2 后端识别优先级（与 `backend_chain_store_api` 对齐并扩展）

建议在服务端将「当前请求门店」解析为统一的 `resolved_shop_id`：

| 优先级 | 来源 | 说明 |
|--------|------|------|
| 1 | `X-Shop-Id` | 整数，与现网一致 |
| 2 | `X-Shop-Code` | 字符串，查 `t_shop.code` → `id`；不存在或多条 → 错误 |
| 3 | Body / Query `shop_id` | 与现有一致 |
| 4 | Body / Query `shop_code` | 可选，与 `X-Shop-Code` 同逻辑 |

**JWT 内可选 claim**（设计建议）：`default_shop_id` / `default_shop_code` —— 仅作**前端默认选中**，不能替代写操作的显式传参（防串店）。

### 3.3 登录 / `me` 接口应答扩展（契约建议）

在现有 `permissions`、`adminId`、`userName` 基础上增加**范围与门店清单**（示例字段名，实现时可微调并同步 OpenAPI）：

```json
{
  "code": 0,
  "token": "<JWT>",
  "adminId": 1,
  "userName": "zhangsan",
  "permissions": ["order:view", "dish:manage"],
  "scope": "SHOP",
  "shops": [
    { "id": 3, "code": "SH003", "name": "西湖店" }
  ]
}
```

| 字段 | 取值示例 | 含义 |
|------|----------|------|
| `scope` | `HQ` / `REGION` / `SHOP` | 主数据范围类型，与 §2 对应 |
| `regionIds` | `[1,2]` | 可选；`scope=REGION` 或 HQ 下辖区域时用 |
| `shops` | `{id,code,name}[]` | 当前账号**可操作门店列表**（已按 ①②③ 解析后的结果） |

**总部账号**：`scope=HQ` 时，`shops` 可返回**全部门店**或**分页查询接口**由前端懒加载（避免一次上万行）。

---

## 4. 运营前端（admin_panel）架构

### 4.1 全局状态（建议）

| 状态项 | 说明 |
|--------|------|
| `auth.token` | JWT |
| `auth.permissions` | 权限码数组，驱动菜单/按钮 |
| `auth.scope` | `HQ` / `REGION` / `SHOP` |
| `auth.accessibleShops` | `{ id, code, name }[]`，来自登录/`me` |
| `context.currentShopId` | 当前工作台选中的店 |
| `context.currentShopCode` | 与上同步，便于展示与请求头 |

**切换门店**：更新 `context`，后续 API 自动带 `X-Shop-Id` 或 `X-Shop-Code`（与后端约定一致即可）。

### 4.2 路由与菜单（元信息约定）

| meta 字段 | 用途 |
|-----------|------|
| `permission` | 所需权限码，如 `order:view`（与现有一致） |
| `requireShopContext` | `true` 时：无 `currentShopId` 且非 `HQ` 可全局不带店 → 引导先选店 |
| `allowHqWithoutShop` | `true` 时：总部可看汇总页，不要求先选店 |

**菜单生成**：`v-if` / 路由 `beforeEach`：`permissions` 包含 `meta.permission` 且（选店满足 `requireShopContext` 或 HQ 豁免）。

### 4.3 请求拦截器（Axios 等）

1. 附加 `Authorization: Bearer <token>`。  
2. 若 `meta.requireShopContext` 或接口文档要求门店：附加 `X-Shop-Id: context.currentShopId` **或** `X-Shop-Code: context.currentShopCode`（二选一，全项目统一）。  
3. 收到 **403**：提示无业务权限；收到 **4001**（或约定 code）：提示缺少门店或门店不在范围内。

### 4.4 UI 要点

- **顶部门店选择器**：仅展示 `accessibleShops`；`scope=HQ` 可增加「全部门店」虚拟项或汇总仪表盘入口。  
- **列表页**：门店维度筛选器选项 **不得大于** `accessibleShops`（防伪造参数；后端仍必须校验）。  
- **展示 `code`**：设置页、打印调试、对接说明中展示 `code`，减少误用 `id`。

---

## 5. 后端校验逻辑（与前端成对）

对每个需要门店的接口：

1. 解析 `resolved_shop_id`（§3.2）。  
2. 若接口**必须**门店且无法解析 → 返回约定错误码（如 **4001**）。  
3. 若管理员 **非 HQ** 或 **非全店角色**：`resolved_shop_id ∈ allowed_shop_ids`（由 §2 计算），否则 **403**（或 4003 门店越权）。  
4. 再查 **`t_api_permission` / 映射表** 是否具备对应 `permission_code`。

---

## 6. 数据模型演进建议（可选迁移）

当前已有 **`t_shop.code`**、**`t_admin_shop`**。若要完整支持 **区域**：

| 表 / 列 | 说明 |
|---------|------|
| `t_region` | `id`, `code`（唯一）, `name`, `parent_id`（可空，支持多级区域） |
| `t_shop.region_id` | 可空；门店归属区域 |
| `t_admin_region` | `admin_id`, `region_id`；区域经理绑定 |

**权限计算伪代码**：

```text
if role 含 HQ / super_admin:
    allowed_shop_ids = ALL_ACTIVE_SHOPS  // 或按 brand 过滤
else if t_admin_region 非空:
    allowed_shop_ids = SELECT shop_id FROM t_shop WHERE region_id IN (...)
    if t_admin_shop 非空:
        allowed_shop_ids = intersect(allowed_shop_ids, t_admin_shop)
else:
    allowed_shop_ids = t_admin_shop
```

---

## 7. 单店与历史环境兼容

- **无连锁配置**：`accessibleShops` 仅一行；前端可隐藏门店选择器，默认带唯一 `shop_id`/`code`。  
- **`t_admin_shop` 未使用**：总部超管仍可登录；店长类账号必须补数据，否则无门店范围。

---

## 8. 文档与契约维护

| 文档 | 职责 |
|------|------|
| **本文** | 连锁下**前后端**范围模型 + 门店 `code` + 前端状态/路由约定 |
| **`docs/admin_chain_permission_implementation.md`** | **按本文拆分的分阶段任务清单、补丁建议、现状缺口与验收顺序** |
| **`docs/权限设计.md`** | 业务权限码、RBAC 表、接口-权限映射 |
| **`docs/openapi.yaml`** | 登录/`me` 增字段、`X-Shop-Code`、错误码需在实现后同步 |
| **`docs/backend_chain_store_api.md`** | 小程序与后台共同的 `shop_id` 传递；可追加 `shop_code` 一节 |

---

## 9. 验收清单（实现阶段）

- [ ] 登录（及 `GET /admin/me/permissions`）返回 `scope` + `shops[{id,code,name}]`（或等价接口）。  
- [ ] 后端能从 **`X-Shop-Code`** 解析到唯一 `shop_id`。  
- [ ] 非总部用户访问他店 `shop_id` → 403/4003。  
- [ ] 前端门店选择器仅展示后端下发的列表；请求头与当前选中店一致。  
- [ ] OpenAPI 与 **`docs/权限设计.md`** 接口表同步更新。

---

**文档结束。**
