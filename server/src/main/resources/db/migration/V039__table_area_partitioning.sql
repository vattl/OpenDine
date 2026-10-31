-- V039: Table area partitioning and POS coordination API permissions
-- Idempotent column addition for t_table (area_code, area_name)

SET @ddl_area_code = IF(
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = DATABASE()
     AND table_name = 't_table'
     AND column_name = 'area_code') = 0,
  'ALTER TABLE `t_table` ADD COLUMN `area_code` VARCHAR(32) NOT NULL DEFAULT ''hall'' COMMENT ''桌台区域编码(hall/box/patio)'' AFTER `number`',
  'SELECT 1'
);
PREPARE stmt_area_code FROM @ddl_area_code;
EXECUTE stmt_area_code;
DEALLOCATE PREPARE stmt_area_code;

SET @ddl_area_name = IF(
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_schema = DATABASE()
     AND table_name = 't_table'
     AND column_name = 'area_name') = 0,
  'ALTER TABLE `t_table` ADD COLUMN `area_name` VARCHAR(64) NOT NULL DEFAULT ''大厅散座'' COMMENT ''桌台区域名称'' AFTER `area_code`',
  'SELECT 1'
);
PREPARE stmt_area_name FROM @ddl_area_name;
EXECUTE stmt_area_name;
DEALLOCATE PREPARE stmt_area_name;

SET @ddl_idx_area = IF(
  (SELECT COUNT(*) FROM information_schema.statistics
   WHERE table_schema = DATABASE()
     AND table_name = 't_table'
     AND index_name = 'idx_table_shop_area') = 0,
  'CREATE INDEX `idx_table_shop_area` ON `t_table` (`shop_id`, `area_code`)',
  'SELECT 1'
);
PREPARE stmt_idx_area FROM @ddl_idx_area;
EXECUTE stmt_idx_area;
DEALLOCATE PREPARE stmt_idx_area;

-- API permissions for table coordination endpoints
INSERT INTO `t_api_permission` (`method`, `path_pattern`, `permission_code`, `remark`) VALUES
('*', '/api/pos/table-areas', 'cashier:operate|table:view', 'POS桌台-区域字典'),
('*', '/cashier/table/areas', 'cashier:operate|table:view', '收银桌台-区域字典'),
('*', '/api/pos/orders/*/diners', 'cashier:operate|order:operate', 'POS订单-调整就餐人数'),
('*', '/cashier/orders/*/diners', 'cashier:operate|order:operate', '收银订单-调整就餐人数'),
('*', '/api/pos/tables/batch-clear', 'cashier:operate|table:operate', 'POS桌台-批量清台'),
('*', '/cashier/table/batch-clear', 'cashier:operate|table:operate', '收银桌台-批量清台'),
('*', '/api/pos/tables/pulse', 'cashier:operate|table:view', 'POS桌台-实时经营脉搏'),
('*', '/cashier/table/pulse', 'cashier:operate|table:view', '收银桌台-实时经营脉搏')
ON DUPLICATE KEY UPDATE
  `method`=VALUES(`method`),
  `permission_code`=VALUES(`permission_code`),
  `remark`=VALUES(`remark`);
