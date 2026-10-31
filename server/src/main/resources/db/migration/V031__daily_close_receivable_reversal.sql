-- WI-029: preserve receivable reversals in immutable daily-close snapshots.
SET @dbname = DATABASE();
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_daily_close_snapshot ADD COLUMN receivable_reversed_fen BIGINT NOT NULL DEFAULT 0 COMMENT ''营业窗口挂账撤销金额(分)'' AFTER receivable_writeoff_fen',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_daily_close_snapshot' AND COLUMN_NAME='receivable_reversed_fen');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
