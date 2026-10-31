# Database Design

Last Updated:

Database Version:

Database Engine:

ORM:

Migration Tool:

---

# 1. Database Principles

- Preserve production data
- Prefer additive schema evolution
- Use migrations
- Avoid ambiguous status semantics
- Maintain business-level integrity

---

# 2. Entity Overview

| Entity | Purpose |
|---|---|
|  |  |

---

# 3. Relationship Overview

```text
User
  └── Order
        └── OrderItem

Replace with actual model.
```

---

# 4. Tables

Table: users

Purpose:

Primary Key:

Columns

| Column | Type | Nullable | Default | Description |
|---|---|---|---|---|
| id |  | NO |  |  |

Indexes

Unique Constraints

Foreign Keys

Business Rules

---

# 5. Status Enums

OrderStatus

Allowed values:

PENDING
PAID
PREPARING
READY
COMPLETED
CANCELLED

Meaning:

PENDING:

PAID:

PREPARING:

READY:

COMPLETED:

CANCELLED:

Allowed transitions:

PENDING
→ PAID
→ PREPARING
→ READY
→ COMPLETED

Exceptional transitions:

PENDING → CANCELLED
PAID → CANCELLED

---

# 6. Data Integrity Rules

Examples:

Order total must not be negative.

OrderItem must belong to an existing Order.

Unique external payment ID must not be reused.

Project-specific:

---

# 7. Money

Currency:

Storage Type:

Precision:

Rule:

Do not use floating-point types for monetary values where exact decimal precision is required.

---

# 8. Time and Timezone

Database timezone:

Application timezone:

Storage convention:

Display convention:

---

# 9. Audit Fields

Recommended fields where relevant:

created_at
updated_at
created_by
updated_by
deleted_at

Soft Delete:
YES / NO

---

# 10. Index Strategy

Important query patterns:

Required indexes:

---

# 11. Migration Policy

All schema changes must use migrations.

Applied migrations must not be casually rewritten.

Prefer:

Add
→ Backfill
→ Support transition
→ Verify
→ Remove legacy later

---

# 12. Migration History

Dish shop full overrides (方案 A)

- Description: `t_dish_shop` 新增 7 列——`specification_override`（255，NULL=回退）、`name_override`（50）、`image_override`（50）、`unit_override`（10）、`type_id_override`（int）、`sorting_override`（int）、`serving_duration_override`（int）。门店上下文编辑菜品的规格/名称/图片/单位/分类/排序/出餐时长仅写覆盖列，NULL 时 C 端回退 `t_dish` 总部值；门店拖拽排序仅写 `sorting_override`。
- Date: 2026-09-07
- Impact: `POST /admin/dish/save`、`POST /admin/dish/sort` 门店上下文语义扩展；`GET /dish/listAll` 按覆盖后分类分组；`POST /combo/detail`、`GET /admin/combo/getByDishId` 子菜展示应用名称/图片/单位/规格/时长覆盖。纯 ADD COLUMN，存量 103 行覆盖记录不受影响（新列 NULL 即回退总部）。
- Migration: `docs/db_migration_dish_shop_full_overrides.sql`
- Rollback: 确认应用不再读取后手工删除 7 列。

Shop category sorting overrides (WI-007)

- Description: 新增 `t_category_shop`，以唯一键 `(shop_id, category_id)` 保存门店分类 `sorting_override`。分类主数据继续共用 `t_category`；缺少覆盖时按 `t_category.sorting` 回退，首次排序后为当前店全量写入连续 `1..n`。
- Date: 2026-10-09
- Impact: `POST /admin/category/sort` 不再跨店改写全局分类顺序；后台与 C 端菜单按门店分类覆盖排序。`POST /admin/dish/sort` 同时收紧为当前门店、当前生效分类内排序。
- Migration: `docs/db_migration_category_shop_sorting.sql`
- Rollback: 先回退应用读取/写入，再删除 `t_category_shop`；表为加法迁移，不改变 `t_category`/`t_dish_shop` 旧数据。

Dish serving duration

- Description: `t_dish.serving_duration_minutes`，正整数分钟，非空且默认 10；存量菜品自动回填为 10。
- Date: 2026-09-02
- Impact: 菜品维护接口可读写；KDS 单品超时优先按菜品时长，关联失败时回退门店 SLA。
- Migration: `docs/db_migration_dish_serving_duration_minutes.sql`
- Rollback: 确认应用不再读取后手工删除该列。

V001

Description:

Date:

Impact:

Rollback:

---

# 13. Production Data Compatibility

Current production assumptions:

Legacy data concerns:

---

# 14. Backup and Recovery

Backup Strategy:

Restore Strategy:

Migration Backup Requirement:

---

# 15. Seed Data

Used:
YES / NO

Purpose:

Rules:

Never rely on unsafe production seed behavior.

---

# 16. Data Retention

Entity: t_operation_log（操作审计）/ t_order_log（订单操作）/ t_dish_stock_log（库存变动）三张日志表

Retention:
- 在线查询：仅近 30 天（AdminLogService 窗口裁剪，越界空页 + hint）
- 归档检索 / 导出：窗口放宽至 365 天（[now-365d, now-30d]；导出 [now-365d, now]）
- 物理删除：LogRetentionCleanupTask 每日 03:20 执行，删除 created_at < now - log.retention-days（默认 400 天），
  分批（单批 5000 行）避免长事务；400 天 > 365 天查询边界，保证查询窗口永不返回已删数据

Deletion Behavior: 调度任务物理删除；迁移脚本 docs/db_migration_log_governance.sql 幂等可重跑

Compliance Requirement: 日志保留期须覆盖财务对账/纠纷审计窗口（≥ 1 年）

---

# 17. Sensitive Data

Sensitive fields: 操作日志快照中的手机号、身份证号（t_operation_log.request_snapshot / before_state / after_state）

Encryption: 传输层 TLS；存储不加密（快照经脱敏后落库）

Masking: LogMaskUtil 正则打码（手机号 138****5678、身份证 前3后4），查询/归档/导出统一走掩码

Logging restrictions: 审计落库禁止包含密码、令牌、商户密钥；SecurityAuditService 契约注释强制

---

# 18. Known Database Risks

---

# 19. Planned Changes

---

# 20. Related Files

Models:

Migrations:

Seeds:

Schema:

---

# 21. Related Documents

Architecture:
docs/ARCHITECTURE.md

API:
docs/API.md

Project State:
docs/PROJECT_STATE.md

## C007 / V007 显式迁移

支付服务不再启动时建表或改表。迁移资源为 `src/main/resources/db/migration/V007__audit.sql`，通过独立 `AuditSchemaMigration` CLI 执行并记录 SHA-256；应用启动只读检查版本与业务字段，缺失时失败。新增 `t_app_schema_version` 与 `t_kds_device_workflow(device_id PK, workflows, updated_at)`；已有支付表采用 IF NOT EXISTS，旧收款唯一索引仅在新索引成功建立后移除。不得删除业务数据。MySQL DDL 自动提交，失败须纠正原因并重跑，不可假定事务回滚。

上线顺序：备份与恢复验证 → 停止旧版本写入/扩容 → 使用独立迁移账号运行 CLI → 改用最小 DML 运行账号启动 → 核查支付/KDS。回滚应用可保留新增表；迁移过的历史已完成追偿余额归零属于数据修正，恢复需以备份和对账为依据。

## C009/T01b：t_kds_projection_intent（2026-09-08）
增量迁移：docs/db_migration_kds_projection_intent.sql。InnoDB；id自增主键；order_id与事件来源/明细JSON记录投影意图；attempts/next_attempt_ms控制重试。idx_kds_intent_due(next_attempt_ms,id)限制到期扫描；idx_kds_intent_order(order_id,id)保持同订单任务顺序。无外键，避免删除源订单时级联删除未处理证据；可空来源字段保持既有语义。
新安装也需执行该增量迁移。原事务插入；工作事务行锁、投影/事件写入及DELETE确认原子提交。异常回滚后保留任务，30秒后重试；不按两天窗口删除。回滚应用时保留表和待办，不自动DDL、不清空。历史已漏发记录仍由旧源订单对账补偿，新表不能自动恢复升级前未知意图。生产迁移与MySQL并发锁验收尚未执行。

## C009/T03：报表/归档执行恢复

## UI013：日结幂等键（2026-10-04）

- 增量迁移：`src/main/resources/db/migration/V019__ui013_daily_close_idempotency.sql`。
- `t_daily_close_snapshot` 新增可空 `settle_idempotency_key VARCHAR(64)`，并建立唯一索引 `uk_daily_close_shop_idempotency(shop_id, settle_idempotency_key)`。历史快照保持 NULL，MySQL 唯一索引允许多个 NULL，因此无需回填且不改变历史数据。
- 回滚应优先回滚应用并保留该可空字段/索引；如确需 DDL 回滚，须先确认无新版实例和重试请求再删除索引与字段。
## C010/T01：日志模块治理（2026-09-10）
- docs/db_migration_log_governance.sql：t_order_log 补 shop_id（门店隔离）、三张日志表补主键/索引（幂等）
- LogRetentionCleanupTask：日志保留策略物理清理（默认 400 天，每日 03:20 分批删除）
- t_order_log 补 C 端写入（create/cancel/add_dish/pay/refund），OrderLog 实体加 shop_id
显式增量迁移docs/db_migration_report_job_recovery.sql为t_report_export_job添加可空run_token VARCHAR(32)、lease_until DATETIME；新增(job_type,status,lease_until,id)及(shop_id,status,job_type)索引。旧RUNNING且lease_until为NULL可恢复；DONE/FAILED保持终态。t_report_job_admission为单行InnoDB配额锁表，id=1保护跨实例受理检查和插入，同事务锁定当前有效任务，单次最多读129行。
执行CAS领取任务并设置30分钟租约；DONE/FAILED必须同时匹配执行令牌和RUNNING状态；过期但未被接管的原执行者仍可完成，成功接管后旧令牌永久失效，租约时间由数据库时钟计算。应用回滚保留字段和记录，禁止旧执行器与新实例并行处理；旧代码无执行令牌保护。未执行生产MySQL迁移或压测。

- C009/T04 / C012 营业日报聚合：`ReportOrderAggregate` 对 `t_order` 中 `merchantId='1'`、已支付且已接单（`rec_order/off_order`，兼容历史 NULL）的订单执行 `COUNT/SUM`，金额逐字段 `COALESCE`，结果保持 `BigDecimal`；`net_amount` 按 `sett_amount+service_fee-discount_amount-refund_amount-pay_amount_gift` 计算。财务归属优先 `pay_time`，仅当其为 NULL 时回退 `order_time`，边界固定为 `>= start AND < end`。单店绑定 `shop_id`；总部由应用逐店使用各自切日窗口聚合。查询仍为单行聚合且 statement timeout=5秒。`docs/db_migration_order_business_report_indexes.sql` 幂等补充 `idx_order_shop_pay_time(shop_id,pay_time)`；既有 `idx_order_shop_time(shop_id,order_time)` 支撑历史回退分支。上线前须在真实 MySQL 用 `EXPLAIN` 核验实际数据分布下的执行计划，H2 测试不作为索引命中证明。

- C009/T05：无新增DDL。t_kds_delivery_consumer.bootstrap_base_cursor=Long.MAX_VALUE表示本轮Bootstrap未完成，ACK不得清除bootstrap_required；完整页登记真实baseCursor后才可确认。起止租约校验/登记在短事务内，缺口检查和分页读取在事务外。后台每单独立5秒事务；源订单和原近2天窗口保留，拒绝/重启后由下一次Bootstrap重试唤醒。

## WI-008：收银账单自定义范围权限

- 增量迁移：`docs/db_migration_cashier_bill_custom_range.sql`。
- 注册权限码 `admin:super`，并且只向 `role_code='super_admin'` 授权；不修改订单表结构或历史数据。
- 必须先执行迁移再部署应用，否则自定义时间查询按失败关闭返回 403；默认未结账及最近 3 小时查询不受影响。
