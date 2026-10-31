-- WI-034: combo commercialization fields required by Combo entity.
-- Every statement is independently idempotent so a partially applied migration can resume safely.

SET @schema_name = DATABASE();

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN limit_per_order INT NULL DEFAULT NULL COMMENT ''单笔订单限购份数，NULL或<=0表示不限'' AFTER status',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='limit_per_order');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN limit_per_user INT NULL DEFAULT NULL COMMENT ''单用户限购份数，NULL或<=0表示不限'' AFTER limit_per_order',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='limit_per_user');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN limit_cycle VARCHAR(20) NOT NULL DEFAULT ''daily'' COMMENT ''用户限购周期：daily(每日)|lifetime(终生)'' AFTER limit_per_user',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='limit_cycle');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN start_time DATETIME NULL DEFAULT NULL COMMENT ''活动生效开始时间，NULL表示不限'' AFTER limit_cycle',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='start_time');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN end_time DATETIME NULL DEFAULT NULL COMMENT ''活动生效截止时间，NULL表示不限'' AFTER start_time',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='end_time');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN available_days VARCHAR(32) NULL DEFAULT NULL COMMENT ''可用星期，逗号分隔，NULL表示不限'' AFTER end_time',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='available_days');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN time_range_start VARCHAR(16) NULL DEFAULT NULL COMMENT ''每日可用起始时段，如 11:00'' AFTER available_days',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='time_range_start');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN time_range_end VARCHAR(16) NULL DEFAULT NULL COMMENT ''每日可用截止时段，如 14:00'' AFTER time_range_start',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='time_range_end');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN apply_dining_type VARCHAR(20) NOT NULL DEFAULT ''all'' COMMENT ''适用就餐方式：all|dine_in|take_out'' AFTER time_range_end',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='apply_dining_type');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN allow_coupon TINYINT NOT NULL DEFAULT 1 COMMENT ''是否允许叠加优惠券：1允许 0禁止'' AFTER apply_dining_type',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='allow_coupon');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @ddl = (SELECT IF(COUNT(*) = 0,
  'ALTER TABLE t_combo ADD COLUMN daily_stock INT NULL DEFAULT NULL COMMENT ''每日套餐配额，NULL表示不限'' AFTER allow_coupon',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@schema_name AND TABLE_NAME='t_combo' AND COLUMN_NAME='daily_stock');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
