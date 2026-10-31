-- WI-031: Cashier order park / hang status and metadata
SET @dbname = DATABASE();
SET @sql = (SELECT IF(COUNT(*)=0,
  'ALTER TABLE t_order ADD COLUMN hang_status TINYINT NOT NULL DEFAULT 0 COMMENT ''挂单状态: 0正常未挂单 1挂单中'', ADD COLUMN hang_time DATETIME NULL COMMENT ''挂单时间'', ADD COLUMN hang_reason VARCHAR(255) NULL COMMENT ''挂单原因'', ADD COLUMN hang_admin_id INT NULL COMMENT ''挂单操作员工ID''',
  'SELECT 1') FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA=@dbname AND TABLE_NAME='t_order' AND COLUMN_NAME='hang_status');
PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt;
