-- ============================================================================
-- db_migration_order_business_report_indexes.sql
-- 跨天营业日报按门店与支付时间聚合的性能索引（C012）
-- 幂等、仅新增索引，兼容 MySQL 8.0。
-- 执行：mysql -u<user> -p db_diancan < db_migration_order_business_report_indexes.sql
-- 校验：SHOW INDEX FROM t_order WHERE Key_name IN
--       ('idx_order_shop_pay_time', 'idx_order_shop_time');
-- 回滚：DROP INDEX idx_order_shop_pay_time ON t_order;
-- ============================================================================

SET @report_index_db = DATABASE();

SET @report_index_sql = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_order ADD KEY idx_order_shop_pay_time (shop_id, pay_time)',
  'SELECT ''idx_order_shop_pay_time exists, skip''')
  FROM information_schema.statistics
  WHERE table_schema = @report_index_db
    AND table_name = 't_order'
    AND index_name = 'idx_order_shop_pay_time');

PREPARE report_index_stmt FROM @report_index_sql;
EXECUTE report_index_stmt;
DEALLOCATE PREPARE report_index_stmt;
