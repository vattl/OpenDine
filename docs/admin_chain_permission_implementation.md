# 连锁运营权限 — 按 `admin_chain_permission_architecture.md` 拆任务与补丁

> **主设计**：`docs/admin_chain_permission_architecture.md`  
> **本文**：分阶段任务清单、依赖关系、建议补丁文件与**当前代码缺口**（便于排期与验收）。

---

## 0. 现状快照（仓库内）

| 项 | 现状 |
|----|------|
| `t_shop.code` | 库表已有（`docs/db_diancan.sql`），实体 `Shop.code` 已有 |
| `t_admin_shop` | 补丁已定义（`docs/db_diancan_chain_store_patch.sql`），**Java 层未见 Entity/Mapper** |
| 请求门店解析 | `ShopChainSupport` 仅 **`X-Shop-Id` + body/query `shop_id`**，**无 `X-Shop-Code` / `shop_code`** |
| 登录 / `me` | `AdminController` 仅返回 `token`、`permissions`、`adminId`、`userName`，**无 `scope`、`shops`** |
| JWT | `JwtUtils.createJWT` 仅 `id` + subject，**无自定义 claims**（可选后续加 `default_shop_id`，非 P0） |
| 运营前端 | `admin_panel/` 为 Vue，需在登录与 axios 层接新字段与请求头 |

---

## 1. 阶段划分（建议）

| 阶段 | 目标 | 风险 |
|------|------|------|
| **P0** | `X-Shop-Code` / `shop_code` 解析为 `shop_id`，与现有 `X-Shop-Id` 优先级一致；OpenAPI 与 `backend_chain_store_api` 同步 | 低 |
| **P1** | 登录 + `GET /admin/me/permissions` 返回 `scope` + `shops[]`；计算规则：**总部角色 = 全店**，否则 = **`t_admin_shop` 关联门店** | 中（需定「总部」判定） |
| **P2** | 对**需门店**的 `/admin/*` 接口：解析 `resolved_shop_id` 后校验 **`resolved_shop_id ∈ allowed`**；错误码 **4001**（缺店）、**4003**（越权） | 高（接口面广，宜白名单渐进） |
| **P3** | **区域**：`t_region`、`t_shop.region_id`、`t_admin_region` + 范围交集逻辑 | 高（新表 + 迁移） |
| **P4** | **admin_panel**：存 `scope`/`shops`、顶栏选店、`axios` 自动带 `X-Shop-Id` 或 `X-Shop-Code` | 依赖 P1 |

---

## 2. P0 任务清单（门店 code 解析）

1. **扩展 `ShopChainSupport`**
   - 新增 `parseHeaderShopCode(HttpServletRequest)`、`parseBodyShopCode(Object)`（trim，空则 null）。
   - 新增 **`resolveShopIdFromCode(String code, IShopService or ShopMapper)`**：`WHERE code = ? AND status = 1`（或仅存在性校验，与产品一致），0/多行报错。
   - 合并优先级（与架构文档 §3.2 一致）：  
     `X-Shop-Id` → `X-Shop-Code`（解析出 id）→ body/query `shop_id` → body/query `shop_code`。  
   - **互斥校验**：若同时出现 `X-Shop-Id` 与 `X-Shop-Code`，解析后 **id 必须一致**，否则「门店信息不一致」类错误。

2. **调用点**
   - 所有已使用 `ShopChainSupport` 的 Controller（C 端 + 将来 B 端）逐步改为统一入口方法，例如 `AdminShopContext.resolve(request, bodyShopId, bodyShopCode)`（可新建小工具类避免循环依赖）。

3. **契约**
   - `docs/openapi.yaml`：`components.parameters` 增加 **`X-Shop-Code`**；相关路径 description 注明与 `X-Shop-Id` 二选一及优先级。
   - `docs/backend_chain_store_api.md`：§3.3 / §4 增加 **`X-Shop-Code`** 一行表。

**验收**：仅带 `X-Shop-Code: SH003` 时，解析结果与带对应 `X-Shop-Id` 一致；冲突时报错。

---

## 3. P1 任务清单（登录返回 scope + shops）

### 3.1 数据访问层

1. 新增 **`AdminShop` 实体** + **`AdminShopMapper`**（表 `t_admin_shop`：`admin_id`, `shop_id`）。
2. 新增 **`IAdminShopAccessService`**（名称可调整），方法建议：
   - `boolean isHeadquartersAdmin(Integer adminId)` — 见下节。
   - `List<Shop> listAccessibleShops(Integer adminId)` — HQ 返回营业中全部门店（或 `status=1` 全部）；非 HQ 返回 `t_admin_shop` JOIN `t_shop`。
   - `AdminDataScope resolveScope(Integer adminId)` — 返回枚举 `HQ | SHOP`（**REGION 待 P3**）。

### 3.2 「总部」判定（必须写死一种，建议优先角色）

| 方案 | 做法 | 备注 |
|------|------|------|
| **A（推荐）** | `t_admin_role` 关联的角色中 **`role_code = super_admin`**（或配置表 `hq_role_codes`）→ `scope=HQ` | 与 `docs/权限设计.md` 一致 |
| **B** | `t_admin` 增加 `scope_type` 列 `HQ/SHOP` | 需迁移，灵活 |

### 3.3 接口改动

1. **`POST /adminLogin`**：在现有字段上增加：
   - `scope`: `"HQ"` | `"SHOP"`（**暂不含 REGION** 直至 P3）
   - `shops`: `[{ "id", "code", "name" }]`（`code` 允许 null 时前端展示 `-`）
   - 可选：`regionIds: []` 占位，P3 再填
2. **`GET /admin/me/permissions`**：同样附带 `scope`、`shops`，避免前端仅刷新权限时丢范围。

### 3.4 HQ 的 `shops` 体量

- 门店数 &lt; 200：登录一次返回全量可接受。  
- 更大：**登录只返回 `scope=HQ` + `shops: []`**，并新增 **`GET /admin/me/shops?page=&pageSize=`**（需 `dish:manage` 或独立 `shop:read`），前端懒加载选店列表。

**验收**：店长账号仅见绑定店；超管见全店；`me` 与登录一致。

---

## 4. P2 任务清单（服务端门店越权校验）

1. **工具方法**（示例签名）：  
   `void assertShopAllowed(HttpServletRequest request, Integer resolvedShopId, boolean required)`  
   - `required && resolvedShopId == null` → **4001**（或与现有 `R` 约定 `code`）。  
   - 非 HQ 且 `resolvedShopId ∉ allowed_shop_ids` → **4003**。  
   - HQ：仅校验 `shop` 存在且可用（可选）。

2. **接入策略（渐进）**
   - 维护 **`/admin/**` 需门店白名单**（path + method），先接：**订单列表、桌台、日结/收银扩展**等已带 `shop_id` 的接口。
   - 未列入白名单的接口暂不强制，避免一次性打挂后台。

3. **性能**：同一请求内可 **`request.setAttribute("allowed_shop_ids", ...)`** 或 ThreadLocal 缓存，避免重复查库。

**验收**：非 HQ 用户篡改 `X-Shop-Id` 为他店 → **4003**；不带店且 required → **4001**。

---

## 5. P3 任务清单（区域，可选 DDL 补丁）

**新文件建议**：`docs/db_migration_admin_region.sql`（勿与现网未执行脚本冲突，按需合并）

```sql
-- 示例结构（实现前请评审字段与索引）
CREATE TABLE IF NOT EXISTS `t_region` (
  `id` int NOT NULL AUTO_INCREMENT,
  `code` varchar(32) NOT NULL,
  `name` varchar(64) NOT NULL,
  `parent_id` int NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_region_code` (`code`)
) ...;

ALTER TABLE `t_shop` ADD COLUMN `region_id` int NULL ...;

CREATE TABLE IF NOT EXISTS `t_admin_region` (
  `id` int NOT NULL AUTO_INCREMENT,
  `admin_id` int NOT NULL,
  `region_id` int NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_admin_region` (`admin_id`, `region_id`),
  ...
);
```

**逻辑**：按架构文档 **区域店铺 ∩ t_admin_shop** 得 `allowed_shop_ids`；`scope=REGION`。

---

## 6. P4 任务清单（admin_panel）

| # | 任务 |
|---|------|
| 1 | `login.vue`：解析并持久化 `scope`、`shops`（sessionStorage + Vuex 任选） |
| 2 | 若 `shops.length === 1`：自动设当前店并写 header |
| 3 | 若 `shops.length > 1`：顶栏 `Select`，切换时更新 `currentShopId`/`currentShopCode` |
| 4 | `axios` 拦截器：有当前店则设 **`X-Shop-Id`**（推荐，少一次 code 查库）或统一 **`X-Shop-Code`** |
| 5 | `router`：`meta.requireShopContext`；非 HQ 且无当前店 → 跳转选店或首页提示 |
| 6 | 处理 **4001 / 4003**：统一 toast + 必要时清空当前店重选 |

---

## 7. 错误码约定（建议与 `R` 对齐）

| code | 含义 |
|------|------|
| **4001** | 缺少必选门店上下文（header/body 均无法解析 `shop_id`） |
| **4003** | 门店不在当前管理员可操作范围内（越权） |

若项目坚持业务错误仅用 HTTP 200 + `code != 0`，则上述为 **body.code**，与现有 **401/403** JWT 权限并存。

---

## 8. 文档勾选（与架构 §9 对应）

- [x] P0：`openapi` + `backend_chain_store_api` + `ShopChainSupport` + `IShopService.requireActiveShopIdByCode` + C 端订单/菜单解析  
- [x] P1：`AdminShop`/`AdminShopMapper`、`IAdminShopAccessService`、`POST /adminLogin` 与 `GET /admin/me/permissions` 的 `scope`/`shops`/`regionIds`；`openapi` + `权限设计.md` 5.1  
- [x] P2：白名单路径表 + 拦截器/断言 **4001**/**4003**（已支持 header/query/json body 解析门店上下文）  
- [x] P3：迁移脚本 + `db_chain_store_design.md` 更新 ER 描述（新增 `db_migration_admin_region.sql`，后端支持 `scope=REGION` 与区域∩门店逻辑）  
- [x] P4：`admin_panel` 登录存储与请求头选店（登录落库 scope/shops、顶部选店、axios 自动附带 `X-Shop-Id`、4001/4003 提示）

---

## 9. 建议排期顺序

```
P0（解析 code） → P1（登录/me 范围） → P4（前端接范围与头） → P2（后端越权，按白名单扩面） → P3（区域，按需）
```

补充（已实现）：
- 已新增 `GET /admin/me/shops?page=&pageSize=&keyword=`，用于 HQ 大门店量时分页懒加载。
- 已新增 `docs/db_seed_admin_region_example.sql`，便于联调环境快速初始化区域/门店/管理员绑定示例数据。

---

## 10. 回链

实现过程中请保持 **`docs/admin_chain_permission_architecture.md`** 为语义权威；若实现与文档冲突，**先改文档再改代码**或反之一次性对齐 OpenAPI。

**文档结束。**
