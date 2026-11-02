-- LEGACY_TRANSITIONAL: retained because scripts/setup-debug.ps1 still applies it.
-- It is not an architecture source and must not introduce a cashier-local KDS authority.
-- Target architecture: docs/KDS_ARCHITECTURE.md (KDS-CA-1.0).
-- Cashier cloud-first / local KDS coordination (MySQL 8.0+)
-- Idempotent: safe to execute again before deploying the matching backend JAR.

DROP PROCEDURE IF EXISTS `migrate_cashier_cloud_first_kds`;
DELIMITER $$
CREATE PROCEDURE `migrate_cashier_cloud_first_kds`()
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_order_client_request'
      AND COLUMN_NAME='request_fingerprint'
  ) THEN
    ALTER TABLE `t_order_client_request`
      ADD COLUMN `request_fingerprint` char(64) NULL
        COMMENT 'SHA-256 of the canonical request body' AFTER `request_path`;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_order_detail'
      AND COLUMN_NAME='client_line_id'
  ) THEN
    ALTER TABLE `t_order_detail`
      ADD COLUMN `client_line_id` varchar(64) NULL
        COMMENT 'Cashier client line correlation ID' AFTER `cid`;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_order_detail'
      AND COLUMN_NAME='refunded_quantity'
  ) THEN
    ALTER TABLE `t_order_detail`
      ADD COLUMN `refunded_quantity` int NOT NULL DEFAULT 0
        COMMENT 'Cumulative refunded quantity' AFTER `quantity`;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='t_order_detail'
      AND INDEX_NAME='idx_order_detail_client_line'
  ) THEN
    ALTER TABLE `t_order_detail`
      ADD INDEX `idx_order_detail_client_line` (`mId`, `client_line_id`);
  END IF;
END$$
DELIMITER ;

CALL `migrate_cashier_cloud_first_kds`();
DROP PROCEDURE `migrate_cashier_cloud_first_kds`;
