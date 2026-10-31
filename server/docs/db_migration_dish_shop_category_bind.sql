-- ============================================================================
-- t_dish_shop 分类显式绑定迁移（配合代码：AdminDishController 挂载/保存自动回填）
-- 目标：
--   1) 报告总部菜品中 typeId 无效（NULL 或不存在于 t_category）的清单 —— 需人工补分类；
--   2) 存量回填：type_id_override 为 NULL 且总部 typeId 有效 → 写入（绑定总部分类）；
--   3) 回填后仍为 NULL 的行（总部无有效分类）必须由人工补好分类后重跑，直到 0 残留；
--   4) 残留为 0 后，将 type_id_override 收紧为 NOT NULL（数据库层硬约束，每行必有分类）。
-- 依赖：
--   - docs/db_migration_dish_shop_full_overrides.sql（列已存在）
--   - docs/db_migration_dish_shop_category_fk.sql（外键约束，与本脚本先后均可，幂等兼容）
-- 建议：低峰期执行；执行前备份 t_dish_shop（CREATE TABLE t_dish_shop_bak_<yyyymmdd> AS SELECT * FROM t_dish_shop;）
-- 幂等：基于 information_schema 判断，可重复执行；回填 UPDATE 天然幂等。
-- 流程：先跑 1/2 巡检 → 执行 3 回填 → 若 4 仍有残留（总部无分类），人工补分类后重跑 3/4/5 → 5 收紧 NOT NULL。
-- ============================================================================

SET NAMES utf8mb4;

-- 1) 巡检 A：总部菜品无有效分类清单（需人工补分类；补完重跑本脚本 3/4/5）
SELECT d.id AS dish_id, d.name AS dish_name, d.typeId AS hq_type_id,
       (SELECT COUNT(*) FROM t_dish_shop ds WHERE ds.dish_id = d.id AND ds.type_id_override IS NULL) AS unbound_link_cnt
FROM t_dish d
WHERE d.typeId IS NULL
   OR NOT EXISTS (SELECT 1 FROM t_category c WHERE c.id = d.typeId)
ORDER BY d.id;

-- 2) 巡检 B：当前未绑定分类的门店行数（应回填）
SELECT COUNT(*) AS unbound_rows
FROM t_dish_shop ds
WHERE ds.type_id_override IS NULL;

-- 3) 存量回填：type_id_override 为 NULL 且总部 typeId 有效 → 绑定总部分类
UPDATE t_dish_shop ds
JOIN t_dish d ON d.id = ds.dish_id
SET ds.type_id_override = d.typeId
WHERE ds.type_id_override IS NULL
  AND d.typeId IS NOT NULL
  AND EXISTS (SELECT 1 FROM t_category c WHERE c.id = d.typeId);

-- 4) 回填后巡检：仍为 NULL 的行（= 总部无有效分类，需人工补分类后重跑 3/4/5）
SELECT ds.shop_id, ds.dish_id, d.name AS dish_name, d.typeId AS hq_type_id
FROM t_dish_shop ds
JOIN t_dish d ON d.id = ds.dish_id
WHERE ds.type_id_override IS NULL
ORDER BY ds.shop_id, ds.dish_id;

-- 5) 幂等收紧 NOT NULL：仅当无 NULL 残留且尚未收紧时执行
SET @remaining := (SELECT COUNT(*) FROM t_dish_shop WHERE type_id_override IS NULL);
SET @col_not_null := (SELECT COUNT(*) FROM information_schema.COLUMNS
                      WHERE table_schema = DATABASE() AND table_name = 't_dish_shop'
                        AND column_name = 'type_id_override' AND IS_NULLABLE = 'NO');
SET @ddl := IF(@remaining = 0 AND @col_not_null = 0,
  'ALTER TABLE `t_dish_shop` MODIFY COLUMN `type_id_override` int NOT NULL COMMENT ''门店分类(t_category.id)；显式绑定，挂载/保存时自动回填总部分类''',
  IF(@remaining > 0,
     'SELECT ''SKIP: 仍有 NULL 行（总部菜品无有效分类），请先人工补分类后重跑本脚本'' AS msg',
     'SELECT ''type_id_override already NOT NULL'' AS msg'));
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 6) 终检：未绑定行数应为 0（若 5 被 SKIP，则 4 的输出即待人工处理清单）
SELECT COUNT(*) AS remaining_unbound
FROM t_dish_shop WHERE type_id_override IS NULL;
