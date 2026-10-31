-- V045: Convert unique index on t_order_detail(mId, client_line_id) to regular index.
-- This prevents constraint violations when combo meals or multiple detail lines share or correlate identifiers.

SET @drop_uk1 = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = DATABASE()
     AND table_name = 't_order_detail'
     AND index_name = 'uk_detail_order_client_line'
     AND non_unique = 0) > 0,
  'ALTER TABLE `t_order_detail` DROP INDEX `uk_detail_order_client_line`',
  'SELECT 1'
);
PREPARE stmt_drop_uk1 FROM @drop_uk1;
EXECUTE stmt_drop_uk1;
DEALLOCATE PREPARE stmt_drop_uk1;

SET @drop_uk2 = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = DATABASE()
     AND table_name = 't_order_detail'
     AND index_name = 'idx_detail_order_client_line'
     AND non_unique = 0) > 0,
  'ALTER TABLE `t_order_detail` DROP INDEX `idx_detail_order_client_line`',
  'SELECT 1'
);
PREPARE stmt_drop_uk2 FROM @drop_uk2;
EXECUTE stmt_drop_uk2;
DEALLOCATE PREPARE stmt_drop_uk2;

SET @add_idx = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = DATABASE()
     AND table_name = 't_order_detail'
     AND index_name = 'idx_order_detail_client_line') = 0,
  'ALTER TABLE `t_order_detail` ADD KEY `idx_order_detail_client_line` (`mId`, `client_line_id`)',
  'SELECT 1'
);
PREPARE stmt_add_idx FROM @add_idx;
EXECUTE stmt_add_idx;
DEALLOCATE PREPARE stmt_add_idx;
