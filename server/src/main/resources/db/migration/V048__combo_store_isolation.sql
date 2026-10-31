-- V048: Add shop_id to t_combo for store-level combo isolation and replace uk_combo_dish with uk_combo_dish_shop
SET @schema_name = DATABASE();

-- 1. Add shop_id column to t_combo if missing (default 0 for HQ global template)
SET @add_col = IF(
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = @schema_name
     AND table_name = 't_combo'
     AND column_name = 'shop_id') = 0,
  'ALTER TABLE `t_combo` ADD COLUMN `shop_id` INT NOT NULL DEFAULT 0 COMMENT ''门店ID，0表示总部默认模板'' AFTER `dish_id`',
  'SELECT 1'
);
PREPARE stmt_add_col FROM @add_col;
EXECUTE stmt_add_col;
DEALLOCATE PREPARE stmt_add_col;

-- 2. Drop legacy single dish unique index uk_combo_dish if present
SET @drop_idx = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = @schema_name
     AND table_name = 't_combo'
     AND index_name = 'uk_combo_dish') > 0,
  'ALTER TABLE `t_combo` DROP INDEX `uk_combo_dish`',
  'SELECT 1'
);
PREPARE stmt_drop_idx FROM @drop_idx;
EXECUTE stmt_drop_idx;
DEALLOCATE PREPARE stmt_drop_idx;

-- 3. Add compound unique index uk_combo_dish_shop if missing
SET @add_uk = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = @schema_name
     AND table_name = 't_combo'
     AND index_name = 'uk_combo_dish_shop') = 0,
  'ALTER TABLE `t_combo` ADD UNIQUE KEY `uk_combo_dish_shop` (`dish_id`, `shop_id`)',
  'SELECT 1'
);
PREPARE stmt_add_uk FROM @add_uk;
EXECUTE stmt_add_uk;
DEALLOCATE PREPARE stmt_add_uk;

-- 4. Add index idx_combo_shop on shop_id if missing
SET @add_idx_shop = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = @schema_name
     AND table_name = 't_combo'
     AND index_name = 'idx_combo_shop') = 0,
  'ALTER TABLE `t_combo` ADD INDEX `idx_combo_shop` (`shop_id`)',
  'SELECT 1'
);
PREPARE stmt_add_idx_shop FROM @add_idx_shop;
EXECUTE stmt_add_idx_shop;
DEALLOCATE PREPARE stmt_add_idx_shop;
