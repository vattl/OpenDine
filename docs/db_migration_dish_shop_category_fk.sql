-- ============================================================================
-- 门店菜品分类关联约束迁移（t_dish_shop.type_id_override → t_category.id）
-- 目标：
--   1) 清洗历史脏数据：type_id_override 指向不存在分类的行重置为 NULL（回退总部 t_dish.typeId）；
--   2) 为 type_id_override 显式建立索引 idx_dish_shop_type_override（外键会自动建索引，显式声明便于排查）；
--   3) 建立外键约束 fk_dish_shop_category：门店菜品分类必须存在于 t_category。
-- 约定：
--   - NULL 回退总部分类的语义不变（与 unitprice / onsale_override 一致）；
--   - ON DELETE RESTRICT：分类被任何门店菜品引用时禁止删除，与
--     AdminCategoryController.delete 的逻辑层删除保护一致，双保险。
-- 依赖：t_dish_shop.type_id_override 列已存在（docs/db_migration_dish_shop_full_overrides.sql）
-- 建议：低峰期执行；执行前备份 t_dish_shop（例如：
--       CREATE TABLE t_dish_shop_bak_<yyyymmdd> AS SELECT * FROM t_dish_shop;）
-- 幂等：基于 information_schema 判断，可重复执行；已存在的索引/约束自动跳过。
-- 巡检：脚本自带 0 与 4 两段只读检查，执行前先跑 0 段确认影响行数。
-- ============================================================================

SET NAMES utf8mb4;

-- 0) 执行前巡检：将被清洗的脏数据行数（只读，不修改）
SELECT 't_dish_shop.type_id_override 脏数据行数（将重置为 NULL）' AS check_name, COUNT(*) AS cnt
FROM `t_dish_shop`
WHERE `type_id_override` IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM `t_category` c WHERE c.`id` = `t_dish_shop`.`type_id_override`);

-- 0.1) 参考巡检：总部 t_dish.typeId 脏数据行数（仅报告，不修改；如需同等约束可参照本脚本扩展）
SELECT 't_dish.typeId 脏数据行数（仅报告）' AS check_name, COUNT(*) AS cnt
FROM `t_dish`
WHERE `typeId` IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM `t_category` c WHERE c.`id` = `t_dish`.`typeId`);

-- 1) 清洗：不存在分类的门店覆盖分类重置为 NULL（回退总部 t_dish.typeId）
UPDATE `t_dish_shop`
SET `type_id_override` = NULL
WHERE `type_id_override` IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM `t_category` c WHERE c.`id` = `t_dish_shop`.`type_id_override`);

-- 2) 幂等创建索引 idx_dish_shop_type_override
SET @idx_exists := (SELECT COUNT(*) FROM information_schema.STATISTICS
                    WHERE table_schema = DATABASE() AND table_name = 't_dish_shop'
                      AND index_name = 'idx_dish_shop_type_override');
SET @ddl_idx := IF(@idx_exists = 0,
  'ALTER TABLE `t_dish_shop` ADD INDEX `idx_dish_shop_type_override` (`type_id_override`) USING BTREE',
  'SELECT ''idx_dish_shop_type_override already exists'' AS msg');
PREPARE stmt_idx FROM @ddl_idx;
EXECUTE stmt_idx;
DEALLOCATE PREPARE stmt_idx;

-- 3) 幂等添加外键 fk_dish_shop_category
SET @fk_exists := (SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
                   WHERE constraint_schema = DATABASE() AND table_name = 't_dish_shop'
                     AND constraint_name = 'fk_dish_shop_category'
                     AND constraint_type = 'FOREIGN KEY');
SET @ddl_fk := IF(@fk_exists = 0,
  'ALTER TABLE `t_dish_shop` ADD CONSTRAINT `fk_dish_shop_category` FOREIGN KEY (`type_id_override`) REFERENCES `t_category` (`id`) ON DELETE RESTRICT ON UPDATE RESTRICT',
  'SELECT ''fk_dish_shop_category already exists'' AS msg');
PREPARE stmt_fk FROM @ddl_fk;
EXECUTE stmt_fk;
DEALLOCATE PREPARE stmt_fk;

-- 4) 执行后巡检：残留脏数据应为 0；同时确认约束与索引已生效
SELECT 't_dish_shop.type_id_override 残留脏数据（应为 0）' AS check_name, COUNT(*) AS cnt
FROM `t_dish_shop`
WHERE `type_id_override` IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM `t_category` c WHERE c.`id` = `t_dish_shop`.`type_id_override`);

SELECT constraint_name, constraint_type
FROM information_schema.TABLE_CONSTRAINTS
WHERE constraint_schema = DATABASE() AND table_name = 't_dish_shop'
  AND constraint_name = 'fk_dish_shop_category';

SELECT index_name, column_name
FROM information_schema.STATISTICS
WHERE table_schema = DATABASE() AND table_name = 't_dish_shop'
  AND index_name = 'idx_dish_shop_type_override';
