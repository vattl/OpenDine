# Implementation Design — WI-034

## Root Fix / Owner

根因属于数据库版本链缺口。修复所有权放在正式版本迁移目录，而不是让 Mapper 忽略字段或在请求中捕获 SQL 异常。

## Design

1. 新增 `V034__combo_commercialization.sql`。
2. 每个字段通过 `INFORMATION_SCHEMA.COLUMNS` 判断后动态执行 `ALTER TABLE ... ADD COLUMN`，保证旧库补齐、部分迁移库续跑、已完成库重跑均安全。
3. 迁移不调用 `p_add_col_if_missing`，避免依赖仅在其他脚本执行期间临时存在的过程。
4. 更新全量建库表定义，使新库天然具备字段。
5. 更新增量同步脚本，使通用同步路径同样补齐字段。

## Compatibility / Defaults

- `limit_per_order`, `limit_per_user`, `daily_stock` 默认为 NULL：不限。
- `limit_cycle='daily'`：只有设置用户限购值时才生效。
- 时间、星期和时段字段默认为 NULL：不限制。
- `apply_dining_type='all'`：堂食和外卖均可。
- `allow_coupon=1`：保持旧套餐允许叠券。

## Failure / Boundary Behavior

- `t_combo` 不存在时迁移会失败，阻止错误发布；基础套餐表必须先由既有迁移创建。
- 部分字段已存在时只补缺失字段。
- DDL 失败时修正数据库原因后重跑同一迁移；幂等检查允许续跑。

## Rollback / Recovery

新增列向后兼容，旧应用会忽略。回滚应用无需删除字段；避免破坏已写入的新配置。

## Verification Strategy

- RED：迁移资源测试在 V034 不存在时失败。
- GREEN：验证 11 个字段、`INFORMATION_SCHEMA` 幂等判断及无外部过程依赖。
- 运行套餐商业规则测试。
- 运行 Maven 编译与完整 JAR 打包，确认迁移资源进入产物。
