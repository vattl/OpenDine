-- =========================================================================
-- 商业化收银交班与日结补丁脚本 (支持标准 MySQL 5.7 / 8.0 / 8.4 LTS)
-- 执行方式: mysql -u <用户名> -p <数据库名> < patch_commercial_shift_columns.sql
-- =========================================================================

-- 1. 给 t_shift 补充钱箱与商用化审计关联字段
SET @dbname = DATABASE();
SET @tablename = 't_shift';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'drawer_session_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `drawer_session_id` BIGINT DEFAULT NULL COMMENT ''关联钱箱会话ID'''
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'terminal_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `terminal_id` VARCHAR(64) DEFAULT NULL COMMENT ''终端编号'''
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'state') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `state` VARCHAR(32) DEFAULT ''OPEN'' COMMENT ''状态：OPEN/CLOSED'''
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'business_day') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `business_day` VARCHAR(16) DEFAULT NULL COMMENT ''归属营业日(YYYY-MM-DD)'''
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'version') > 0,
  'SELECT 1',
  'ALTER TABLE `t_shift` ADD COLUMN `version` INT DEFAULT 1 COMMENT ''乐观锁版本'''
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 2. 给 t_daily_stat 添加快照外键关联
SET @tablename = 't_daily_stat';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'snapshot_id') > 0,
  'SELECT 1',
  'ALTER TABLE `t_daily_stat` ADD COLUMN `snapshot_id` BIGINT DEFAULT NULL COMMENT ''关联不可变日结快照ID'''
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 3. 给 t_payment_ledger 增加 source 与 trust_level 字段
SET @tablename = 't_payment_ledger';

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'source') > 0,
  'SELECT 1',
  'ALTER TABLE `t_payment_ledger` ADD COLUMN `source` VARCHAR(32) NOT NULL DEFAULT ''NATIVE'' COMMENT ''数据来源：NATIVE/BACKFILLED_ORDER/MANUAL'' AFTER `status`'
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @preparedStatement = (SELECT IF(
  (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = @dbname AND TABLE_NAME = @tablename AND COLUMN_NAME = 'trust_level') > 0,
  'SELECT 1',
  'ALTER TABLE `t_payment_ledger` ADD COLUMN `trust_level` VARCHAR(32) NOT NULL DEFAULT ''TRUST_HIGH'' COMMENT ''可信等级：TRUST_HIGH/TRUST_MEDIUM/TRUST_SUSPECT'' AFTER `source`'
));
PREPARE stmt FROM @preparedStatement;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
