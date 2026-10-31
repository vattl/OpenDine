-- 活动弹窗门店：由单值 shop_id 改为 apply_shop_ids（varchar JSON 数组，如 [1,5,3]）
-- 若尚未执行 db_migration_activity_popup_shop_id.sql，可直接执行本脚本（会新建 apply_shop_ids）
-- 若已存在 int 型 shop_id，会迁移为 JSON 后删除 shop_id

SET @has_apply := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_activity_popup' AND COLUMN_NAME = 'apply_shop_ids'
);
SET @has_shop_id := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_activity_popup' AND COLUMN_NAME = 'shop_id'
);

SET @sql := IF(@has_apply = 0,
  'ALTER TABLE `t_activity_popup` ADD COLUMN `apply_shop_ids` varchar(500) NULL DEFAULT NULL COMMENT ''适用门店 JSON 数组，如 [1,5,3]；NULL/空/[]=全部门店'' AFTER `type`',
  'SELECT ''apply_shop_ids already exists'' AS msg');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := IF(@has_shop_id > 0,
  'UPDATE `t_activity_popup` SET `apply_shop_ids` = CONCAT(''['', `shop_id`, '']'') WHERE `shop_id` IS NOT NULL AND (`apply_shop_ids` IS NULL OR TRIM(`apply_shop_ids`) = '''')',
  'SELECT ''skip shop_id data migrate'' AS msg');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @sql := IF(@has_shop_id > 0,
  'ALTER TABLE `t_activity_popup` DROP COLUMN `shop_id`',
  'SELECT ''skip drop shop_id'' AS msg');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_idx := (
  SELECT COUNT(*) FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 't_activity_popup' AND INDEX_NAME = 'idx_activity_popup_shop'
);
SET @sql := IF(@has_idx > 0,
  'ALTER TABLE `t_activity_popup` DROP INDEX `idx_activity_popup_shop`',
  'SELECT ''skip drop index'' AS msg');
PREPARE stmt FROM @sql;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
