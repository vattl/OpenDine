-- V047: Add cashier_id column to t_order to record the on-duty cashier ID (referencing t_admin.id)
SET @add_col = IF(
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = DATABASE()
     AND table_name = 't_order'
     AND column_name = 'cashier_id') = 0,
  'ALTER TABLE `t_order` ADD COLUMN `cashier_id` INT(11) DEFAULT NULL COMMENT ''当班收银员ID，关联 t_admin.id'' AFTER `order_admin_id`',
  'SELECT 1'
);
PREPARE stmt_add_col FROM @add_col;
EXECUTE stmt_add_col;
DEALLOCATE PREPARE stmt_add_col;

SET @add_idx = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = DATABASE()
     AND table_name = 't_order'
     AND index_name = 'idx_order_cashier_id') = 0,
  'ALTER TABLE `t_order` ADD INDEX `idx_order_cashier_id` (`cashier_id`)',
  'SELECT 1'
);
PREPARE stmt_add_idx FROM @add_idx;
EXECUTE stmt_add_idx;
DEALLOCATE PREPARE stmt_add_idx;
