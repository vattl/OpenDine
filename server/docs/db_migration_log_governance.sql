-- ============================================================
-- 日志模块治理加固（v1.2.237）
-- 补：t_order_log.shop_id 门店隔离列 + 三张日志表主键/索引 + 保留策略落地说明
-- 幂等：基于 information_schema 判断，可重复执行；已存在的定义自动跳过。
-- 前提：t_operation_log / t_order_log 的 id 由 MyBatis-Plus ASSIGN_ID（雪花）生成，
--       全局唯一且非空；若存量存在 id 重复（理论不发生）会报错，需先人工去重。
-- ============================================================

-- 1) t_order_log 补门店隔离列 shop_id（存量行为 NULL，兼容历史数据）
SET @has_col := (SELECT COUNT(*) FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 't_order_log' AND column_name = 'shop_id');
SET @sql := IF(@has_col = 0,
  'ALTER TABLE `t_order_log` ADD COLUMN `shop_id` int(11) DEFAULT NULL COMMENT ''门店ID，审计隔离'' AFTER `id`',
  'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 2) t_operation_log 补主键（缺失时）
SET @has_pk := (SELECT COUNT(*) FROM information_schema.table_constraints
  WHERE table_schema = DATABASE() AND table_name = 't_operation_log' AND constraint_type = 'PRIMARY KEY');
SET @sql := IF(@has_pk = 0, 'ALTER TABLE `t_operation_log` ADD PRIMARY KEY (`id`)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 3) t_order_log 补主键（缺失时）
SET @has_pk := (SELECT COUNT(*) FROM information_schema.table_constraints
  WHERE table_schema = DATABASE() AND table_name = 't_order_log' AND constraint_type = 'PRIMARY KEY');
SET @sql := IF(@has_pk = 0, 'ALTER TABLE `t_order_log` ADD PRIMARY KEY (`id`)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 3.5) t_dish_stock_log 建表（线上库若缺失直接建表；建表定义含主键与索引，后续步骤自动跳过）
CREATE TABLE IF NOT EXISTS `t_dish_stock_log` (
  `id` bigint AUTO_INCREMENT PRIMARY KEY,
  `shop_id` int NOT NULL COMMENT '门店ID',
  `dish_id` int NOT NULL COMMENT '菜品ID',
  `dish_name` varchar(128) DEFAULT NULL COMMENT '菜品名称',
  `order_no` varchar(64) DEFAULT NULL COMMENT '关联订单号',
  `detail_id` int DEFAULT NULL COMMENT '关联订单明细ID',
  `change_type` varchar(32) NOT NULL COMMENT '变动类型：CREATE_ORDER/ADD_DISH/CANCEL_ORDER/REFUND_RESTORE/REFUND_NO_RESTORE/REFUND_OUT_OF_STOCK/ADMIN_MANUAL/KDS_LACK',
  `delta` int NOT NULL COMMENT '变动数量(+增/-减/0不变)',
  `stock_before` int DEFAULT NULL COMMENT '变动前库存',
  `stock_after` int DEFAULT NULL COMMENT '变动后库存',
  `operator_id` varchar(64) DEFAULT NULL COMMENT '操作人/终端',
  `remark` varchar(255) DEFAULT NULL COMMENT '备注/退菜原因',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_shop_dish_time` (`shop_id`, `dish_id`, `created_at`),
  INDEX `idx_order_no` (`order_no`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='菜品库存变动流水日志表';

-- 4) t_dish_stock_log 补主键（缺失时；上一步建表已含主键则自动跳过）
SET @has_pk := (SELECT COUNT(*) FROM information_schema.table_constraints
  WHERE table_schema = DATABASE() AND table_name = 't_dish_stock_log' AND constraint_type = 'PRIMARY KEY');
SET @sql := IF(@has_pk = 0, 'ALTER TABLE `t_dish_stock_log` ADD PRIMARY KEY (`id`)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 5) t_operation_log 补 (shop_id, created_at) 索引（在线查询/归档检索主路径）
SET @has_idx := (SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 't_operation_log' AND index_name = 'idx_log_shop_created');
SET @sql := IF(@has_idx = 0,
  'CREATE INDEX `idx_log_shop_created` ON `t_operation_log` (`shop_id`, `created_at`)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 6) t_order_log 补 (shop_id, created_at) 索引
SET @has_idx := (SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 't_order_log' AND index_name = 'idx_log_shop_created');
SET @sql := IF(@has_idx = 0,
  'CREATE INDEX `idx_log_shop_created` ON `t_order_log` (`shop_id`, `created_at`)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 7) t_dish_stock_log 补 (created_at) 索引（清理任务按时间裁剪）
SET @has_idx := (SELECT COUNT(*) FROM information_schema.statistics
  WHERE table_schema = DATABASE() AND table_name = 't_dish_stock_log' AND index_name = 'idx_stock_created');
SET @sql := IF(@has_idx = 0,
  'CREATE INDEX `idx_stock_created` ON `t_dish_stock_log` (`created_at`)', 'SELECT 1');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 8) 保留策略物理清理落地说明
--    之前仅查询侧窗口裁剪（db_migration_report_logs.sql 注明“本库不物理删除历史数据”），
--    现由 LogRetentionCleanupTask 每日执行物理删除：created_at < now - log.retention-days（默认 400 天），
--    覆盖 t_operation_log / t_order_log / t_dish_stock_log 三表；删除量计入日志并限制单批行数。
--    400 天 > 查询侧 365 天边界，保证查询/归档/导出可窗口永不返回被删数据。
