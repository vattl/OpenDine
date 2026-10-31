# Scenario Matrix — WI-034

| ID | Scenario | Preconditions/Input | Expected Business Outcome | Invariants | Verification | Result |
|---|---|---|---|---|---|---|
| S01 | 旧库缺少全部商业化列 | 仅有旧版 `t_combo` 六列 | V034 补齐 11 列且保留套餐数据 | INV-COMBO-034-01/02 | migration static test | PASS |
| S02 | 数据库只补过部分列 | 任意部分新列已存在 | 仅添加缺失列，不报重复列 | INV-COMBO-034-02 | migration idempotency assertions | PASS |
| S03 | 已完成迁移后重复执行 | 11 列均存在 | 全部语句退化为 `SELECT 1` | INV-COMBO-034-02 | migration idempotency assertions | PASS |
| S04 | 旧套餐未配置商业规则 | 新字段均使用默认值 | 套餐继续不限购、全时段可售且允许叠券 | INV-COMBO-034-03 | combo rule tests | PASS |
| S05 | 新库从全量基线初始化 | 执行 `docs/db_diancan.sql` | `t_combo` 表直接包含 11 列 | INV-COMBO-034-01 | static schema check | PASS |
| S06 | 构建发布包 | Maven clean package | JAR 包含 V034 且编译成功 | INV-COMBO-034-01 | package build | PASS |
