# 连锁模式 — 数据库设计说明

> 基线：`docs/db_diancan.sql`  
> 增量：`docs/db_diancan_chain_store_patch.sql`  
> 本文说明**表职责、关系、索引思路**与基线表的差异，不重复完整 DDL。

---

## 1. 设计目标

1. **订单、桌台可追溯门店**，支撑小程序选店、对账、报表按店聚合（与已有 `t_daily_stat.shop_id`、`t_payment.shop_id`、`t_shift.shop_id` 一致）。  
2. **优惠券、活动**可配置门店范围，避免跨店误用。  
3. **可选**：门店级菜品价/库存（`t_dish_shop`），避免多店共用一个 `t_dish.stock` 导致超卖或库存语义混乱。  
4. **可选**：管理员门店数据权限、用户最近门店，提升后台安全与 C 端体验。

---

## 2. 实体关系（逻辑）

```
t_shop (门店)
  ├── t_order.shop_id          ← 新增，订单归属
  ├── t_table.shop_id          ← 新增，桌号在店内唯一
  ├── t_dish_shop              ← 新增可选，覆盖 dish 价/库存
  ├── t_user_last_shop         ← 新增可选
  ├── t_admin_shop             ← 新增可选
  └── 已存在：t_daily_stat, t_payment, t_shift 上已有 shop_id

t_dish (总部菜品主数据)
  └── t_dish_shop.dish_id      ← 仅门店有差异时建行；无行则逻辑回退 t_dish

t_coupon
  └── apply_shop_ids (JSON)    ← 新增；与 apply_dish_ids 类似

t_order
  ├── merchantId               ← 保留：支付/商户配置维度
  └── shop_id                  ← 新增：经营维度，报表与权限主键
```

---

## 3. 基线表优化摘要（不改 Navicat 全量导出文件时）

| 表 | 变更类型 | 说明 |
|----|----------|------|
| `t_shop` | 扩列 + 索引 | `latitude/longitude/sort_order/remark`，列表按 `status+sort_order` 查询。 |
| `t_order` | 扩列 + 索引 | `shop_id`；按店+时间、按店+用户查单。 |
| `t_table` | 扩列 + 唯一键 | `shop_id` + `number` 唯一；桌码生成需带店。 |
| `t_coupon` | 扩列 | `apply_shop_ids`。 |
| `t_order_log` | 扩列 + 索引 | 冗余 `shop_id` 便于审计检索。 |
| `t_material` | 扩列 + 索引 | `shop_id`：原料与库存按店隔离；迁移见 **`docs/db_migration_material_payment_log_shop_id.sql`**。 |
| `t_stock_in` / `t_stock_out` | 扩列 + 索引 | `shop_id`：出入库记录归属门店，与原料一致。 |
| `t_payment_method` | 扩列 + 索引 | `shop_id`：`NULL` 表示全部门店共用的方式（如微信）；非空为单店自定义。 |
| `t_operation_log` | 扩列 + 索引 | `shop_id`：关键操作审计按店过滤；写入日志时需由业务层赋值。 |

---

## 4. 新增表说明

### 4.1 `t_dish_shop`

- **用途**：连锁下各店售价不同、或库存独立时使用。  
- **行为约定**（需应用层实现）：  
  - `unitprice` 非空 → 下单计价用门店价；否则用 `t_dish.unitprice`。  
  - `stock` 非空 → 该店启用有限库存，扣减在此行或统一策略；`NULL` 则回退到总部 `t_dish.stock` 规则。  
  - `onsale_override` 与总部 `onsale` 的合并规则应在服务端文档化（建议 override 优先）。

### 4.2 `t_user_last_shop`

- **用途**：小程序再次打开默认选中上次门店。  
- **键**：`openid` 唯一一行。

### 4.3 `t_admin_shop`

- **用途**：非超级管理员仅可管理指定门店；JWT 或登录后加载可访问 `shop_id` 列表。  
- **空表语义**：若不做数据权限，可不插入；超级管理员可视为全店。  
- **运营后台四级权限（总部 / 区域 / 门店 / 业务 RBAC）与门店 `code` 约定**：见 **`docs/admin_chain_permission_architecture.md`**。

### 4.4 `t_region` + `t_admin_region`（P3）

- **用途**：支持区域经理按区域管理多店。
- **结构**：
  - `t_region(id, code, name, parent_id)`
  - `t_shop.region_id`（门店归属区域）
  - `t_admin_region(admin_id, region_id)`（管理员绑定区域）
- **范围语义**：
  - 若管理员为 HQ：可访问全部营业门店；
  - 若绑定区域：`shops(区域)`；
  - 若同时绑定 `t_admin_shop`：取交集 `shops(区域) ∩ shops(管理员绑定门店)`。
- 迁移脚本见：`docs/db_migration_admin_region.sql`。

---

## 5. 索引与外键策略

- **外键**：`t_dish_shop`、`t_user_last_shop`、`t_admin_shop` 使用 FK 保证引用完整；`t_order.shop_id` 建议**先只加索引**，历史数据清洗后再考虑 FK，避免孤儿行阻塞迁移。  
- **`t_table.uk_table_shop_number`**：同一门店内桌号唯一；多店可重号「1 号桌」。

---

## 6. 与现有迁移脚本的关系

- `db_migration_dish_stock.sql`：已增加 `t_dish.stock`，与 `t_dish_shop.stock` 并存时，**必须在业务层定义唯一优先级**（推荐：有 `t_dish_shop` 行且 `stock` 非空则门店库存优先）。  
- `db_migration_coupon_apply_dish_ids.sql`：与 `apply_shop_ids` 独立，核销时**同时**校验菜品与门店范围。  
- **`db_migration_material_payment_log_shop_id.sql`**：为 `t_material`、`t_stock_in`、`t_stock_out`、`t_payment_method`、`t_operation_log` 增加 `shop_id`（及索引）；脚本内对历史 `t_material` 有默认 `UPDATE`，多店部署后请按实际修正。

---

## 7. 后续可演进（未包含在补丁中）

- **品牌表 `t_brand`**：`t_shop.brand_id`，多品牌集团。  
- **订单与支付商户**：`t_shop.mch_id` 或映射表，对接微信多商户号。  
- **会员储值按店拆分**：当前余额在 `t_user.balance`（全局按用户）；若需「每店独立储值」，需新表或扩列设计。  
- **`transac_status` 扩展**：若需 `refunded` 等状态，见独立 patch 脚本，勿与连锁补丁混用。

---

**文档结束。**
